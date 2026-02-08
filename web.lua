-- Enhanced Web Browser for LuaWatch
local SW, SH = 410, 502

-- Состояние браузера
local url_input = "http://google.com"
local page_content = {}
local history = {}
local scroll_pos = 0
local max_scroll = 0
local loading = false
local status_msg = "Ready"
local bookmarks = {}
local zoom = 1.0
local mode = "menu" -- Инициализируем сразу

-- Стили для отрисовки
local STYLES = {
    h1 = {size = 3, col = 0xF800},
    h2 = {size = 2, col = 0xFDA0},
    h3 = {size = 2, col = 0xFFE0},
    text = {size = 1, col = 0xFFFF},
    link = {size = 1, col = 0x07FF}
}

-- Элементы управления
local buttons = {
    {name = "<-", x = 10, y = 10, w = 45, h = 35, col = 0x2104},
    {name = "H", x = 60, y = 10, w = 45, h = 35, col = 0x6318},
    {name = "R", x = 110, y = 10, w = 45, h = 35, col = 0x07E0},
    {name = "+", x = 310, y = 10, w = 40, h = 35, col = 0x2104},
    {name = "-", x = 355, y = 10, w = 40, h = 35, col = 0x2104},
}

-- Функция отрисовки «Загрузки» (вызывать перед net.get)
function show_loading_frame(url)
    ui.rect(0, 0, SW, SH, 0x0000)
    ui.text(SW/2 - 60, SH/2 - 20, "LOADING...", 2, 0xFFFF)
    ui.text(20, SH/2 + 20, url:sub(1, 45), 1, 0x7BEF)
    ui.flush() -- Важно! Выталкиваем буфер на экран до блокировки
end

-- Новый надежный парсер
function parse_html(html)
    page_content = {}
    if not html then return end
    
    -- Очистка от мусора (скрипты, стили)
    html = html:gsub("<script.-</script>", ""):gsub("<style.-</style>", ""):gsub("<!%-%-.-%-%->", "")
    
    local pos = 1
    while pos <= #html do
        local start_tag, end_tag = html:find("<[^>]+>", pos)
        
        -- Текст до тега
        local text_before = html:sub(pos, (start_tag or 0) - 1):gsub("%s+", " ")
        if #text_before > 1 and text_before ~= " " then
            table.insert(page_content, {type = "text", text = text_before})
        end

        if not start_tag then break end

        local tag_content = html:sub(start_tag + 1, end_tag - 1)
        local tag_name = tag_content:match("^(%/?%w+)")
        if tag_name then
            tag_name = tag_name:lower()
            
            -- Обработка заголовков
            if tag_name:match("h[1-3]") then
                local h_end = html:find("</" .. tag_name .. ">", end_tag)
                if h_end then
                    table.insert(page_content, {type = tag_name, text = html:sub(end_tag + 1, h_end - 1)})
                    end_tag = h_end + #tag_name + 3
                end
            -- Обработка ссылок
            elseif tag_name == "a" then
                local href = tag_content:match('href=["\']([^"\']+)["\']')
                local a_end = html:find("</a>", end_tag)
                if a_end and href then
                    table.insert(page_content, {type = "link", text = html:sub(end_tag + 1, a_end - 1), url = href})
                    end_tag = a_end + 4
                end
            -- Новая строка
            elseif tag_name == "p" or tag_name == "br" then
                table.insert(page_content, {type = "newline"})
            end
        end
        pos = end_tag + 1
    end
end

function load_page(url)
    if not url:match("^https?://") then url = "http://" .. url end
    
    show_loading_frame(url)
    loading = true
    
    -- Очистка памяти перед тяжелой операцией
    collectgarbage("collect")
    
    local res = net.get(url)
    if res and res.ok then
        url_input = url
        parse_html(res.body)
        scroll_pos = 0
        status_msg = "Loaded: " .. #res.body .. " bytes"
    else
        status_msg = "Error: " .. (res and res.code or "Timeout")
        page_content = {{type="h1", text="Failed to load"}}
    end
    loading = false
end

function display_content()
    local y = 110 - scroll_pos
    local line_h = 25 * zoom
    
    for _, el in ipairs(page_content) do
        -- Не рисуем то, что за экраном сверху
        if y > -50 and y < SH - 60 then
            if el.type == "text" then
                ui.text(10, y, el.text:sub(1, 50), 1, STYLES.text.col)
                y = y + line_h
            elseif STYLES[el.type] then
                local s = STYLES[el.type]
                ui.text(10, y, el.text:sub(1, 40), s.size, s.col)
                y = y + (line_h * s.size * 0.8)
            elseif el.type == "link" then
                if ui.button(10, y, 380, 30, "> " .. el.text:sub(1, 35), 0x001F) then
                    table.insert(history, url_input)
                    load_page(el.url)
                    return
                end
                y = y + 35
            elseif el.type == "newline" then
                y = y + line_h
            end
        else
            -- Даже если не рисуем, считаем высоту для корректного скролла
            y = y + line_h
        end
    end
    max_scroll = math.max(0, (y + scroll_pos) - 300)
end

function draw()
    ui.rect(0, 0, SW, SH, 0x0000)
    
    -- Инструменты
    ui.rect(0, 0, SW, 100, 0x2104)
    for _, btn in ipairs(buttons) do
        if ui.button(btn.x, btn.y, btn.w, btn.h, btn.name, btn.col) then
            if btn.name == "<-" and #history > 0 then load_page(table.remove(history))
            elseif btn.name == "H" then mode = "menu"
            elseif btn.name == "R" then load_page(url_input)
            elseif btn.name == "+" then zoom = zoom + 0.1
            elseif btn.name == "-" then zoom = math.max(0.5, zoom - 0.1) end
        end
    end

    -- URL Bar
    ui.rect(10, 55, 300, 35, 0x0000)
    ui.text(15, 62, url_input:sub(-30), 1, 0xFFFF)
    if ui.button(315, 55, 85, 35, "GO", 0x07E0) then
        mode = "browse"
        load_page(url_input)
    end

    -- Content
    if mode == "menu" then
        ui.text(50, 150, "WELCOME", 3, 0x07E0)
        if ui.button(50, 200, 300, 50, "Open Google", 0x2104) then 
            url_input = "http://google.com"
            load_page(url_input)
            mode = "browse"
        end
    else
        display_content()
    end

    -- Status Bar
    ui.rect(0, SH - 40, SW, 40, 0x1082)
    ui.text(10, SH - 30, status_msg, 1, 0xFFFF)
end

-- Обработка скролла через Touch
local last_ty = 0
function loop()
    local t = ui.getTouch()
    if t.touching and t.y > 100 then
        if last_ty > 0 then
            local diff = last_ty - t.y
            scroll_pos = math.max(0, math.min(max_scroll, scroll_pos + diff))
        end
        last_ty = t.y
    else
        last_ty = 0
    end
end

-- Запуск
while true do
    draw()
    loop()
    ui.flush()
end
