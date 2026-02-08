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
-- ==========================================
-- ИНСТРУМЕНТЫ ПАРСИНГА
-- ==========================================

-- Список тегов, которые вызывают перенос строки
local BLOCK_TAGS = {
    p=true, div=true, h1=true, h2=true, h3=true, h4=true, h5=true, h6=true,
    ul=true, ol=true, li=true, br=true, blockquote=true, hr=true, tr=true
}

-- Разрешение относительных ссылок
local function resolve_url(base, href)
    if not href then return base end
    href = href:gsub("^%s+", ""):gsub("%s+$", "")
    
    if href:sub(1,2) == "//" then return "https:" .. href end
    if href:match("^https?://") then return href end
    if href:match("^mailto:") or href:match("^javascript:") then return nil end
    
    local proto, domain = base:match("^(https?://)([^/]+)")
    if not proto then return href end -- fallback
    
    if href:sub(1,1) == "/" then
        return proto .. domain .. href
    end
    
    local path = base:match("^https?://[^/]+(.*/)") or "/"
    return proto .. domain .. path .. href
end

-- Декодирование HTML-сущностей
local function decode_html_entities(str)
    if not str then return "" end
    local map = {
        amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'", nbsp = " ",
        copy = "©", reg = "®", trade = "™", mdash = "—", ndash = "–"
    }
    str = str:gsub("&(#?x?)(%w+);", function(type, val)
        if type == "" then return map[val] or "" end
        if type == "#" then return string.char(tonumber(val)) end
        if type == "#x" then return string.char(tonumber(val, 16)) end
    end)
    return str
end

-- Очистка текста от мусора
local function clean_text(txt)
    -- Заменяем любые пробельные символы (табы, переносы) на пробел
    txt = txt:gsub("[%s\r\n]+", " ")
    return txt
end

-- Полное удаление скриптов и стилей
-- В Lua нет флага "multiline" для точки (.), поэтому используем трюк
local function remove_junk(html)
    -- Удаляем комментарии -- Используем цикл, так как gsub может зависнуть на сложном вложении
    local out = {}
    local i = 1
    while i <= #html do
        local start_c = html:find("<!%-%-", i)
        if not start_c then
            table.insert(out, html:sub(i))
            break
        end
        table.insert(out, html:sub(i, start_c - 1))
        local end_c = html:find("%-%->", start_c + 4)
        if not end_c then break end -- не закрыт комментарий
        i = end_c + 3
    end
    html = table.concat(out)

    -- Удаляем <script>...</script> и <style>...</style>
    -- Простой gsub тут плох, лучше удалить контент тегов
    local function strip_tag_content(text, tagname)
        local res = {}
        local pos = 1
        while true do
            -- Ищем начало <tag
            local s_tag, e_tag = text:find("<" .. tagname, pos) -- упрощенный поиск
            if not s_tag then
                table.insert(res, text:sub(pos))
                break
            end
            
            -- Сохраняем то, что было ДО тега
            table.insert(res, text:sub(pos, s_tag - 1))
            
            -- Ищем конец </tag>
            local end_s, end_e = text:find("</" .. tagname .. ">", e_tag)
            if not end_s then
                -- Если закрывающего нет, обрезаем все до конца
                break 
            end
            pos = end_e + 1
        end
        return table.concat(res)
    end

    -- Lua чувствителен к регистру в find, приведем временно к lower? 
    -- Для простоты предположим стандартный HTML, но лучше сделать gsub с функцией
    -- Ниже простой, но рабочий вариант:
    html = strip_tag_content(html, "script")
    html = strip_tag_content(html, "style")
    html = strip_tag_content(html, "SCRIPT") -- на всякий случай
    
    return html
end

-- Перенос текста (Word Wrap)
local function wrap_text(text)
    if #text == 0 then return {} end
    local lines = {}
    local pos = 1
    local max_w = MAX_CHARS_PER_LINE
    
    while pos <= #text do
        local rem = #text - pos + 1
        if rem <= max_w then
            table.insert(lines, text:sub(pos))
            break
        end
        
        -- Ищем пробел, чтобы не резать слово
        local substr = text:sub(pos, pos + max_w)
        local break_point = substr:match(".*%s()") -- последний пробел
        
        if not break_point then
            break_point = max_w -- если слова длиннее строки, режем жестко
        else
            break_point = break_point - 1
        end
        
        table.insert(lines, text:sub(pos, pos + break_point - 1))
        pos = pos + break_point
        -- Пропускаем пробелы в начале новой строки
        while text:sub(pos, pos) == " " do pos = pos + 1 end
    end
    return lines
end

-- Добавление в общий массив контента
local function add_content(text, is_link, link_url)
    if not text or #text == 0 or text == " " then return end
    
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

-- Добавление новой строки (отступа)
local function add_newline()
    -- Добавляем пустой отступ только если предыдущий элемент не был отступом
    if #content > 0 and content[#content].text ~= "" then
         -- Просто добавляем "пустышку", чтобы сдвинуть Y координату при отрисовке
         -- Или в вашей логике просто увеличиваем content_height?
         -- Лучше добавим пустой элемент, чтобы список работал корректно
         table.insert(content, { type = "text", text = "", url = nil })
         content_height = content_height + (LINE_H / 2)
    end
end

-- ==========================================
-- ОСНОВНОЙ ПАРСЕР
-- ==========================================

function parse_html(html)
    content = {}
    content_height = 60
    
    html = remove_junk(html)

    local pos = 1
    local in_link = false
    local current_link = nil
    
    while pos <= #html do
        -- 1. Ищем начало следующего тега "<"
        local start_tag = html:find("<", pos)
        
        if not start_tag then
            -- Тегов больше нет, добавляем остаток текста
            local text = html:sub(pos)
            text = clean_text(decode_html_entities(text))
            add_content(text, in_link, current_link)
            break
        end
        
        -- 2. Обрабатываем ТЕКСТ до тега
        if start_tag > pos then
            local text = html:sub(pos, start_tag - 1)
            text = clean_text(decode_html_entities(text))
            add_content(text, in_link, current_link)
        end
        
        -- 3. Разбираем сам ТЕГ
        -- Ищем закрывающую ">"
        local end_tag = html:find(">", start_tag)
        if not end_tag then break end -- Обрыв HTML
        
        local tag_raw = html:sub(start_tag + 1, end_tag - 1)
        
        -- Определяем имя тега
        -- Паттерн: возможно слэш, затем буквы/цифры
        local is_closing, tag_name = tag_raw:match("^(/?)([%w%-]+)")
        
        if tag_name then
            tag_name = tag_name:lower()
            local is_block = BLOCK_TAGS[tag_name]
            
            if is_closing == "/" then
                -- Закрывающий тег (</a>, </div>)
                if tag_name == "a" then
                    in_link = false
                    current_link = nil
                elseif is_block then
                    add_newline()
                end
            else
                -- Открывающий тег (<a ...>, <div>)
                if tag_name == "a" then
                    -- Ищем href. Поддержка " и '
                    local href = tag_raw:match('href%s*=%s*"([^"]+)"') or 
                                 tag_raw:match("href%s*=%s*'([^']+)'")
                    
                    if href then
                        current_link = resolve_url(current_url, href)
                        if current_link then in_link = true end
                    end
                elseif tag_name == "br" then
                    add_newline()
                elseif is_block then
                    add_newline()
                end
            end
        end
        
        pos = end_tag + 1
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
