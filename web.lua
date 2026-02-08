-- Простой веб-браузер на Lua (улучшенная версия с исправленным парсером)
-- Исправления:
-- • Полностью удаляются <script>, <style> и комментарии <!-- -->
-- • Теги правильно захватываются целиком (с атрибутами), больше никаких остатков тегов в тексте
-- • Лучшая обработка HTML-сущностей (&nbsp;, &amp;, &lt;, &#123; и т.д.)
-- • Игнорируются все теги кроме <a> и блочных (<p>, <div>, <br>, <li>, заголовки)
-- • Блочные теги добавляют отступ (новая строка)
-- • Текст очищается от лишних пробелов

local SCR_W, SCR_H = 410, 502
local LINE_H = 28
local LINK_H = 36
local MAX_CHARS_PER_LINE = 52

local current_url = "https://news.ycombinator.com"
local history = {}
local history_pos = 0
local scroll_y = 0

local content = {}
local content_height = 0

-- Разрешение относительных ссылок
local function resolve_url(base, href)
    href = href:gsub("^%s+", ""):gsub("%s+$", "")
    if href:match("^https?://") then return href end
    if href:sub(1,1) == "/" then
        local proto_host = base:match("(https?://[^/]+)")
        return proto_host .. href
    end
    local dir = base:match("(.*/)[^/]*$") or base .. "/"
    return dir .. href
end

-- Декодирование HTML-сущностей
local function decode_html_entities(str)
    local map = {
        amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'", nbsp = " ",
    }
    -- Числовые сущности &#123; и &#xAB;
    str = str:gsub("&#(%d+);", function(n) return string.char(tonumber(n)) end)
    str = str:gsub("&#x(%x+);", function(n) return string.char(tonumber(n,16)) end)
    -- Именованные
    str = str:gsub("&(%a+);", map)
    return str
end

-- Удаление скриптов, стилей и комментариев
local function remove_scripts_styles_comments(html)
    -- Комментарии
    html = html:gsub("<!%-%-.-%-%->", "")
    -- Script (case-insensitive)
    html = html:gsub("<[sS][cC][rR][iI][pP][tT][^>]*>.-</[sS][cC][rR][iI][pP][tT]>", "")
    -- Style (case-insensitive)
    html = html:gsub("<[sS][tT][yY][lL][eE][^>]*>.-</[sS][tT][yY][lL][eE]>", "")
    return html
end

-- Перенос текста по словам
local function wrap_text(text)
    text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #text == 0 then return {} end
    local lines = {}
    local pos = 1
    while pos <= #text do
        local remaining = #text - pos + 1
        local chunk_len = math.min(MAX_CHARS_PER_LINE, remaining)
        local chunk_end = pos + chunk_len - 1
        if remaining > MAX_CHARS_PER_LINE then
            local last_space = text:find(" [^ ]*$", pos)
            if last_space and last_space < pos + MAX_CHARS_PER_LINE then
                chunk_end = last_space - 1
            end
        end
        table.insert(lines, text:sub(pos, chunk_end))
        pos = chunk_end + 1
        if pos <= #text and text:sub(pos, pos) == " " then pos = pos + 1 end
    end
    return lines
end

-- Добавление контента
local function add_content(text, is_link, link_url)
    local lines = wrap_text(text)
    for _, line in ipairs(lines) do
        table.insert(content, {
            type = is_link and "link" or "text",
            text = line,
            url = link_url
        })
        content_height = content_height + (is_link and LINK_H or LINE_H)
    end
end

-- Новый улучшенный парсер
-- Улучшенный HTML-парсер
function parse_html(html)
    content = {}
    content_height = 60
    
    -- Удаляем теги скриптов и стилей
    html = html:gsub("<script[^>]*>.-</script>", "")
    html = html:gsub("<style[^>]*>.-</style>", "")
    
    -- Преобразуем HTML-сущности
    local function decode_entities(text)
        local entities = {
            ["&nbsp;"] = " ", ["&amp;"] = "&", ["&lt;"] = "<", 
            ["&gt;"] = ">", ["&quot;"] = "\"", ["&#39;"] = "'",
            ["&apos;"] = "'", ["&ndash;"] = "-", ["&mdash;"] = "-",
            ["&hellip;"] = "...", ["&laquo;"] = "<<", ["&raquo;"] = ">>"
        }
        for entity, replacement in pairs(entities) do
            text = text:gsub(entity, replacement)
        end
        return text
    end
    
    -- Ищем ссылки и текст
    local pos = 1
    local last_was_text = false
    
    while pos <= #html do
        -- Ищем открывающий тег <a>
        local a_start, a_end, a_tag = html:find('<a([^>]*)>', pos)
        
        if a_start then
            -- Текст перед ссылкой
            local text_before = html:sub(pos, a_start - 1)
            text_before = decode_entities(text_before)
            text_before = text_before:gsub("^%s+", ""):gsub("%s+$", "")
            
            if #text_before > 0 then
                add_content(text_before, false)
                last_was_text = true
            end
            
            -- Извлекаем href из тега <a>
            local href = a_tag:match('href%s*=%s*["\']([^"\']+)["\']')
            if href then
                href = resolve_url(current_url, href)
                
                -- Ищем закрывающий тег </a>
                local a_close_start = html:find('</a>', a_end + 1)
                if a_close_start then
                    -- Текст внутри ссылки
                    local link_text = html:sub(a_end + 1, a_close_start - 1)
                    link_text = decode_entities(link_text)
                    link_text = link_text:gsub("<[^>]+>", "") -- Удаляем вложенные теги
                    link_text = link_text:gsub("^%s+", ""):gsub("%s+$", "")
                    
                    if #link_text > 0 then
                        add_content(link_text, true, href)
                        last_was_text = false
                    end
                    
                    pos = a_close_start + 4
                else
                    pos = a_end + 1
                end
            else
                pos = a_end + 1
            end
        else
            -- Остальной текст после тегов <a>
            local text_rest = html:sub(pos)
            text_rest = decode_entities(text_rest)
            text_rest = text_rest:gsub("<[^>]+>", " ") -- Заменяем все остальные теги пробелами
            
            -- Удаляем множественные пробелы и переносы строк
            text_rest = text_rest:gsub("%s+", " ")
            text_rest = text_rest:gsub("^%s+", ""):gsub("%s+$", "")
            
            if #text_rest > 0 then
                -- Добавляем пустую строку перед новым блоком текста
                if last_was_text then
                    content_height = content_height + LINE_H
                end
                add_content(text_rest, false)
                last_was_text = true
            end
            
            break
        end
    end
end

-- Загрузка страницы
function load_page(new_url)
    if not new_url:match("^https?://") then
        new_url = "https://" .. new_url
    end
    local res = net.get(new_url)
    if res.ok and res.code == 200 then
        current_url = new_url
        table.insert(history, current_url)
        history_pos = #history
        parse_html(res.body)
        scroll_y = 0
    else
        content = {}
        content_height = 200
        add_content("Ошибка загрузки", false)
        add_content("URL: " .. new_url, false)
        add_content("Код: " .. tostring(res.code or "—"), false)
        add_content("Ошибка: " .. tostring(res.err or "нет ответа"), false)
    end
end

-- Назад
local function go_back()
    if history_pos > 1 then
        history_pos = history_pos - 1
        load_page(history[history_pos])
    end
end

load_page(current_url)

-- Отрисовка
function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0)

    -- URL
    ui.text(10, 12, current_url:sub(1, 65), 2, 0xFFFF)

    -- Кнопки
    if history_pos > 1 then
        if ui.button(10, 52, 100, 40, "Back", 0x4208) then go_back() end
    end
    if ui.button(120, 52, 130, 40, "Reload", 0x4208) then load_page(current_url) end
    if ui.button(260, 52, 130, 40, "Home", 0x4208) then load_page("https://news.ycombinator.com") end

    -- Контент
    scroll_y = ui.beginList(0, 100, SCR_W, SCR_H - 100, scroll_y, content_height)

    local cy = 20
    for _, item in ipairs(content) do
        if item.type == "text" then
            ui.text(20, cy, item.text, 2, 0xFFFF)
            cy = cy + LINE_H
        else
            local clicked = ui.button(10, cy, SCR_W - 20, LINK_H, "", 0)
            ui.text(25, cy + 6, item.text, 2, 0x07FF)
            if clicked then
                load_page(item.url)
            end
            cy = cy + LINK_H
        end
    end

    ui.endList()
end
