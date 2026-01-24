-- e621 simple client for LuaWatch - Single post version
-- Константы экрана (закругленный 410x502)
SCR_W = 410
SCR_H = 502
SAFE_MARGIN = 20  -- Отступ от углов для закругленного экрана

-- Отладочный вывод
local debugLog = {}
local MAX_LOG_LINES = 10

function addLog(msg)
    table.insert(debugLog, 1, msg)
    if #debugLog > MAX_LOG_LINES then
        table.remove(debugLog, MAX_LOG_LINES + 1)
    end
    print(msg)
end

-- Состояние приложения
local app = {
    searchText = "cat",
    currentPost = nil,
    loading = false,
    page = 1,
    debugVisible = false,
    lastError = nil,
    downloadProgress = 0,
    downloadTotal = 0
}

-- Настройки
local settings = {
    rating = "safe",
    showDebug = true,
    autoSave = false
}

-- Цвета
local COLORS = {
    bg = 0x0000,
    text = 0xFFFF,
    button = 0x528B,
    buttonActive = 0x7BEF,
    warning = 0xF800,
    safe = 0x07E0,
    questionable = 0xFD20,
    explicit = 0xF800,
    debug = 0xAD55,
    progress = 0x07FF
}

-- Очистка изображений из кэша
function clearImageCache()
    if app.currentPost and app.currentPost.cacheKey then
        ui.unload(app.currentPost.cacheKey)
        addLog("Cache cleared")
    end
end

-- Улучшенный парсинг JSON для e621
function parseJSON(str)
    local result = {}
    local i = 1
    local len = #str
    
    local function skipWhitespace()
        while i <= len and str:sub(i, i):match("%s") do
            i = i + 1
        end
    end
    
    local function parseValue()
        skipWhitespace()
        local char = str:sub(i, i)
        
        if char == '{' then
            return parseObject()
        elseif char == '[' then
            return parseArray()
        elseif char == '"' then
            return parseString()
        elseif char:match("%d") or char == '-' then
            return parseNumber()
        elseif char == 't' and str:sub(i, i+3) == 'true' then
            i = i + 4
            return true
        elseif char == 'f' and str:sub(i, i+4) == 'false' then
            i = i + 5
            return false
        elseif char == 'n' and str:sub(i, i+3) == 'null' then
            i = i + 4
            return nil
        end
        return nil
    end
    
    local function parseObject()
        i = i + 1
        local obj = {}
        
        while true do
            skipWhitespace()
            if str:sub(i, i) == '}' then
                i = i + 1
                return obj
            end
            
            local key = parseString()
            skipWhitespace()
            
            if str:sub(i, i) == ':' then
                i = i + 1
            end
            
            obj[key] = parseValue()
            skipWhitespace()
            
            if str:sub(i, i) == ',' then
                i = i + 1
            end
        end
    end
    
    local function parseArray()
        i = i + 1
        local arr = {}
        
        while true do
            skipWhitespace()
            if str:sub(i, i) == ']' then
                i = i + 1
                return arr
            end
            
            table.insert(arr, parseValue())
            skipWhitespace()
            
            if str:sub(i, i) == ',' then
                i = i + 1
            end
        end
    end
    
    local function parseString()
        i = i + 1
        local start = i
        while i <= len do
            if str:sub(i, i) == '"' then
                local s = str:sub(start, i-1)
                i = i + 1
                return s
            elseif str:sub(i, i) == '\\' then
                i = i + 1
            end
            i = i + 1
        end
        return ""
    end
    
    local function parseNumber()
        local start = i
        local hasDot = false
        
        while i <= len do
            local char = str:sub(i, i)
            if char:match("%d") or char == '.' or (char == '-' and i == start) then
                if char == '.' then
                    hasDot = true
                end
                i = i + 1
            else
                break
            end
        end
        
        local numStr = str:sub(start, i-1)
        return hasDot and tonumber(numStr) or math.floor(tonumber(numStr))
    end
    
    return parseValue()
end

-- Получение одного поста с e621
function fetchPost(tags)
    app.loading = true
    app.lastError = nil
    clearImageCache()
    
    local url = string.format(
        "https://e621.net/posts.json?tags=%s&limit=1&page=%d",
        tags:gsub(" ", "+"),
        app.page
    )
    
    addLog("Fetching: " .. url)
    
    local res = net.get(url)
    
    if res and res.ok and res.code == 200 then
        addLog("Response received: " .. #(res.body or "") .. " bytes")
        
        local data = parseJSON(res.body)
        if data and data.posts and #data.posts > 0 then
            local post = data.posts[1]
            
            -- Проверяем рейтинг
            local showPost = false
            if settings.rating == "safe" and post.rating == "s" then 
                showPost = true
            elseif settings.rating == "questionable" and (post.rating == "s" or post.rating == "q") then 
                showPost = true
            elseif settings.rating == "explicit" then 
                showPost = true
            end
            
            if not showPost then
                app.lastError = "Rating filtered: " .. post.rating
                app.loading = false
                return false
            end
            
            -- Проверяем формат
            local ext = post.file and post.file.ext or ""
            local supported = ext:lower() == "jpg" or ext:lower() == "jpeg" or ext:lower() == "png"
            
            if not supported then
                app.lastError = "Unsupported format: " .. ext
                app.loading = false
                return false
            end
            
            app.currentPost = {
                id = post.id,
                url = post.file.url,
                preview = post.preview and post.preview.url or nil,
                sample = post.sample and post.sample.url or nil,
                width = post.file.width,
                height = post.file.height,
                rating = post.rating,
                tags = post.tags,
                artist = post.tags.artist and post.tags.artist[1] or "unknown",
                cacheKey = "/e621_" .. post.id .. ".jpg",
                fileExt = ext
            }
            
            addLog("Post loaded: ID=" .. post.id .. " " .. post.file.width .. "x" .. post.file.height)
            app.loading = false
            return true
        else
            app.lastError = "No posts found"
            addLog("No posts in response")
        end
    else
        local errMsg = res and res.err or "Unknown error"
        app.lastError = "HTTP " .. (res and res.code or "?") .. ": " .. errMsg
        addLog("HTTP error: " .. app.lastError)
    end
    
    app.loading = false
    return false
end

-- Загрузка изображения
function loadCurrentImage()
    if not app.currentPost then return false end
    
    local imageUrl = app.currentPost.sample or app.currentPost.preview or app.currentPost.url
    
    if not imageUrl then
        app.lastError = "No image URL available"
        return false
    end
    
    -- Проверяем кэш
    if fs.exists(app.currentPost.cacheKey) then
        addLog("Image already in cache")
        return true
    end
    
    addLog("Downloading: " .. imageUrl)
    
    -- Сбрасываем прогресс
    app.downloadProgress = 0
    app.downloadTotal = 0
    
    -- Скачиваем с коллбэком прогресса
    local success = net.download(
        imageUrl, 
        app.currentPost.cacheKey,
        function(loaded, total)
            app.downloadProgress = loaded
            app.downloadTotal = total
            addLog(string.format("Progress: %d/%d", loaded, total))
        end
    )
    
    if success then
        addLog("Download complete")
        return true
    else
        app.lastError = "Download failed"
        addLog("Download failed")
        return false
    end
end

-- Отображение рейтинга
function drawRating(rating, x, y)
    local color = COLORS.text
    local text = "?"
    
    if rating == "s" then
        color = COLORS.safe
        text = "S"
    elseif rating == "q" then
        color = COLORS.questionable
        text = "Q"
    elseif rating == "e" then
        color = COLORS.explicit
        text = "E"
    end
    
    ui.rect(x, y, 25, 25, color)
    ui.text(x + 8, y + 5, text, 2, COLORS.bg)
end

-- Безопасные координаты (учитываем закругленные углы)
function safeX(x)
    return math.max(SAFE_MARGIN, math.min(SCR_W - SAFE_MARGIN, x))
end

function safeY(y)
    return math.max(SAFE_MARGIN, math.min(SCR_H - SAFE_MARGIN, y))
end

-- Отрисовка отладочной информации
function drawDebugInfo()
    if not settings.showDebug then return end
    
    -- Фон для лога
    ui.rect(SAFE_MARGIN, SCR_H - 150, SCR_W - 2*SAFE_MARGIN, 130, 0x2104)
    ui.rect(SAFE_MARGIN, SCR_H - 150, SCR_W - 2*SAFE_MARGIN, 15, COLORS.debug)
    ui.text(SAFE_MARGIN + 5, SCR_H - 147, "DEBUG LOG", 1, COLORS.bg)
    
    -- Лог
    local y = SCR_H - 130
    for i, msg in ipairs(debugLog) do
        if y < SCR_H - SAFE_MARGIN - 10 then
            ui.text(SAFE_MARGIN + 5, y, msg, 1, COLORS.text)
            y = y + 12
        end
    end
    
    -- Статус
    ui.text(SAFE_MARGIN + 5, SCR_H - 20, 
        string.format("Mem: %dKB  Page: %d", 
            math.floor(hw.getFreePsram() / 1024), 
            app.page
        ), 
        1, COLORS.text
    )
end

-- Отображение прогресса загрузки
function drawProgress()
    if app.downloadTotal == 0 then return end
    
    local width = SCR_W - 2*SAFE_MARGIN - 20
    local progressWidth = math.floor((app.downloadProgress / app.downloadTotal) * width)
    
    ui.rect(SAFE_MARGIN + 10, SCR_H - 180, width, 15, 0x4208)
    ui.rect(SAFE_MARGIN + 10, SCR_H - 180, progressWidth, 15, COLORS.progress)
    
    local percent = math.floor((app.downloadProgress / app.downloadTotal) * 100)
    local text = string.format("%d%% (%d/%d KB)", 
        percent, 
        math.floor(app.downloadProgress / 1024),
        math.floor(app.downloadTotal / 1024)
    )
    ui.text(SCR_W/2 - 40, SCR_H - 178, text, 1, COLORS.text)
end

-- Основной интерфейс
function draw()
    -- Фон
    ui.rect(0, 0, SCR_W, SCR_H, COLORS.bg)
    
    -- Верхняя панель (безопасные координаты)
    ui.rect(SAFE_MARGIN, SAFE_MARGIN, SCR_W - 2*SAFE_MARGIN, 50, 0x2104)
    
    -- Поле поиска
    ui.rect(SAFE_MARGIN + 10, SAFE_MARGIN + 10, 200, 30, 0x4208)
    ui.text(SAFE_MARGIN + 15, SAFE_MARGIN + 15, app.searchText, 2, COLORS.text)
    
    -- Кнопка поиска
    if ui.button(SAFE_MARGIN + 220, SAFE_MARGIN + 10, 60, 30, "GO", COLORS.button) then
        if app.searchText ~= "" and #app.searchText > 0 then
            app.page = 1
            fetchPost(app.searchText)
        end
    end
    
    -- Кнопка настроек
    if ui.button(SAFE_MARGIN + 290, SAFE_MARGIN + 10, 60, 30, "SET", COLORS.button) then
        app.currentView = "settings"
    end
    
    if app.currentView == "settings" then
        drawSettings()
        return
    end
    
    -- Индикатор загрузки
    if app.loading then
        ui.text(SCR_W/2 - 30, SCR_H/2 - 20, "LOADING...", 2, COLORS.text)
        drawProgress()
        drawDebugInfo()
        return
    end
    
    -- Ошибка
    if app.lastError then
        ui.text(SCR_W/2 - 100, SCR_H/2 - 40, "ERROR:", 2, COLORS.warning)
        ui.text(SCR_W/2 - 100, SCR_H/2, app.lastError, 1, COLORS.text)
        
        if ui.button(SCR_W/2 - 60, SCR_H/2 + 40, 120, 40, "RETRY", COLORS.button) then
            app.lastError = nil
            fetchPost(app.searchText)
        end
        drawDebugInfo()
        return
    end
    
    -- Нет поста
    if not app.currentPost then
        ui.text(SCR_W/2 - 80, SCR_H/2 - 20, "NO POST", 2, COLORS.text)
        ui.text(SCR_W/2 - 150, SCR_H/2 + 20, "Enter tags and press GO", 1, COLORS.text)
        drawDebugInfo()
        return
    end
    
    -- Отображение поста
    drawPost()
    
    -- Нижняя панель управления
    drawControls()
    
    -- Отладочная информация
    drawDebugInfo()
end

-- Отображение поста
function drawPost()
    local post = app.currentPost
    if not post then return end
    
    -- Область для изображения (безопасная зона)
    local imgX = SAFE_MARGIN
    local imgY = SAFE_MARGIN + 60
    local imgW = SCR_W - 2*SAFE_MARGIN
    local imgH = SCR_H - SAFE_MARGIN - 160  -- Оставляем место для управления и дебага
    
    -- Фон для изображения
    ui.rect(imgX, imgY, imgW, imgH, 0x2104)
    
    -- Загружаем и отображаем изображение
    if fs.exists(post.cacheKey) then
        local success = ui.drawJPEG(imgX + 5, imgY + 5, post.cacheKey)
        if not success then
            ui.text(imgX + imgW/2 - 40, imgY + imgH/2, "Display error", 2, COLORS.warning)
            addLog("Display failed for: " .. post.cacheKey)
        end
    else
        -- Показываем информацию о посте
        ui.text(imgX + 10, imgY + 10, "ID: " .. post.id, 2, COLORS.text)
        ui.text(imgX + 10, imgY + 35, post.artist, 2, COLORS.text)
        ui.text(imgX + 10, imgY + 60, string.format("%dx%d", post.width, post.height), 1, COLORS.text)
        ui.text(imgX + 10, imgY + 80, "Click LOAD to download", 1, COLORS.text)
        
        -- Рейтинг
        drawRating(post.rating, imgX + imgW - 40, imgY + 10)
    end
    
    -- Информация о посте
    ui.text(imgX + 5, imgY + imgH + 5, "Tags: " .. app.searchText, 1, COLORS.text)
end

-- Панель управления
function drawControls()
    local y = SCR_H - SAFE_MARGIN - 40
    local btnW = 80
    local spacing = 10
    
    -- Кнопка загрузки
    if ui.button(SAFE_MARGIN, y, btnW, 40, "LOAD", COLORS.button) then
        loadCurrentImage()
    end
    
    -- Кнопка сохранения
    if ui.button(SAFE_MARGIN + btnW + spacing, y, btnW, 40, "SAVE", COLORS.buttonActive) then
        saveToSD()
    end
    
    -- Кнопка предыдущего
    if ui.button(SAFE_MARGIN + 2*(btnW + spacing), y, 60, 40, "<<", COLORS.button) and app.page > 1 then
        app.page = app.page - 1
        fetchPost(app.searchText)
    end
    
    -- Номер страницы
    ui.rect(SAFE_MARGIN + 3*(btnW + spacing), y, 60, 40, 0x2104)
    ui.text(SAFE_MARGIN + 3*(btnW + spacing) + 20, y + 10, tostring(app.page), 2, COLORS.text)
    
    -- Кнопка следующего
    if ui.button(SAFE_MARGIN + 4*(btnW + spacing), y, 60, 40, ">>", COLORS.button) then
        app.page = app.page + 1
        fetchPost(app.searchText)
    end
    
    -- Кнопка очистки
    if ui.button(SAFE_MARGIN + 5*(btnW + spacing), y, 60, 40, "X", COLORS.warning) then
        clearImageCache()
        app.currentPost = nil
    end
end

-- Сохранение на SD карту
function saveToSD()
    if not app.currentPost or not app.currentPost.cacheKey then
        addLog("No post to save")
        return
    end
    
    if not fs.exists(app.currentPost.cacheKey) then
        addLog("Image not loaded yet")
        return
    end
    
    if not sd.exists then
        addLog("SD card not available")
        app.lastError = "SD card not found"
        return
    end
    
    local sdPath = "/e621_" .. app.currentPost.id .. ".jpg"
    addLog("Saving to SD: " .. sdPath)
    
    local content = fs.readBytes(app.currentPost.cacheKey)
    if not content then
        addLog("Failed to read image")
        return
    end
    
    -- Проверяем размер
    if #content > 10 * 1024 * 1024 then  -- 10MB limit
        addLog("File too large")
        return
    end
    
    -- Записываем на SD
    local result = sd.append(sdPath, content)
    if result and result.ok then
        addLog("Saved to SD successfully")
    else
        addLog("Save failed")
    end
end

-- Окно настроек
function drawSettings()
    -- Фон
    ui.rect(SAFE_MARGIN, SAFE_MARGIN, SCR_W - 2*SAFE_MARGIN, SCR_H - 2*SAFE_MARGIN, 0x2104)
    
    ui.text(SCR_W/2 - 40, SAFE_MARGIN + 20, "SETTINGS", 3, COLORS.text)
    
    -- Рейтинг
    ui.text(SAFE_MARGIN + 20, SAFE_MARGIN + 70, "Rating Filter:", 2, COLORS.text)
    local ratingY = SAFE_MARGIN + 100
    
    local ratings = {
        {value = "safe", label = "SAFE", color = COLORS.safe},
        {value = "questionable", label = "QUESTIONABLE", color = COLORS.questionable},
        {value = "explicit", label = "EXPLICIT", color = COLORS.explicit}
    }
    
    for _, r in ipairs(ratings) do
        local color = (settings.rating == r.value) and r.color or COLORS.button
        if ui.button(SAFE_MARGIN + 20, ratingY, 150, 40, r.label, color) then
            settings.rating = r.value
        end
        ratingY = ratingY + 50
    end
    
    -- Отладочный вывод
    local debugY = ratingY + 20
    ui.text(SAFE_MARGIN + 20, debugY, "Debug Output:", 2, COLORS.text)
    
    local debugColor = settings.showDebug and COLORS.buttonActive or COLORS.button
    if ui.button(SAFE_MARGIN + 20, debugY + 30, 120, 40, "DEBUG", debugColor) then
        settings.showDebug = not settings.showDebug
    end
    
    -- Автосохранение
    local autoY = debugY + 80
    ui.text(SAFE_MARGIN + 20, autoY, "Auto-save to SD:", 2, COLORS.text)
    
    local autoColor = settings.autoSave and COLORS.buttonActive or COLORS.button
    if ui.button(SAFE_MARGIN + 20, autoY + 30, 120, 40, "AUTO SAVE", autoColor) then
        settings.autoSave = not settings.autoSave
    end
    
    -- Кнопка назад
    if ui.button(SCR_W/2 - 60, SCR_H - SAFE_MARGIN - 60, 120, 40, "BACK", COLORS.button) then
        app.currentView = nil
        -- Сохраняем настройки
        saveSettings()
    end
end

-- Сохранение настроек
function saveSettings()
    local settingsStr = string.format(
        '{"rating":"%s","showDebug":%s,"autoSave":%s}',
        settings.rating,
        tostring(settings.showDebug),
        tostring(settings.autoSave)
    )
    
    local ok = fs.save("/e621_settings.json", settingsStr)
    if ok then
        addLog("Settings saved")
    else
        addLog("Failed to save settings")
    end
end

-- Загрузка настроек
function loadSettings()
    if fs.exists("/e621_settings.json") then
        local content = fs.load("/e621_settings.json")
        if content then
            local data = parseJSON(content)
            if data then
                settings.rating = data.rating or "safe"
                settings.showDebug = data.showDebug ~= false
                settings.autoSave = data.autoSave or false
                addLog("Settings loaded")
            end
        end
    end
end

-- Инициализация
function init()
    addLog("=== e621 Client Starting ===")
    addLog("Screen: " .. SCR_W .. "x" .. SCR_H)
    addLog("Free PSRAM: " .. math.floor(hw.getFreePsram() / 1024) .. "KB")
    
    -- Загружаем настройки
    loadSettings()
    
    -- Проверяем сеть
    if net.status() ~= 3 then
        app.lastError = "WiFi not connected"
        addLog("WiFi not connected")
    else
        addLog("WiFi connected: " .. (net.getIP() or "unknown"))
        -- Автоматический поиск при запуске
        fetchPost(app.searchText)
    end
    
    addLog("Ready")
end

-- Запуск приложения
init()

-- Быстрые теги для демо
local quickTags = {"cat", "dog", "fox", "wolf", "bird", "feral", "anthro"}

-- Основной цикл
function main()
    -- Если нет поста, показываем быстрые теги
    if not app.currentPost and not app.loading and not app.lastError then
        ui.rect(SAFE_MARGIN, 120, SCR_W - 2*SAFE_MARGIN, 200, 0x2104)
        ui.text(SAFE_MARGIN + 10, 130, "Quick tags:", 2, COLORS.text)
        
        local x, y = SAFE_MARGIN + 10, 160
        for i, tag in ipairs(quickTags) do
            if ui.button(x, y, 70, 35, tag, COLORS.button) then
                app.searchText = tag
                app.page = 1
                fetchPost(tag)
            end
            x = x + 75
            if x > SCR_W - SAFE_MARGIN - 80 then
                x = SAFE_MARGIN + 10
                y = y + 40
            end
        end
    end
end

-- Модифицированный draw для включения main()
function draw()
    -- Фон
    ui.rect(0, 0, SCR_W, SCR_H, COLORS.bg)
    
    -- Верхняя панель
    ui.rect(SAFE_MARGIN, SAFE_MARGIN, SCR_W - 2*SAFE_MARGIN, 50, 0x2104)
    
    -- Поле поиска
    ui.rect(SAFE_MARGIN + 10, SAFE_MARGIN + 10, 200, 30, 0x4208)
    ui.text(SAFE_MARGIN + 15, SAFE_MARGIN + 15, app.searchText, 2, COLORS.text)
    
    -- Кнопка поиска
    if ui.button(SAFE_MARGIN + 220, SAFE_MARGIN + 10, 60, 30, "GO", COLORS.button) then
        if app.searchText ~= "" and #app.searchText > 0 then
            app.page = 1
            fetchPost(app.searchText)
        end
    end
    
    -- Кнопка настроек
    if ui.button(SAFE_MARGIN + 290, SAFE_MARGIN + 10, 60, 30, "SET", COLORS.button) then
        app.currentView = "settings"
    end
    
    if app.currentView == "settings" then
        drawSettings()
        drawDebugInfo()
        return
    end
    
    -- Индикатор загрузки
    if app.loading then
        ui.text(SCR_W/2 - 30, SCR_H/2 - 20, "LOADING...", 2, COLORS.text)
        drawProgress()
        drawDebugInfo()
        return
    end
    
    -- Ошибка
    if app.lastError then
        ui.text(SCR_W/2 - 100, SCR_H/2 - 40, "ERROR:", 2, COLORS.warning)
        ui.text(SCR_W/2 - 100, SCR_H/2, app.lastError, 1, COLORS.text)
        
        if ui.button(SCR_W/2 - 60, SCR_H/2 + 40, 120, 40, "RETRY", COLORS.button) then
            app.lastError = nil
            fetchPost(app.searchText)
        end
        drawDebugInfo()
        return
    end
    
    -- Нет поста - показываем быстрые теги
    if not app.currentPost then
        main()  -- Показываем быстрые теги
        drawDebugInfo()
        return
    end
    
    -- Отображение поста
    drawPost()
    
    -- Панель управления
    drawControls()
    
    -- Отладочная информация
    drawDebugInfo()
end
