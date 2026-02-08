-- Simple Web Browser для LuaWatch
-- Автор: ChatGPT
-- Версия: 1.0

-- Константы экрана
local SCR_W, SCR_H = 410, 502
local HEADER_H = 40
local FOOTER_H = 40
local CONTENT_H = SCR_H - HEADER_H - FOOTER_H

-- Состояние браузера
local state = {
    -- История и навигация
    history = {},
    history_index = 0,
    
    -- Текущая страница
    page = {
        url = "",
        title = "New Tab",
        content = {},
        links = {},
        scroll_y = 0,
        total_height = 0
    },
    
    -- Ввод URL
    input_mode = false,
    url_input = "https://example.com",
    
    -- Статус
    loading = false,
    status = "Ready",
    last_load_time = 0
}

-- Вспомогательные функции
function string.starts(str, start)
    return str:sub(1, #start) == start
end

function string.trim(s)
    return s:match("^%s*(.-)%s*$")
end

function encodeURL(url)
    return url:gsub("[^a-zA-Z0-9%-._~:/?#%[%]@!$&'()*+,;=]", 
        function(c) return string.format("%%%02X", string.byte(c)) end)
end

-- Парсинг HTML (очень упрощенный)
function parseHTML(html)
    local lines = {}
    local links = {}
    local link_index = 1
    local y = 0
    local line_height = 20
    local padding = 5
    
    -- Удаляем теги <script> и <style>
    html = html:gsub("<script[^>]*>.-</script>", "")
    html = html:gsub("<style[^>]*>.-</style>", "")
    
    -- Заменяем <br> на переносы строк
    html = html:gsub("<br%s*/?>", "\n")
    
    -- Обработка ссылок
    html = html:gsub('<a[^>]+href="([^"]+)"[^>]*>(.-)</a>', 
        function(href, text)
            local start = #lines + 1
            local link_id = link_index
            link_index = link_index + 1
            
            -- Обрабатываем текст ссылки
            local clean_text = text:gsub("<[^>]+>", ""):trim()
            if clean_text ~= "" then
                table.insert(lines, {text = clean_text, type = "link", link_id = link_id, y = y})
                y = y + line_height
            end
            
            -- Сохраняем ссылку
            links[link_id] = {
                href = href,
                text = clean_text,
                start_line = start
            }
            
            return clean_text
        end)
    
    -- Удаляем все остальные теги
    html = html:gsub("<[^>]+>", "")
    
    -- Разбиваем на строки
    for line in html:gmatch("[^\r\n]+") do
        line = line:trim()
        if line ~= "" then
            -- Разбиваем длинные строки
            local max_len = 45  -- Примерно 45 символов на строку
            while #line > max_len do
                local space_pos = line:sub(1, max_len):find("%s[^%s]*$")
                if space_pos then
                    local part = line:sub(1, space_pos):trim()
                    table.insert(lines, {text = part, type = "text", y = y})
                    y = y + line_height
                    line = line:sub(space_pos + 1):trim()
                else
                    break
                end
            end
            
            if line ~= "" and #line > 0 then
                table.insert(lines, {text = line, type = "text", y = y})
                y = y + line_height
            end
        end
    end
    
    return {
        lines = lines,
        links = links,
        total_height = y + padding
    }
end

-- Загрузка страницы
function loadPage(url)
    if not url or url == "" then
        state.status = "Empty URL"
        return false
    end
    
    -- Добавляем протокол если нужно
    if not string.starts(url, "http://") and not string.starts(url, "https://") then
        url = "https://" .. url
    end
    
    state.loading = true
    state.status = "Loading..."
    state.page.url = url
    state.page.title = "Loading..."
    state.page.scroll_y = 0
    
    -- Показываем обновление UI
    draw()
    ui.flush()
    
    -- Загружаем страницу
    local encoded_url = encodeURL(url)
    local result = net.get(encoded_url)
    
    if result and result.ok and result.body then
        -- Парсим HTML
        local parsed = parseHTML(result.body)
        
        -- Обновляем состояние
        state.page.content = parsed.lines
        state.page.links = parsed.links
        state.page.total_height = parsed.total_height
        state.page.title = url
        
        -- Извлекаем заголовок если есть
        local title = result.body:match("<title>(.-)</title>")
        if title and title:trim() ~= "" then
            state.page.title = title:trim():gsub("<[^>]+>", "")
            if #state.page.title > 30 then
                state.page.title = state.page.title:sub(1, 27) .. "..."
            end
        end
        
        -- Сохраняем в историю
        table.insert(state.history, {
            url = url,
            title = state.page.title,
            time = hw.getTime()
        })
        state.history_index = #state.history
        
        state.status = "Loaded"
        state.last_load_time = hw.millis()
        state.loading = false
        return true
    else
        state.status = "Failed to load"
        if result and result.err then
            state.status = state.status .. ": " .. result.err
        end
        state.loading = false
        return false
    end
end

-- Навигация назад/вперед
function goBack()
    if state.history_index > 1 then
        state.history_index = state.history_index - 1
        local hist = state.history[state.history_index]
        loadPage(hist.url)
    end
end

function goForward()
    if state.history_index < #state.history then
        state.history_index = state.history_index + 1
        local hist = state.history[state.history_index]
        loadPage(hist.url)
    end
end

-- Обработка клика по ссылке
function handleLinkClick(x, y)
    local screen_y = y - HEADER_H + state.page.scroll_y
    
    for _, line in ipairs(state.page.content) do
        if line.type == "link" and screen_y >= line.y and screen_y <= line.y + 20 then
            local link = state.page.links[line.link_id]
            if link then
                local href = link.href
                
                -- Обработка относительных URL
                if not string.starts(href, "http://") and not string.starts(href, "https://") then
                    if string.starts(href, "/") then
                        -- Абсолютный путь относительно домена
                        local domain = state.page.url:match("https?://[^/]+")
                        if domain then
                            href = domain .. href
                        end
                    else
                        -- Относительный путь
                        local base = state.page.url:match("(.+)/[^/]*$")
                        if base then
                            href = base .. "/" .. href
                        end
                    end
                end
                
                loadPage(href)
                return true
            end
        end
    end
    
    return false
end

-- Отрисовка интерфейса
function draw()
    -- Фон
    ui.rect(0, 0, SCR_W, SCR_H, 0)
    
    -- Заголовок
    ui.rect(0, 0, SCR_W, HEADER_H, 1024)
    ui.text(10, 10, "LuaBrowser", 2, 65535)
    
    -- Статус загрузки
    if state.loading then
        ui.text(SCR_W - 100, 10, state.status, 1, 65535)
    else
        local time_str = ""
        if state.last_load_time > 0 then
            local sec = math.floor((hw.millis() - state.last_load_time) / 1000)
            if sec < 60 then
                time_str = sec .. "s ago"
            else
                time_str = math.floor(sec/60) .. "m ago"
            end
        end
        ui.text(SCR_W - 80, 10, time_str, 1, 2016)
    end
    
    -- Кнопки навигации
    if ui.button(SCR_W - 90, HEADER_H + 5, 40, 30, "<", 8452) then
        goBack()
    end
    
    if ui.button(SCR_W - 45, HEADER_H + 5, 40, 30, ">", 8452) then
        goForward()
    end
    
    -- Поле ввода/отображения URL
    if state.input_mode then
        -- Режим редактирования URL
        ui.rect(5, HEADER_H + 5, SCR_W - 100, 30, 65535)
        ui.text(10, HEADER_H + 10, state.url_input, 2, 0)
        
        -- Кнопка GO
        if ui.button(SCR_W - 95, HEADER_H + 5, 90, 30, "GO", 2048) then
            loadPage(state.url_input)
            state.input_mode = false
        end
    else
        -- Отображение текущего URL
        local display_url = state.page.url
        if #display_url > 40 then
            display_url = display_url:sub(1, 17) .. "..." .. display_url:sub(-20)
        end
        
        if ui.button(5, HEADER_H + 5, SCR_W - 100, 30, display_url, 8452) then
            state.input_mode = true
            state.url_input = state.page.url
        end
    end
    
    -- Область контента
    ui.pushClip(0, HEADER_H + 40, SCR_W, CONTENT_H)
    
    -- Заголовок страницы
    ui.text(10, HEADER_H + 40 - state.page.scroll_y, state.page.title, 2, 2016)
    
    -- Контент страницы
    local content_start_y = HEADER_H + 70
    for _, line in ipairs(state.page.content) do
        local line_y = content_start_y + line.y - state.page.scroll_y
        
        -- Проверяем, видима ли строка
        if line_y >= HEADER_H + 40 and line_y <= SCR_H - FOOTER_H then
            if line.type == "link" then
                -- Ссылка (синий подчеркнутый текст)
                ui.text(10, line_y, line.text, 2, 31)  -- Синий цвет
                -- Подчеркивание
                ui.rect(10, line_y + 16, #line.text * 12, 1, 31)
            else
                -- Обычный текст
                ui.text(10, line_y, line.text, 2, 65535)
            end
        end
    end
    
    -- Индикатор скролла
    if state.page.total_height > CONTENT_H then
        local scroll_height = math.max(20, (CONTENT_H / state.page.total_height) * CONTENT_H)
        local scroll_pos = (state.page.scroll_y / (state.page.total_height - CONTENT_H)) * (CONTENT_H - scroll_height)
        
        ui.rect(SCR_W - 5, HEADER_H + 40 + scroll_pos, 5, scroll_height, 63488)
    end
    
    ui.popClip()
    
    -- Панель внизу (статус)
    ui.rect(0, SCR_H - FOOTER_H, SCR_W, FOOTER_H, 1024)
    
    -- Статус
    ui.text(10, SCR_H - FOOTER_H + 10, state.status, 1, 65535)
    
    -- Информация о странице
    local info = #state.page.content .. " lines"
    if #state.page.content > 0 then
        info = info .. ", " .. #state.page.links .. " links"
    end
    ui.text(SCR_W - 150, SCR_H - FOOTER_H + 10, info, 1, 2016)
    
    -- Кнопки внизу
    if ui.button(SCR_W - 90, SCR_H - 35, 40, 30, "↺", 2048) then
        -- Перезагрузка страницы
        if state.page.url ~= "" then
            loadPage(state.page.url)
        end
    end
    
    if ui.button(SCR_W - 45, SCR_H - 35, 40, 30, "+", 8452) then
        -- Новая вкладка (сброс)
        state.page = {
            url = "",
            title = "New Tab",
            content = {},
            links = {},
            scroll_y = 0,
            total_height = 0
        }
        state.input_mode = true
        state.url_input = "https://example.com"
    end
end

-- Основной цикл приложения
function mainLoop()
    -- Переменные для скроллинга
    local scroll_start_y = 0
    local scroll_start_scroll = 0
    local is_scrolling = false
    
    -- Загружаем стартовую страницу
    loadPage("https://example.com")
    
    while true do
        -- Получаем состояние тача
        local touch = ui.getTouch()
        
        if touch.touching then
            -- Скроллинг контента
            if not state.input_mode and touch.y > HEADER_H + 40 and touch.y < SCR_H - FOOTER_H then
                if not is_scrolling then
                    scroll_start_y = touch.y
                    scroll_start_scroll = state.page.scroll_y
                    is_scrolling = true
                else
                    local delta = scroll_start_y - touch.y
                    local new_scroll = scroll_start_scroll + delta
                    
                    -- Ограничиваем скролл
                    local max_scroll = math.max(0, state.page.total_height - CONTENT_H + 50)
                    if new_scroll < 0 then
                        state.page.scroll_y = 0
                    elseif new_scroll > max_scroll then
                        state.page.scroll_y = max_scroll
                    else
                        state.page.scroll_y = new_scroll
                    end
                end
            end
        else
            -- Обработка клика при отпускании
            if is_scrolling then
                is_scrolling = false
            elseif not state.input_mode and touch.y > HEADER_H + 40 and touch.y < SCR_H - FOOTER_H then
                -- Проверяем клик по ссылке
                handleLinkClick(touch.x, touch.y)
            end
        end
        
        -- Отрисовка
        draw()
        ui.flush()
        
        -- Небольшая задержка для стабильности
        local time = hw.getTime()
        local delay_ms = 33  -- ~30 FPS
        hw.millis()
    end
end

-- Запуск браузера
mainLoop()
