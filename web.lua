-- Простой веб-браузер для LuaWatch
-- Автор: ChatGPT

-- Константы экрана
local SCR_W, SCR_H = 410, 502

-- Состояние браузера
local history = {}        -- История посещений (URLs)
local history_index = 0   -- Текущая позиция в истории
local current_url = ""    -- Текущий URL
local page_content = ""   -- Загруженный контент страницы
local page_title = "Browser"
local scroll_pos = 0      -- Позиция скролла
local max_scroll = 0
local loading = false     -- Идет загрузка
local error_msg = ""      -- Сообщение об ошибке

-- Настройки
local settings = {
    font_size = 2,
    line_height = 20,
    margin = 10,
    max_lines = 1000      -- Максимальное количество строк для парсинга
}

-- Начальная страница
local homepage = "https://furtails.pw"

-- Цвета
local colors = {
    bg = 0x0000,          -- Черный фон
    text = 0xFFFF,        -- Белый текст
    link = 0x07FF,        -- Голубые ссылки
    title = 0xF800,       -- Красный заголовок
    url_bar = 0x3186,     -- Темно-синий бар
    button = 0x8410,      -- Серые кнопки
    button_active = 0xEF5D, -- Оранжевые активные кнопки
    loading = 0xFFE0,     -- Желтый индикатор загрузки
    error = 0xF800        -- Красный для ошибок
}

-- Упрощенный HTML парсер (только текст и ссылки)
function parse_html(content)
    local lines = {}
    local links = {}
    local in_tag = false
    local in_script = false
    local in_style = false
    local current_line = ""
    local link_text = ""
    local link_url = ""
    local in_link = false
    local in_title = false
    
    -- Простейший парсинг HTML
    for i = 1, #content do
        local char = content:sub(i, i)
        
        if char == "<" then
            in_tag = true
            local tag_end = content:find(">", i)
            if tag_end then
                local tag = content:sub(i, tag_end):lower()
                
                -- Закрывающие теги
                if tag:find("</script") then in_script = false
                elseif tag:find("</style") then in_style = false
                elseif tag:find("</a") then
                    if in_link and link_text ~= "" and link_url ~= "" then
                        table.insert(links, {
                            text = link_text,
                            url = link_url,
                            line = #lines + 1,
                            pos = #current_line
                        })
                    end
                    in_link = false
                    link_text = ""
                    link_url = ""
                elseif tag:find("</title") then in_title = false
                
                -- Открывающие теги
                elseif tag:find("<script") then in_script = true
                elseif tag:find("<style") then in_style = true
                elseif tag:find("<a ") then
                    in_link = true
                    -- Извлекаем href
                    local href_start = tag:find("href=")
                    if href_start then
                        local quote = tag:sub(href_start + 5, href_start + 5)
                        if quote == '"' or quote == "'" then
                            local href_end = tag:find(quote, href_start + 6)
                            if href_end then
                                link_url = tag:sub(href_start + 6, href_end - 1)
                                -- Преобразуем относительные ссылки
                                if link_url:sub(1, 1) == "/" and current_url ~= "" then
                                    local base = current_url:match("^(https?://[^/]+)")
                                    if base then
                                        link_url = base .. link_url
                                    end
                                elseif link_url:sub(1, 4) ~= "http" and current_url ~= "" then
                                    local base = current_url:match("^(.*)/[^/]*$") or current_url
                                    if base then
                                        link_url = base .. "/" .. link_url
                                    end
                                end
                            end
                        end
                    end
                elseif tag:find("<title") then in_title = true
                elseif tag:find("<br") or tag:find("<p") or tag:find("<div") then
                    -- Новые строки
                    if #current_line > 0 then
                        table.insert(lines, current_line)
                        current_line = ""
                    end
                elseif tag:find("</p") or tag:find("</div") then
                    if #current_line > 0 then
                        table.insert(lines, current_line)
                        current_line = ""
                    end
                end
                
                i = tag_end
                in_tag = false
            end
        elseif not in_tag and not in_script and not in_style then
            if char == "&" then
                -- Простые HTML entity
                local entity_end = content:find(";", i)
                if entity_end then
                    local entity = content:sub(i, entity_end)
                    if entity == "&lt;" then char = "<"
                    elseif entity == "&gt;" then char = ">"
                    elseif entity == "&amp;" then char = "&"
                    elseif entity == "&quot;" then char = '"'
                    elseif entity == "&apos;" then char = "'"
                    elseif entity == "&nbsp;" then char = " "
                    else char = " " -- Неизвестная entity
                    end
                    i = entity_end
                end
            end
            
            if char == "\n" or char == "\r" then
                -- Игнорируем переводы строк в HTML
            else
                if in_link then
                    link_text = link_text .. char
                end
                
                if in_title then
                    page_title = page_title .. char
                end
                
                -- Добавляем символ в текущую строку
                current_line = current_line .. char
                
                -- Ограничиваем длину строки
                if #current_line > 60 then
                    table.insert(lines, current_line)
                    current_line = ""
                end
            end
        end
    end
    
    -- Добавляем последнюю строку
    if #current_line > 0 then
        table.insert(lines, current_line)
    end
    
    -- Обрезаем количество строк
    if #lines > settings.max_lines then
        lines = {table.unpack(lines, 1, settings.max_lines)}
        table.insert(lines, "[... content truncated ...]")
    end
    
    return lines, links
end

-- Парсинг простого текста (для Markdown и plain text)
function parse_text(content)
    local lines = {}
    
    for line in content:gmatch("[^\r\n]+") do
        -- Убираем лишние пробелы
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        
        if #line > 0 then
            -- Разбиваем длинные строки
            while #line > 60 do
                table.insert(lines, line:sub(1, 60))
                line = line:sub(61)
            end
            if #line > 0 then
                table.insert(lines, line)
            end
        else
            table.insert(lines, "") -- Пустая строка
        end
    end
    
    -- Обрезаем количество строк
    if #lines > settings.max_lines then
        lines = {table.unpack(lines, 1, settings.max_lines)}
        table.insert(lines, "[... content truncated ...]")
    end
    
    return lines, {}
end

-- Загрузка страницы
function load_url(url)
    if url == "" then return end
    
    -- Добавляем протокол если нет
    if not url:find("^https?://") then
        url = "http://" .. url
    end
    
    current_url = url
    loading = true
    error_msg = ""
    scroll_pos = 0
    
    -- Добавляем в историю
    table.insert(history, url)
    history_index = #history
    
    -- Показываем сообщение о загрузке
    page_content = "Loading..."
    
    -- Загружаем страницу
    local res = net.get(url)
    
    if res and res.ok and res.body then
        if #res.body < 10000 then -- Проверяем размер
            -- Определяем тип контента
            if res.body:find("<!DOCTYPE") or res.body:find("<html") then
                -- HTML страница
                page_title = "Web Page"
                local lines, links = parse_html(res.body)
                page_content = lines
                page_links = links
            else
                -- Текстовый контент
                page_title = "Text Document"
                local lines, links = parse_text(res.body)
                page_content = lines
                page_links = links
            end
        else
            error_msg = "Page too large (" .. #res.body .. " bytes)"
            page_content = {"[Page too large to display]"}
        end
    else
        error_msg = res and res.err or "Unknown error"
        page_content = {"[Failed to load page]"}
    end
    
    loading = false
    
    -- Рассчитываем максимальный скролл
    if type(page_content) == "table" then
        max_scroll = math.max(0, #page_content * settings.line_height - (SCR_H - 80))
    else
        max_scroll = 0
    end
end

-- Отображение страницы
function draw_page()
    local start_y = 80 - scroll_pos
    local content_height = SCR_H - 80
    
    -- Фон
    ui.rect(0, 0, SCR_W, SCR_H, colors.bg)
    
    -- Заголовок
    ui.text(10, 10, page_title, settings.font_size, colors.title)
    
    -- URL бар
    ui.rect(0, 40, SCR_W, 30, colors.url_bar)
    ui.text(10, 45, current_url:sub(1, 50), 1, colors.text)
    
    -- Индикатор загрузки/ошибки
    if loading then
        ui.text(SCR_W - 100, 45, "Loading...", 1, colors.loading)
    elseif error_msg ~= "" then
        ui.text(SCR_W - 100, 45, "Error", 1, colors.error)
    end
    
    -- Контент
    if type(page_content) == "table" then
        for i, line in ipairs(page_content) do
            local y = start_y + (i-1) * settings.line_height
            
            -- Проверяем видимость строки
            if y >= 80 and y < SCR_H - 10 then
                -- Проверяем, есть ли ссылка на этой строке
                local link_color = colors.text
                for _, link in ipairs(page_links or {}) do
                    if link.line == i then
                        link_color = colors.link
                        break
                    end
                end
                
                ui.text(settings.margin, y, line, 1, link_color)
            elseif y > SCR_H then
                break -- Выходим если ниже экрана
            end
        end
    else
        ui.text(settings.margin, start_y, page_content, 2, colors.text)
    end
    
    -- Скроллбар
    if max_scroll > 0 then
        local scroll_height = math.max(20, content_height * content_height / (#page_content * settings.line_height))
        local scroll_y = 80 + (scroll_pos / max_scroll) * (content_height - scroll_height)
        ui.rect(SCR_W - 10, scroll_y, 8, scroll_height, colors.button)
    end
end

-- Обработка кликов по ссылкам
function handle_click(x, y)
    if type(page_content) ~= "table" then return end
    
    local content_y = y - 80 + scroll_pos
    local line_index = math.floor(content_y / settings.line_height) + 1
    
    if line_index >= 1 and line_index <= #page_content then
        -- Проверяем клик по ссылке
        for _, link in ipairs(page_links or {}) do
            if link.line == line_index then
                -- Загружаем ссылку
                load_url(link.url)
                return true
            end
        end
    end
    
    return false
end

-- Отрисовка UI
function draw()
    -- Область контента для скролла
    local scroll_area = ui.beginList(0, 80, SCR_W, SCR_H - 80, scroll_pos, 
                                     type(page_content) == "table" and #page_content * settings.line_height or 100)
    scroll_pos = scroll_area
    
    -- Рисуем страницу
    draw_page()
    
    ui.endList()
    
    -- Нижняя панель навигации
    ui.rect(0, SCR_H - 40, SCR_W, 40, colors.url_bar)
    
    -- Кнопка Назад
    if ui.button(10, SCR_H - 35, 60, 30, "Back", colors.button) then
        if history_index > 1 then
            history_index = history_index - 1
            load_url(history[history_index])
        end
    end
    
    -- Кнопка Вперед
    if ui.button(80, SCR_H - 35, 60, 30, "Next", colors.button) then
        if history_index < #history then
            history_index = history_index + 1
            load_url(history[history_index])
        end
    end
    
    -- Кнопка Обновить
    if ui.button(150, SCR_H - 35, 60, 30, "Reload", colors.button) then
        if current_url ~= "" then
            load_url(current_url)
        end
    end
    
    -- Кнопка Домой
    if ui.button(220, SCR_H - 35, 60, 30, "Home", colors.button) then
        load_url(homepage)
    end
    
    -- Поле ввода URL
    local url_input = ui.input(290, SCR_H - 35, 110, 30, "Go to:", false)
    if url_input then
        -- Открываем клавиатуру для ввода URL
        local new_url = input_dialog("Enter URL:", current_url)
        if new_url and new_url ~= "" then
            load_url(new_url)
        end
    end
end

-- Диалог ввода текста
function input_dialog(title, default)
    local input_text = default or ""
    local result = nil
    local exit_dialog = false
    
    while not exit_dialog do
        ui.rect(0, 0, SCR_W, SCR_H, 0x0000)
        ui.text(SCR_W/2 - 50, 50, title, 2, 0xFFFF)
        
        -- Поле ввода
        ui.rect(50, 100, SCR_W - 100, 40, 0x3186)
        ui.text(60, 110, input_text, 2, 0xFFFF)
        
        -- Простая клавиатура
        local keys = {
            "abcdefghij", "klmnopqrst", "uvwxyz.-:/",
            "0123456789", "DELETE", "CLEAR", "OK"
        }
        
        for i, row in ipairs(keys) do
            local cols = {}
            for c in row:gmatch(".") do
                table.insert(cols, c)
            end
            
            for j, key in ipairs(cols) do
                local x = 20 + (j-1) * 90
                local y = 160 + (i-1) * 45
                
                if ui.button(x, y, 80, 40, key, 0x8410) then
                    if key == "DELETE" then
                        input_text = input_text:sub(1, -2)
                    elseif key == "CLEAR" then
                        input_text = ""
                    elseif key == "OK" then
                        result = input_text
                        exit_dialog = true
                    else
                        input_text = input_text .. key
                    end
                end
            end
        end
        
        ui.flush()
    end
    
    return result
end

-- Обработка касаний для скролла
local last_touch_y = 0
local is_dragging = false
local scroll_velocity = 0

function on_touch(touch)
    if touch.touching then
        if not is_dragging then
            last_touch_y = touch.y
            is_dragging = true
        else
            local delta = last_touch_y - touch.y
            scroll_pos = scroll_pos + delta
            
            -- Ограничиваем скролл
            if scroll_pos < 0 then scroll_pos = 0 end
            if scroll_pos > max_scroll then scroll_pos = max_scroll end
            
            last_touch_y = touch.y
            scroll_velocity = delta
        end
        
        -- Проверяем клик по ссылке (при отпускании)
        if touch.released then
            if scroll_velocity == 0 or math.abs(scroll_velocity) < 5 then
                handle_click(touch.x, touch.y)
            end
        end
    else
        is_dragging = false
        
        -- Инерционный скролл
        if math.abs(scroll_velocity) > 0.5 then
            scroll_pos = scroll_pos + scroll_velocity
            scroll_velocity = scroll_velocity * 0.92
            
            -- Ограничиваем скролл
            if scroll_pos < 0 then 
                scroll_pos = 0
                scroll_velocity = 0
            end
            if scroll_pos > max_scroll then 
                scroll_pos = max_scroll
                scroll_velocity = 0
            end
        end
    end
end

-- Основной цикл
function main()
    -- Загружаем домашнюю страницу
    load_url(homepage)
    
    -- Главный цикл
    while true do
        local touch = ui.getTouch()
        on_touch(touch)
        draw()
        ui.flush()
    end
end

-- Запуск браузера
main()
