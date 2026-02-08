-- Enhanced Web Browser for LuaWatch
local SW, SH = 410, 502

-- Состояние браузера
local url_input = "https://"
local page_content = {}
local history = {}
local scroll_pos = 0
local max_scroll = 0
local loading = false
local current_title = "Web Browser"
local status_msg = "Ready"
local bookmarks = {}
local zoom = 1.0
local images = {}
local links = {}
local hover_link = nil
local active_link = nil

-- Элементы управления (сдвинуты от краев)
local buttons = {
    {name = "←", x = 20, y = 15, w = 40, h = 35, col = 0x2104, tooltip = "Back"},
    {name = "→", x = 65, y = 15, w = 40, h = 35, col = 0x2104, tooltip = "Forward"},
    {name = "↻", x = 110, y = 15, w = 40, h = 35, col = 0x07E0, tooltip = "Reload"},
    {name = "🏠", x = 155, y = 15, w = 40, h = 35, col = 0x6318, tooltip = "Home"},
    {name = "+", x = 320, y = 15, w = 35, h = 35, col = 0x2104, tooltip = "Zoom In"},
    {name = "-", x = 360, y = 15, w = 35, h = 35, col = 0x2104, tooltip = "Zoom Out"},
}

-- Загрузка закладок
function load_bookmarks()
    if fs.exists("/bookmarks.txt") then
        local data = fs.load("/bookmarks.txt")
        if data then
            bookmarks = {}
            for line in data:gmatch("[^\r\n]+") do
                local title, url = line:match("(.+)|(.+)")
                if title and url then
                    table.insert(bookmarks, {title = title, url = url})
                end
            end
        end
    end
end

-- Сохранение закладок
function save_bookmarks()
    local data = ""
    for _, bm in ipairs(bookmarks) do
        data = data .. bm.title .. "|" .. bm.url .. "\n"
    end
    fs.save("/bookmarks.txt", data)
end

-- Добавить текущую страницу в закладки
function add_bookmark()
    if current_title ~= "Web Browser" and url_input ~= "" then
        table.insert(bookmarks, {title = current_title, url = url_input})
        save_bookmarks()
        status_msg = "✓ Bookmark added"
    end
end

-- Улучшенный парсер HTML с поддержкой ссылок
function parse_html(content, base_url)
    local result = {}
    links = {}
    local link_index = 1
    
    -- Извлекаем заголовок
    local title = content:match("<title[^>]*>(.-)</title>")
    if title then
        current_title = title:gsub("&nbsp;", " "):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"):sub(1, 50)
        table.insert(result, {type = "title", text = "=== " .. current_title .. " ==="})
    end
    
    -- Извлекаем основной текст
    local body = content:match("<body[^>]*>(.-)</body>") or content
    
    -- Удаляем скрипты и стили
    body = body:gsub("<script[^>]*>.-</script>", "")
    body = body:gsub("<style[^>]*>.-</style>", "")
    
    -- Простой парсинг
    local pos = 1
    local in_link = false
    local current_link = nil
    local link_text = ""
    
    while pos <= #body do
        -- Ищем следующий тег
        local tag_start, tag_end = body:find("<[^>]+>", pos)
        
        if not tag_start then
            -- Оставшийся текст
            local remaining = body:sub(pos)
            if in_link and current_link then
                -- Добавляем текст к текущей ссылке
                link_text = link_text .. remaining
                table.insert(result, {
                    type = "link", 
                    text = link_text, 
                    url = current_link,
                    index = link_index
                })
                links[link_index] = {url = current_link, text = link_text}
                link_index = link_index + 1
            elseif remaining:match("%S") then
                table.insert(result, {type = "text", text = remaining})
            end
            break
        end
        
        -- Текст перед тегом
        local text_before = body:sub(pos, tag_start - 1)
        if text_before ~= "" then
            if in_link and current_link then
                link_text = link_text .. text_before
            elseif text_before:match("%S") then
                table.insert(result, {type = "text", text = text_before})
            end
        end
        
        -- Обрабатываем тег
        local tag = body:sub(tag_start, tag_end)
        
        if tag:match("^<a[^>]") then
            -- Начало ссылки
            local href = tag:match('href%s*=%s*["\']([^"\']+)["\']') or
                        tag:match("href%s*=%s*([^%s>]+)")
            
            if href then
                -- Преобразуем относительный URL в абсолютный
                if not href:match("^https?://") then
                    if href:match("^//") then
                        href = "https:" .. href
                    elseif href:match("^/") then
                        local domain = base_url:match("(https?://[^/]+)")
                        if domain then 
                            href = domain .. href 
                        else
                            href = base_url .. href
                        end
                    else
                        -- Относительный URL
                        local base = base_url:match("(.-/)[^/]*$")
                        if base then 
                            href = base .. href 
                        else
                            href = base_url .. "/" .. href
                        end
                    end
                end
                
                in_link = true
                current_link = href
                link_text = ""
            end
            
        elseif tag:match("^</a>") then
            -- Конец ссылки
            if in_link and current_link and link_text:match("%S") then
                table.insert(result, {
                    type = "link", 
                    text = link_text, 
                    url = current_link,
                    index = link_index
                })
                links[link_index] = {url = current_link, text = link_text}
                link_index = link_index + 1
            end
            in_link = false
            current_link = nil
            
        elseif tag:match("^<img[^>]") then
            -- Изображение
            local src = tag:match('src%s*=%s*["\']([^"\']+)["\']')
            local alt = tag:match('alt%s*=%s*["\']([^"\']+)["\']') or "Image"
            
            if src then
                -- Преобразуем относительный URL
                if not src:match("^https?://") then
                    if src:match("^//") then
                        src = "https:" .. src
                    elseif src:match("^/") then
                        local domain = base_url:match("(https?://[^/]+)")
                        if domain then src = domain .. src end
                    else
                        local base = base_url:match("(.-/)[^/]*$")
                        if base then src = base .. src end
                    end
                end
                
                if src then
                    table.insert(result, {
                        type = "image",
                        url = src,
                        alt = alt,
                        placeholder = "[IMG: " .. alt:sub(1, 20) .. "]"
                    })
                end
            end
            
        elseif tag:match("^<br") or tag:match("^<br%s*/?>") then
            table.insert(result, {type = "newline"})
            
        elseif tag:match("^<p[^>]*>") or tag:match("^<div[^>]*>") then
            if not in_link then
                table.insert(result, {type = "newline"})
            end
            
        elseif tag:match("^<h[1-6][^>]*>") then
            if not in_link then
                local heading_text = body:match(">(.-)</h[1-6]>", tag_end)
                if heading_text then
                    heading_text = heading_text:gsub("<[^>]+>", "")
                    if heading_text:match("%S") then
                        table.insert(result, {type = "heading", text = heading_text})
                        local closing_tag = body:find("</h[1-6]>", tag_end)
                        if closing_tag then
                            pos = closing_tag + 4
                            goto continue
                        end
                    end
                end
            end
        end
        
        pos = tag_end + 1
        ::continue::
    end
    
    return result
end

-- Загрузка страницы
function load_page(url)
    if net.status() ~= 3 then
        status_msg = "No internet connection"
        return
    end
    
    if not url:match("^https?://") then
        url = "http://" .. url
        url_input = url
    end
    
    loading = true
    status_msg = "Loading..."
    page_content = {}
    links = {}
    active_link = nil
    hover_link = nil
    
    -- Добавляем в историю
    if #history == 0 or history[#history] ~= url then
        table.insert(history, url)
        if #history > 20 then
            table.remove(history, 1)
        end
    end
    
    local res = net.get(url)
    
    if res and res.ok and res.code == 200 then
        page_content = parse_html(res.body, url)
        scroll_pos = 0
        status_msg = "✓ Loaded"
        fs.save("/last_page.txt", url)
    else
        table.insert(page_content, {type = "text", text = "Error loading page"})
        if res and res.code then
            table.insert(page_content, {type = "text", text = "HTTP Code: " .. res.code})
            if res.err then
                table.insert(page_content, {type = "text", text = "Error: " .. res.err})
            end
        end
        status_msg = "✗ Load failed"
    end
    
    loading = false
end

-- Отображение контента
function display_content()
    if #page_content == 0 then
        ui.text(50, 150, "Enter URL and press GO", 2, 0xFFFF)
        return
    end
    
    local content_start_y = 110
    local content_width = 380
    local line_height = math.floor(20 * zoom)
    local char_width = math.floor(8 * zoom)
    local current_y = content_start_y - scroll_pos
    
    -- Рассчитываем общую высоту контента
    local total_height = 0
    local element_positions = {}
    
    for i, element in ipairs(page_content) do
        element_positions[i] = {start_y = total_height}
        
        if element.type == "title" then
            total_height = total_height + 30
        elseif element.type == "heading" then
            total_height = total_height + 25
        elseif element.type == "text" then
            local lines = math.ceil(#element.text / (content_width / char_width))
            total_height = total_height + lines * line_height
        elseif element.type == "link" then
            local lines = math.ceil(#element.text / (content_width / char_width))
            total_height = total_height + lines * line_height
        elseif element.type == "image" then
            total_height = total_height + 50
        elseif element.type == "newline" then
            total_height = total_height + line_height
        end
        
        element_positions[i].end_y = total_height
    end
    
    max_scroll = math.max(0, total_height - 350)
    
    -- Проверяем касание
    local touch = ui.getTouch()
    hover_link = nil
    
    if touch.touching and touch.y > 70 and touch.y < SH - 60 then
        local relative_y = touch.y - content_start_y + scroll_pos
        
        -- Ищем элемент под курсором
        for i, element in ipairs(page_content) do
            local pos = element_positions[i]
            if relative_y >= pos.start_y and relative_y <= pos.end_y then
                if element.type == "link" then
                    hover_link = element.url
                    
                    if touch.pressed then
                        active_link = element.url
                        load_page(element.url)
                        return
                    end
                end
                break
            end
        end
    end
    
    -- Отображаем видимые элементы
    for i, element in ipairs(page_content) do
        local pos = element_positions[i]
        local element_y = content_start_y + pos.start_y - scroll_pos
        
        if element_y + (pos.end_y - pos.start_y) > 70 and element_y < SH - 60 then
            if element.type == "title" then
                ui.text(10, element_y, element.text, 2, 0x07E0)
                
            elseif element.type == "heading" then
                ui.text(10, element_y, element.text, 1, 0xF800)
                
            elseif element.type == "text" then
                -- Обрезаем текст по ширине
                local max_chars = math.floor(content_width / char_width)
                local display_text = element.text
                if #display_text > max_chars then
                    display_text = display_text:sub(1, max_chars)
                end
                ui.text(10, element_y, display_text, 1, 0xFFFF)
                
            elseif element.type == "link" then
                local max_chars = math.floor(content_width / char_width)
                local display_text = element.text
                if #display_text > max_chars then
                    display_text = display_text:sub(1, max_chars) .. "..."
                end
                
                -- Проверяем наведение
                local is_hovered = (hover_link == element.url)
                local color = is_hovered and 0xFFFF or 0x07FF
                
                ui.text(10, element_y, display_text, 1, color)
                
                if is_hovered then
                    -- Подчеркивание для ссылки
                    ui.rect(10, element_y + 15, #display_text * char_width, 1, color)
                end
                
            elseif element.type == "image" then
                ui.rect(10, element_y, 100, 40, 0x2104)
                ui.text(15, element_y + 10, element.placeholder, 1, 0xFFFF)
                
                if ui.button(120, element_y, 100, 30, "Load", 0x6318) then
                    status_msg = "Loading image..."
                end
            end
        end
    end
    
    -- Индикатор прокрутки
    if max_scroll > 0 then
        local visible_height = 350
        local scrollbar_height = visible_height * visible_height / (total_height + 50)
        local scrollbar_pos = visible_height * scroll_pos / (total_height + 50)
        
        ui.rect(390, content_start_y, 5, visible_height, 0x2104)
        ui.rect(390, content_start_y + scrollbar_pos, 5, scrollbar_height, 0x6318)
    end
end

-- Показ закладок
function show_bookmarks()
    ui.text(20, 100, "★ Bookmarks", 2, 0xFFE0)
    
    local y = 130
    for i, bm in ipairs(bookmarks) do
        if y < 400 then
            if ui.button(20, y, 360, 35, bm.title:sub(1, 40), 0x2104) then
                url_input = bm.url
                load_page(bm.url)
                mode = "browse"
                return
            end
            ui.text(25, y + 25, bm.url:sub(1, 45), 1, 0x8C71)
            y = y + 60
        end
    end
    
    if #bookmarks == 0 then
        ui.text(20, 180, "No bookmarks yet", 1, 0xFFFF)
        ui.text(20, 200, "Press ★ to add current page", 1, 0x8C71)
    end
end

-- Главное меню с быстрыми ссылками
function show_main_menu()
    ui.text(20, 100, "🌐 Quick Links", 3, 0x07E0)
    
    local quick_links = {
        {"Google", "https://www.google.com"},
        {"DuckDuckGo", "https://duckduckgo.com"},
        {"Wikipedia", "https://wikipedia.org"},
        {"e621", "https://e621.net"},
        {"GitHub", "https://github.com"},
        {"Hacker News", "https://news.ycombinator.com"},
        {"BBC News", "https://www.bbc.com/news"},
        {"Reddit", "https://www.reddit.com/.compact"},
    }
    
    local y = 140
    for i, link in ipairs(quick_links) do
        if y < 380 then
            if ui.button(20, y, 360, 35, link[1], 0x2104) then
                url_input = link[2]
                load_page(link[2])
                mode = "browse"
                return
            end
            y = y + 45
        end
    end
    
    ui.text(20, 430, "Enter custom URL above", 1, 0x8C71)
end

-- Инициализация
function setup()
    load_bookmarks()
    
    if fs.exists("/last_page.txt") then
        local last_url = fs.load("/last_page.txt")
        if last_url then
            url_input = last_url
        end
    end
end

-- Основная функция отрисовки
function draw()
    -- Фон
    ui.rect(0, 0, SW, SH, 0x0000)
    
    -- Панель инструментов
    ui.rect(0, 0, SW, 70, 0x2104)
    
    -- Кнопки навигации
    for _, btn in ipairs(buttons) do
        if ui.button(btn.x, btn.y, btn.w, btn.h, btn.name, btn.col) then
            if btn.name == "←" and #history > 1 then
                table.remove(history)
                local prev_url = history[#history]
                if prev_url then
                    url_input = prev_url
                    load_page(prev_url)
                end
            elseif btn.name == "→" then
                status_msg = "Forward: Not available"
            elseif btn.name == "↻" and url_input ~= "" then
                load_page(url_input)
            elseif btn.name == "🏠" then
                url_input = "https://www.google.com"
                load_page(url_input)
            elseif btn.name == "+" then
                zoom = math.min(zoom + 0.1, 2.0)
                scroll_pos = 0
                status_msg = "Zoom: " .. math.floor(zoom * 100) .. "%"
            elseif btn.name == "-" then
                zoom = math.max(zoom - 0.1, 0.5)
                scroll_pos = 0
                status_msg = "Zoom: " .. math.floor(zoom * 100) .. "%"
            end
        end
    end
    
    -- Поле ввода URL
    ui.rect(10, 65, 320, 35, 0x0000)
    local display_url = url_input
    if #display_url > 35 then
        display_url = "..." .. display_url:sub(-32)
    end
    ui.text(15, 72, display_url, 1, 0xFFFF)
    
    -- Кнопка GO
    if ui.button(335, 65, 60, 35, "GO", 0x07E0) then
        if url_input ~= "" then
            load_page(url_input)
            mode = "browse"
        end
    end
    
    -- Отображение в зависимости от режима
    if mode == "menu" then
        show_main_menu()
    elseif mode == "bookmarks" then
        show_bookmarks()
    else
        display_content()
    end
    
    -- Статус бар
    ui.rect(0, SH - 50, SW, 50, 0x1082)
    
    -- Кнопки нижней панели
    if mode == "browse" then
        -- Кнопка закладки
        if ui.button(20, SH - 45, 50, 35, "★", 0xFFE0) then
            add_bookmark()
        end
        
        -- Кнопка просмотра закладок
        if ui.button(75, SH - 45, 50, 35, "📖", 0x6318) then
            mode = "bookmarks"
        end
        
        -- Кнопка сохранения
        if ui.button(130, SH - 45, 50, 35, "💾", 0x07E0) then
            save_page()
        end
        
        -- Кнопка меню
        if ui.button(185, SH - 45, 50, 35, "🏠", 0x001F) then
            mode = "menu"
        end
        
        -- Кнопка выхода
        if ui.button(240, SH - 45, 140, 35, "Exit Browser", 0xF800) then
            -- Возвращаемся в главное меню
            local f = load(fs.load("/main.lua"))
            if f then f() end
        end
    else
        -- Кнопка возврата в режиме не-browse
        if ui.button(20, SH - 45, 360, 35, "← Back to Browser", 0x2104) then
            mode = "browse"
        end
    end
    
    -- Статус сообщение
    ui.text(20, SH - 15, status_msg, 1, 
           loading and 0xF800 or (status_msg:sub(1,1) == "✓" and 0x07E0 or 0xFFFF))
    
    -- Показываем ссылку при наведении
    if hover_link and mode == "browse" then
        local display_link = hover_link
        if #display_link > 50 then
            display_link = display_link:sub(1, 47) .. "..."
        end
        ui.text(20, SH - 80, display_link, 1, 0x07FF)
    end
    
    -- Индикатор загрузки
    if loading then
        local pulse = math.floor((hw.millis() % 1000) / 500)
        ui.rect(SW - 40, SH - 40, 20, 20, pulse == 0 and 0xF800 or 0x0000)
    end
end

-- Сохранение страницы
function save_page()
    if current_title and #page_content > 0 then
        local filename = "/pages/" .. current_title:gsub("[^%w]", "_") .. ".txt"
        fs.mkdir("/pages")
        
        local content = ""
        for _, element in ipairs(page_content) do
            if element.type == "text" or element.type == "title" or element.type == "heading" then
                content = content .. element.text .. "\n"
            elseif element.type == "link" then
                content = content .. "[LINK] " .. element.text .. " -> " .. element.url .. "\n"
            elseif element.type == "image" then
                content = content .. "[IMG] " .. element.alt .. " -> " .. element.url .. "\n"
            elseif element.type == "newline" then
                content = content .. "\n"
            end
        end
        
        fs.save(filename, content)
        status_msg = "✓ Page saved as text"
    end
end

-- Обработка прокрутки
local last_touch_y = 0
local is_scrolling = false

function loop()
    local touch = ui.getTouch()
    
    -- Прокрутка контента
    if touch.touching and touch.y > 70 and touch.y < SH - 60 then
        if not is_scrolling then
            last_touch_y = touch.y
            is_scrolling = true
        else
            local delta = last_touch_y - touch.y
            scroll_pos = scroll_pos + delta * 2
            if scroll_pos < 0 then scroll_pos = 0 end
            if scroll_pos > max_scroll then scroll_pos = max_scroll end
            last_touch_y = touch.y
        end
    else
        is_scrolling = false
    end
    
    -- Автоматическая очистка
    if not loading and #page_content > 100 then
        -- Удаляем старые элементы чтобы сохранить память
        while #page_content > 50 do
            table.remove(page_content, 1)
        end
    end
end

-- Инициализация
if not _G._BROWSER_INIT then
    _G._BROWSER_INIT = true
    mode = "menu"
    setup()
end
