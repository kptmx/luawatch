-- Простой веб-браузер для LuaWatch
-- Сохранить как /main.lua

local SCR_W, SCR_H = 410, 502
local browser = {}

-- Состояние браузера
browser.history = {}
browser.history_index = 0
browser.current_url = "about:blank"
browser.page_content = {}
browser.scroll_y = 0
browser.max_scroll = 0
browser.loading = false
browser.error = nil
browser.images = {}
browser.input_mode = false
browser.url_input = "https://"
browser.link_under_touch = nil
browser.page_title = "Browser"
browser.cache = {} -- Кэш для загруженных страниц

-- Конфигурация
browser.config = {
    user_agent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
    timeout = 10000,
    max_redirects = 5,
    image_cache_size = 5 -- Сколько JPEG изображений хранить в памяти
}

-- Палитра цветов
browser.colors = {
    background = 0x0000,
    text = 0xFFFF,
    link = 0x07FF,
    visited = 0xAAFF,
    title = 0xF800,
    input_bg = 0x2104,
    input_text = 0xFFFF,
    loading = 0xFFE0,
    error = 0xF800,
    scrollbar = 0x528A
}

-- Утилиты для работы с URL
function browser.normalize_url(url, base)
    if url:sub(1, 7) == "http://" or url:sub(1, 8) == "https://" then
        return url
    elseif url:sub(1, 4) == "www." then
        return "http://" .. url
    elseif base then
        if url:sub(1, 1) == "/" then
            local protocol, domain = base:match("^(https?://[^/]+)")
            return protocol .. domain .. url
        else
            local path = base:match("^(.-/[^/]*)$")
            if path then
                return path:gsub("/[^/]*$", "/") .. url
            end
        end
    end
    return "http://" .. url
end

-- Парсинг простого HTML (очень упрощенный)
function browser.parse_html(html, base_url)
    local lines = {}
    local in_pre = false
    local text_buffer = ""
    
    -- Очистка тегов и извлечение текста/ссылок
    local i = 1
    while i <= #html do
        if html:sub(i, i) == "<" then
            -- Найден тег
            local tag_end = html:find(">", i)
            if tag_end then
                local tag = html:sub(i, tag_end):lower()
                
                -- Обработка основных тегов
                if tag:find("<pre") then
                    in_pre = true
                elseif tag == "</pre>" then
                    in_pre = false
                elseif tag:find("<img") then
                    -- Извлечение src у изображений
                    local src = tag:match('src%s*=%s*["\']([^"\']+)["\']')
                    if src then
                        local img_url = browser.normalize_url(src, base_url)
                        table.insert(lines, {type = "image", url = img_url})
                    end
                elseif tag:find("<a%s") then
                    -- Извлечение href у ссылок
                    local href = tag:match('href%s*=%s*["\']([^"\']+)["\']')
                    local link_text = ""
                    if href then
                        local link_url = browser.normalize_url(href, base_url)
                        -- Ищем текст ссылки до закрывающего тега
                        local close_a = html:find("</a>", tag_end)
                        if close_a then
                            link_text = html:sub(tag_end + 1, close_a - 1)
                            link_text = link_text:gsub("<[^>]+>", "")
                        end
                        table.insert(lines, {type = "link", url = link_url, text = link_text})
                        i = close_a or tag_end
                    end
                elseif tag:find("<title>") then
                    -- Извлечение заголовка
                    local title_end = html:find("</title>", tag_end)
                    if title_end then
                        browser.page_title = html:sub(tag_end + 1, title_end - 1)
                        browser.page_title = browser.page_title:gsub("%s+", " ")
                    end
                elseif tag:find("<h1") or tag:find("<h2") or tag:find("<h3") then
                    table.insert(lines, {type = "header", level = tonumber(tag:match("<h(%d)")) or 2})
                elseif tag:find("</h%d") then
                    if text_buffer:len() > 0 then
                        table.insert(lines, {type = "text", content = text_buffer})
                        text_buffer = ""
                    end
                end
                
                i = tag_end + 1
            else
                i = i + 1
            end
        else
            -- Текст
            local char = html:sub(i, i)
            if in_pre or char ~= "\n" then
                text_buffer = text_buffer .. char
            end
            
            -- Разбиваем на строки по длине или символам новой строки
            if char == "\n" or #text_buffer >= 50 then
                if text_buffer:len() > 0 then
                    text_buffer = text_buffer:gsub("^%s+", ""):gsub("%s+$", "")
                    if text_buffer:len() > 0 then
                        table.insert(lines, {type = "text", content = text_buffer})
                    end
                    text_buffer = ""
                end
            end
            i = i + 1
        end
    end
    
    -- Добавляем остаток буфера
    if text_buffer:len() > 0 then
        text_buffer = text_buffer:gsub("^%s+", ""):gsub("%s+$", "")
        if text_buffer:len() > 0 then
            table.insert(lines, {type = "text", content = text_buffer})
        end
    end
    
    return lines
end

-- Загрузка страницы
function browser.load_url(url)
    if not url or url == "" then return end
    
    browser.current_url = url
    browser.loading = true
    browser.error = nil
    browser.scroll_y = 0
    browser.link_under_touch = nil
    browser.images = {}
    
    -- Проверяем кэш
    if browser.cache[url] and os.time() - browser.cache[url].timestamp < 300 then
        browser.page_content = browser.cache[url].content
        browser.page_title = browser.cache[url].title
        browser.loading = false
        browser.calculate_layout()
        return
    end
    
    -- Добавляем в историю
    if #browser.history == 0 or browser.history[#browser.history] ~= url then
        table.insert(browser.history, url)
        browser.history_index = #browser.history
    end
    
    -- Загружаем страницу
    local result = net.get(url)
    
    if result and result.ok and result.code == 200 then
        -- Успешная загрузка
        browser.page_content = browser.parse_html(result.body, url)
        
        -- Сохраняем в кэш
        browser.cache[url] = {
            content = browser.page_content,
            title = browser.page_title,
            timestamp = os.time()
        }
        
        -- Очистка старых записей кэша
        local cache_keys = {}
        for k in pairs(browser.cache) do table.insert(cache_keys, k) end
        table.sort(cache_keys, function(a,b) 
            return browser.cache[a].timestamp < browser.cache[b].timestamp 
        end)
        
        while #cache_keys > 10 do
            browser.cache[cache_keys[1]] = nil
            table.remove(cache_keys, 1)
        end
        
        browser.error = nil
    else
        -- Ошибка загрузки
        browser.error = "Failed to load: " .. (result and tostring(result.code) or "no connection")
        browser.page_content = {{type = "text", content = "Error: " .. browser.error}}
        browser.page_title = "Error"
    end
    
    browser.loading = false
    browser.calculate_layout()
end

-- Расчет макета для скроллинга
function browser.calculate_layout()
    local y = 0
    local line_height = 20
    local margin = 5
    
    for _, element in ipairs(browser.page_content) do
        if element.type == "text" then
            element.y = y
            element.height = line_height
            y = y + line_height + margin
        elseif element.type == "header" then
            element.y = y
            element.height = line_height + 10
            y = y + element.height + margin
        elseif element.type == "link" then
            element.y = y
            element.height = line_height
            y = y + line_height + margin
        elseif element.type == "image" then
            element.y = y
            element.height = 100 -- Предполагаемая высота
            y = y + 100 + margin
            element.loaded = false
        end
    end
    
    browser.max_scroll = math.max(0, y - SCR_H + 100)
end

-- Загрузка изображения
function browser.load_image(element)
    if element.loaded or element.loading then return end
    
    element.loading = true
    
    -- Пробуем загрузить из кэша
    if browser.images[element.url] then
        element.bitmap = browser.images[element.url]
        element.loaded = true
        element.loading = false
        return
    end
    
    -- Определяем, откуда грузить (SD или интернет)
    if element.url:match("^https?://") then
        -- Загружаем из интернета
        local filename = "/cache/" .. element.url:gsub("[^%w]", "_") .. ".jpg"
        
        -- Пробуем скачать
        local success = net.download(element.url, filename, "flash", 
            function(loaded, total)
                -- Коллбэк прогресса (можно добавить индикатор)
            end)
        
        if success then
            if ui.drawJPEG(0, 0, filename) then
                element.loaded = true
                browser.images[element.url] = true
            end
            fs.remove(filename) -- Удаляем временный файл
        end
    else
        -- Локальный файл
        if ui.drawJPEG(0, 0, element.url) then
            element.loaded = true
            browser.images[element.url] = true
        end
    end
    
    element.loading = false
    
    -- Ограничиваем размер кэша изображений
    local image_count = 0
    for _ in pairs(browser.images) do image_count = image_count + 1 end
    
    if image_count > browser.config.image_cache_size then
        -- Удаляем самое старое изображение (здесь просто очищаем)
        browser.images = {}
    end
end

-- Отрисовка браузера
function browser.draw()
    -- Фон
    ui.rect(0, 0, SCR_W, SCR_H, browser.colors.background)
    
    -- Панель навигации
    ui.rect(0, 0, SCR_W, 40, 0x2104)
    
    -- Кнопки навигации
    if ui.button(5, 5, 60, 30, "Back", 0x528A) then
        if browser.history_index > 1 then
            browser.history_index = browser.history_index - 1
            browser.load_url(browser.history[browser.history_index])
        end
    end
    
    if ui.button(70, 5, 60, 30, "Forward", 0x528A) then
        if browser.history_index < #browser.history then
            browser.history_index = browser.history_index + 1
            browser.load_url(browser.history[browser.history_index])
        end
    end
    
    if ui.button(135, 5, 60, 30, "Refresh", 0x528A) then
        browser.load_url(browser.current_url)
    end
    
    -- Поле ввода URL
    if ui.input(200, 5, 150, 30, browser.current_url, false) then
        browser.input_mode = true
        browser.url_input = browser.current_url
    end
    
    if ui.button(355, 5, 50, 30, "Go", 0x07E0) then
        browser.input_mode = true
        browser.url_input = browser.current_url
    end
    
    -- Область контента
    ui.pushClip(0, 40, SCR_W, SCR_H - 40)
    
    local start_y = 40 - browser.scroll_y
    
    -- Отображение контента
    for _, element in ipairs(browser.page_content) do
        local y = start_y + element.y
        
        -- Проверяем видимость элемента
        if y < SCR_H and y + element.height > 40 then
            if element.type == "text" then
                ui.text(10, y, element.content, 2, browser.colors.text)
            elseif element.type == "header" then
                ui.text(10, y, element.content or "", 3, browser.colors.title)
            elseif element.type == "link" then
                local color = browser.colors.link
                if browser.visited_links and browser.visited_links[element.url] then
                    color = browser.colors.visited
                end
                
                ui.text(10, y, element.text or element.url, 2, color)
                
                -- Подчеркивание ссылки
                ui.rect(10, y + 15, #(element.text or element.url) * 12, 1, color)
            elseif element.type == "image" then
                -- Заглушка для изображения
                ui.rect(10, y, SCR_W - 20, 100, 0x2104)
                ui.text(20, y + 40, "[Image: " .. element.url:match("([^/]+)$") or "image" .. "]", 2, 0x7BEF)
                
                -- Пробуем загрузить изображение при необходимости
                if not element.loaded and not element.loading then
                    browser.load_image(element)
                end
            end
        end
    end
    
    -- Индикатор загрузки
    if browser.loading then
        ui.rect(SCR_W/2 - 30, SCR_H/2 - 10, 60, 20, browser.colors.loading)
        ui.text(SCR_W/2 - 25, SCR_H/2 - 5, "Loading...", 2, 0x0000)
    end
    
    -- Сообщение об ошибке
    if browser.error then
        ui.rect(10, 50, SCR_W - 20, 40, browser.colors.error)
        ui.text(15, 60, browser.error, 2, 0xFFFF)
    end
    
    -- Скроллбар
    if browser.max_scroll > 0 then
        local scroll_height = (SCR_H - 40) * (SCR_H - 40) / (browser.max_scroll + SCR_H - 40)
        local scroll_pos = (SCR_H - 40 - scroll_height) * (browser.scroll_y / browser.max_scroll)
        ui.rect(SCR_W - 5, 40 + scroll_pos, 5, scroll_height, browser.colors.scrollbar)
    end
    
    ui.popClip()
    
    -- Обработка скроллинга
    local scroll_area = ui.beginList(0, 40, SCR_W, SCR_H - 40, browser.scroll_y, browser.max_scroll + SCR_H - 40)
    if scroll_area ~= browser.scroll_y then
        browser.scroll_y = scroll_area
    end
    ui.endList()
    
    -- Диалог ввода URL
    if browser.input_mode then
        -- Затемнение фона
        ui.rect(0, 0, SCR_W, SCR_H, 0x0000)
        ui.rect(20, 100, SCR_W - 40, 200, 0x2104)
        ui.text(30, 110, "Enter URL:", 3, 0xFFFF)
        
        -- Поле ввода
        if ui.input(30, 150, SCR_W - 100, 40, browser.url_input, true) then
            -- Редактирование URL
        end
        
        -- Кнопки
        if ui.button(30, 210, 100, 40, "Cancel", 0xF800) then
            browser.input_mode = false
        end
        
        if ui.button(SCR_W - 130, 210, 100, 40, "Go", 0x07E0) then
            browser.load_url(browser.url_input)
            browser.input_mode = false
        end
        
        -- Клавиатура
        local keys = {"q","w","e","r","t","y","u","i","o","p",
                      "a","s","d","f","g","h","j","k","l",
                      "z","x","c","v","b","n","m",".com",
                      "://","/","DEL","SPACE","ENTER"}
        
        local key_x, key_y = 30, 260
        local key_w, key_h = 35, 35
        
        for i, key in ipairs(keys) do
            if key == "ENTER" then
                key_w = 80
            elseif key == "SPACE" then
                key_w = 120
            elseif key == "DEL" then
                key_w = 60
            elseif key == "://" or key == ".com" then
                key_w = 60
            end
            
            if ui.button(key_x, key_y, key_w, key_h, key, 0x528A) then
                if key == "DEL" then
                    browser.url_input = browser.url_input:sub(1, -2)
                elseif key == "SPACE" then
                    browser.url_input = browser.url_input .. " "
                elseif key == "ENTER" then
                    browser.load_url(browser.url_input)
                    browser.input_mode = false
                elseif key == "://" then
                    browser.url_input = browser.url_input .. "://"
                elseif key == ".com" then
                    browser.url_input = browser.url_input .. ".com"
                else
                    browser.url_input = browser.url_input .. key
                end
            end
            
            key_x = key_x + key_w + 5
            if key_x + key_w > SCR_W - 30 then
                key_x = 30
                key_y = key_y + key_h + 5
            end
        end
    end
    
    -- Обработка нажатий на ссылки
    if not browser.input_mode and ui.getTouch().released then
        local touch = ui.getTouch()
        if touch.y > 40 then
            local content_y = touch.y + browser.scroll_y - 40
            
            for _, element in ipairs(browser.page_content) do
                if element.type == "link" then
                    if content_y >= element.y and content_y <= element.y + element.height then
                        browser.load_url(element.url)
                        
                        -- Отмечаем как посещенную
                        if not browser.visited_links then
                            browser.visited_links = {}
                        end
                        browser.visited_links[element.url] = true
                        break
                    end
                elseif element.type == "image" then
                    if content_y >= element.y and content_y <= element.y + element.height then
                        -- Просмотр изображения в полном размере
                        browser.view_image(element.url)
                        break
                    end
                end
            end
        end
    end
end

-- Просмотрщик изображений
function browser.view_image(url)
    local viewing = true
    local image_loaded = false
    local zoom = 1.0
    local offset_x, offset_y = 0, 0
    local drag_start = nil
    
    while viewing do
        -- Фон
        ui.rect(0, 0, SCR_W, SCR_H, 0x0000)
        
        if not image_loaded then
            -- Загрузка изображения
            ui.text(SCR_W/2 - 50, SCR_H/2 - 10, "Loading image...", 2, 0xFFFF)
            
            local filename = "/temp_view.jpg"
            if url:match("^https?://") then
                net.download(url, filename, "flash")
            else
                -- Копируем локальный файл
                local source = fs.readBytes(url)
                fs.save(filename, source)
            end
            
            image_loaded = ui.drawJPEG(0, 0, filename)
            fs.remove(filename)
        else
            -- Отображение изображения
            local display_w = SCR_W * zoom
            local display_h = SCR_H * zoom
            
            ui.pushClip(0, 0, SCR_W, SCR_H)
            -- Здесь должна быть логика отрисовки с учетом zoom и offset
            -- Для простоты просто рисуем в центре
            if ui.drawJPEG((SCR_W - 400)/2 + offset_x, 
                          (SCR_H - 300)/2 + offset_y, 
                          url) then
                -- Изображение отрисовано
            end
            ui.popClip()
        end
        
        -- Панель управления
        ui.rect(0, SCR_H - 50, SCR_W, 50, 0x2104)
        
        if ui.button(10, SCR_H - 45, 80, 40, "Back", 0xF800) then
            viewing = false
        end
        
        if ui.button(SCR_W - 90, SCR_H - 45, 80, 40, "Save", 0x07E0) then
            -- Сохранение изображения на SD
            if sd then
                local filename = "/sdcard/image_" .. os.time() .. ".jpg"
                if url:match("^https?://") then
                    net.download(url, filename, "sd")
                else
                    -- Копирование файла
                    local data = fs.readBytes(url)
                    sd.append(filename, data)
                end
            end
        end
        
        -- Обработка жестов для zoom/pan
        local touch = ui.getTouch()
        if touch.pressed then
            drag_start = {x = touch.x, y = touch.y}
        elseif touch.touching and drag_start then
            local dx = touch.x - drag_start.x
            local dy = touch.y - drag_start.y
            offset_x = offset_x + dx
            offset_y = offset_y + dy
            drag_start = {x = touch.x, y = touch.y}
        elseif touch.released then
            drag_start = nil
        end
        
        ui.flush()
    end
    
    -- Очистка кэша изображений при выходе
    browser.images = {}
end

-- Инициализация браузера
function browser.init()
    -- Создаем папку для кэша
    if not fs.exists("/cache") then
        fs.mkdir("/cache")
    end
    
    -- Начальная страница
    browser.load_url("about:blank")
    
    -- Стартовая страница с инструкциями
    browser.page_content = {
        {type = "header", content = "Simple Web Browser", level = 1},
        {type = "text", content = "Welcome to the Lua Web Browser!"},
        {type = "text", content = "Features:"},
        {type = "text", content = "• Text and link navigation"},
        {type = "text", content = "• JPEG image display"},
        {type = "text", content = "• Scrollable pages"},
        {type = "text", content = "• History and cache"},
        {type = "text", content = ""},
        {type = "link", url = "https://www.example.com", text = "Example Website"},
        {type = "link", url = "https://www.wikipedia.org", text = "Wikipedia"},
        {type = "link", url = "https://httpbin.org/image/jpeg", text = "Test JPEG Image"},
        {type = "text", content = ""},
        {type = "text", content = "Tap the URL bar to enter a new address."}
    }
    browser.page_title = "Welcome"
    browser.calculate_layout()
end

-- Главная функция
function main()
    browser.init()
    
    -- Основной цикл
    while true do
        browser.draw()
        ui.flush()
        
        -- Проверка обновления каждые 30 секунд
        if hw.millis() % 30000 < 16 then
            -- Можно добавить автообновление или другие фоновые задачи
        end
    end
end

-- Запуск
if wifi_ready then
    main()
else
    -- Ждем WiFi
    while net.status() ~= 3 do
        ui.rect(0, 0, SCR_W, SCR_H, 0x0000)
        ui.text(50, SCR_H/2 - 20, "Waiting for WiFi...", 3, 0xFFFF)
        ui.flush()
        net.connect(wifi_ssid, wifi_password)
    end
    main()
end
