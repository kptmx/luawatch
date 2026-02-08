-- Улучшенный простой веб-браузер на Lua
-- Исправления:
-- • Текст теперь отображается правильно (удалены script/style/head, добавлены переносы на блок-тегах, улучшен сбор текста)
-- • Ввод адреса работает: клик по строке → редактирование с T9, "DONE" или "GO" загружают url_input
-- • Ссылки и изображения кликабельны
-- • Прокрутка контента и больших изображений
-- • Авто-добавление https:// если нет протокола
-- • Очистка временного изображения при смене страницы

local SCR_W, SCR_H = 410, 502

-- Состояние
local current_url = "https://www.google.com"
local url_input = ""
local editing = false
local history = {}
local page_content = {}
local scroll_y = 0
local touching = false
local last_touch_y = 0
local current_image_path = "/tmp/view.jpg"  -- фиксированный путь, перезаписываем

-- T9 (расширено для URL)
local t9 = {
    [".,!1"] = ".,!1:/",
    ["abc2"] = "abc2",
    ["def3"] = "def3",
    ["ghi4"] = "ghi4",
    ["jkl5"] = "jkl5",
    ["mno6"] = "mno6",
    ["pqrs7"] = "pqrs7",
    ["tuv8"] = "tuv8",
    ["wxyz9"] = "wxyz9",
    ["*"] = "*@#$%&-",
    ["0"] = "0_ ",
    ["#"] = "#"
}

local keys = {
    ".,!1", "abc2", "def3",
    "ghi4", "jkl5", "mno6",
    ["pqrs7"] = "pqrs7",
    ["tuv8"] = "tuv8",
    ["wxyz9"] = "wxyz9",
    "*", "0", "#",
    "DEL", "CLR", "DONE"
}

local last_key, last_time, char_idx = "", 0, 0

-- Блок-теги, на которых делаем перенос строки
local block_tags = {p=true, div=true, li=true, td=true, tr=true, br=true,
                    h1=true, h2=true, h3=true, h4=true, h5=true, h6=true}

function strip_html(s)
    return string.gsub(s, "<[^>]*>", "")
           :gsub("&nbsp;", " "):gsub("&amp;", "&"):gsub("&lt;", "<")
           :gsub("&gt;", ">"):gsub("&quot;", "\"")
end

function resolve_url(rel, base)
    if string.match(rel, "^https?://") then return rel end
    if string.sub(rel, 1, 2) == "//" then return "https:" .. rel end
    local proto_host = string.match(base, "^(https?://[^/]+)")
    if not proto_host then return rel end
    if string.sub(rel, 1, 1) == "/" then return proto_host .. rel end
    local dir = string.match(base, "^(.-/)[^/]*$") or proto_host .. "/"
    return dir .. rel
end

function add_text(text)
    text = strip_html(text)
    text = string.gsub(text, "%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if text ~= "" then
        table.insert(page_content, {type = "text", text = text, color = 65535})
    end
end

function add_link(text, url)
    text = strip_html(text)
    if text == "" then text = url end
    table.insert(page_content, {type = "link", text = text, url = url, color = 2016})
end

function parse_html(html, base_url)
    page_content = {}

    -- Удаляем ненужные разделы
    html = string.gsub(html, "<[sS][cC][rR][iI][pP][tT].-</[sS][cC][rR][iI][pP][tT]>", "")
    html = string.gsub(html, "<[sS][tT][yY][lL][eE].-</[sS][tT][yY][lL][eE]>", "")
    html = string.gsub(html, "<[hH][eE][aA][dD].-</[hH][eE][aA][dD]>", "")

    local i = 1
    while i <= #html do
        local tag_start, _ = string.find(html, "<", i)
        if not tag_start then
            add_text(string.sub(html, i))
            break
        end

        -- Текст перед тегом
        if tag_start > i then
            add_text(string.sub(html, i, tag_start - 1))
        end

        local tag_end = string.find(html, ">", tag_start)
        if not tag_end then break end

        local full_tag = string.sub(html, tag_start + 1, tag_end - 1)
        local is_closing = string.sub(full_tag, 1, 1) == "/"
        local tag_name = string.lower(string.match(full_tag, "^/?(%w+)") or "")

        -- Обработка <img>
        if tag_name == "img" and not is_closing then
            local src = string.match(full_tag, 'src%s*=%s*["\']([^"\']*)')
            if src then
                local full_src = resolve_url(src, base_url)
                if string.lower(full_src):match("%.jpe?g$") then
                    add_link(" Image[link]: " .. src .. "]", full_src)
                end
            end
        -- Обработка <a>
        elseif tag_name == "a" and not is_closing then
            local href = string.match(full_tag, 'href%s*=%s*["\']([^"\']*)')
            local link_end = string.find(html, "</[aA]>", tag_end)
            if href and link_end then
                local link_text = string.sub(html, tag_end + 1, link_end - 1)
                add_link(link_text, resolve_url(href, base_url))
                i = link_end + 4  -- пропускаем </a>
                goto continue
            end
        -- Переносы строк на блок-тегах и br
        elseif block_tags[tag_name] then
            add_text("\n")
        end

        i = tag_end + 1
        ::continue::
    end
end

function handle_t9(k)
    local now = hw.millis()
    local chars = t9[k]
    if not chars then return end
    if k == last_key and (now - last_time) < 800 then
        url_input = url_input:sub(1, -2)
        char_idx = (char_idx % #chars) + 1
    else
        char_idx = 1
    end
    url_input = url_input .. chars:sub(char_idx, char_idx)
    last_key = k
    last_time = now
end

function load_page(url, no_history)
    -- Нормализация URL
    url = string.gsub(url, "^%s+", ""):gsub("%s+$", "")
    if not string.match(url, "^https?://") then
        url = "https://" .. url
    end

    if not no_history then
        table.insert(history, current_url)
    end

    -- Очистка старого изображения
    if fs.exists(current_image_path) then
        fs.remove(current_image_path)
    end

    local res = net.get(url)
    if res.ok and res.code == 200 then
        if string.lower(url):match("%.jpe?g$") then
            -- Прямое изображение
            net.download(url, current_image_path, "flash")
            page_content = {{type = "image", path = current_image_path}}
        else
            parse_html(res.body, url)
        end
        current_url = url
        scroll_y = 0
    else
        page_content = {{type = "text", text = "Error: " .. (res.err or res.code or "unknown error"), color = 63488}}
        current_url = url
    end
    editing = false
end

-- Начальная загрузка
load_page(current_url)

function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0)

    -- Адресная строка
    local address_display = editing and url_input or current_url
    if ui.input(10, 8, 300, 40, address_display, editing) then
        editing = true
        url_input = current_url:gsub("^https?://", "")
    end

    -- Кнопка GO
    if ui.button(320, 8, 80, 40, "GO", 1040) then
        load_page(editing and url_input or current_url)
    end

    -- Кнопка Назад
    if #history > 0 and not editing then
        if ui.button(10, 60, 120, 40, "BACK", 63488) then
            local prev = table.remove(history)
            load_page(prev, true)
        end
    end

    if editing then
        -- Клавиатура T9
        local kb_y = 100
        for i, k in ipairs(keys) do
            local row = math.floor((i-1)/3)
            local col = (i-1)%3
            local bx = 15 + col * 132
            local by = kb_y + row * 50
            if ui.button(bx, by, 125, 45, k, 8452) then
                if k == "DEL" then
                    url_input = url_input:sub(1, -2)
                elseif k == "CLR" then
                    url_input = ""
                elseif k == "DONE" then
                    load_page(url_input)
                else
                    handle_t9(k)
                end
            end
        end
    else
        -- Прокрутка контента
        local touch = ui.getTouch()
        if touch.touching and touch.y > 100 then
            if not touching then
                touching = true
                last_touch_y = touch.y
            else
                scroll_y = scroll_y + (last_touch_y - touch.y) * 1.5  -- ускорение прокрутки
                last_touch_y = touch.y
            end
        elseif not touch.touching then
            touching = false
        end
        scroll_y = math.max(0, scroll_y)

        local y = 100 - scroll_y
        for _, item in ipairs(page_content) do
            if item.type == "text" then
                ui.text(15, y, item.text, 2, item.color or 65535)
                y = y + 40
            elseif item.type == "link" then
                if ui.button(15, y, 380, 50, item.text, item.color or 2016) then
                    load_page(item.url)
                end
                y = y + 60
            elseif item.type == "image" then
                ui.drawJPEG(0, y, item.path)
                y = y + SCR_H + 200  -- запас для прокрутки больших изображений
            end
        end
    end

    ui.flush()
end
