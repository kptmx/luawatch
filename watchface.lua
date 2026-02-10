-- Простая файловая читалка
local SCR_W, SCR_H = 410, 502

-- Конфигурация
local CONFIG = {
    listX = 5,
    listY = 65,
    listW = 400,
    listH = 375,
    itemHeight = 35,
    maxLinesPerPage = 30,
    textLineHeight = 15,
    maxCharsPerLine = 50
}

-- Состояния
local state = {
    mode = "flash",  -- "flash" или "sd"
    path = "/",
    files = {},
    textLines = {},
    currentPage = 1,
    totalPages = 1,
    scrollOffset = 0,
    isTextMode = false,
    currentFile = nil,
    lastTouchY = 0,
    velocity = 0,
    lastUpdate = hw.millis()
}

-- Простой полосы скролла
local function drawScrollbar(x, y, h, contentH, scrollY)
    local barH = math.max(20, h * h / contentH)
    local barY = y + (scrollY / contentH) * (h - barH)
    ui.rect(x - 8, y, 6, h, 0x4208)           -- Фон скроллбара
    ui.rect(x - 8, barY, 6, barH, 0x8410)     -- Ползунок
end

-- Получение списка файлов (простая версия)
local function getFiles(path, mode)
    local files = {}
    
    if mode == "flash" then
        local res = fs.list(path)
        if res.ok then
            for i, name in ipairs(res) do
                table.insert(files, {
                    name = name,
                    path = path .. (path:sub(-1) == "/" and "" or "/") .. name
                })
            end-- Файловая читалка с улучшенным скроллингом
local SCR_W, SCR_H = 410, 502

-- Состояния
local state = {
    mode = "flash",  -- "flash" или "sd"
    path = "/",
    files = {},
    textContent = "",
    textLines = {},
    currentPage = 1,
    totalPages = 1,
    scrollY = 0,
    maxScrollY = 0,
    isTextMode = false,
    selectedFile = nil,
    listScroll = 0,
    listArea = {x=5, y=65, w=400, h=375},
    listItemHeight = 30
}

-- Инициализация
function initFileViewer()
    state.files = getFiles(state.path, state.mode)
    state.scrollY = 0
    state.currentPage = 1
    state.isTextMode = false
end

-- Получение списка файлов
function getFiles(path, mode)
    local result = {}
    
    if mode == "flash" then
        local res = fs.list(path)
        if res.ok then
            for i, name in ipairs(res) do
                table.insert(result, {
                    name = name,
                    path = path .. (path:sub(-1) == "/" and "" or "/") .. name,
                    isDir = false  -- Упрощённо
                })
            end
        end
    else -- sd
        if sd and sd_ok then
            local res = sd.list(path)
            if res.ok then
                for i, name in ipairs(res) do
                    table.insert(result, {
                        name = name,
                        path = path .. (path:sub(-1) == "/" and "" or "/") .. name,
                        isDir = false
                    })
                end
            end
        end
    end
    
    -- Сортируем: сначала папки, потом файлы
    table.sort(result, function(a, b)
        -- TODO: определить папки
        return a.name < b.name
    end)
    
    return result
end

-- Загрузка текстового файла
function loadTextFile(path, mode)
    state.textContent = ""
    state.textLines = {}
    state.isTextMode = true
    state.scrollY = 0
    state.currentPage = 1
    
    local content = ""
    if mode == "flash" then
        local res = fs.readBytes(path)
        if res and type(res) == "string" then
            content = res
        end
    else
        if sd_ok then
            local res = sd.readBytes(path)
            if res and type(res) == "string" then
                content = res
            end
        end
    end
    
    state.textContent = content
    
    -- Разбиваем на строки
    local lines = {}
    for line in content:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    state.textLines = lines
    
    -- Рассчитываем общее количество страниц (примерно 30 строк на страницу)
    state.totalPages = math.ceil(#lines / 30)
    state.maxScrollY = math.max(0, state.totalPages * state.listArea.h - state.listArea.h)
    
    -- Устанавливаем скролл на среднюю треть (страница 2 из 3)
    state.listScroll = state.listArea.h  -- Вторая треть
end

-- Отрисовка списка файлов с улучшенным скроллингом
function drawFileList()
    local area = state.listArea
    local visibleItems = math.floor(area.h / state.listItemHeight)
    
    -- Расчёт размеров виртуального списка (в 3 раза больше реального)
    local virtualHeight = area.h * 3
    local totalContentHeight = #state.files * state.listItemHeight
    local maxListScroll = math.max(0, totalContentHeight - area.h)
    
    -- Ограничиваем скролл
    state.listScroll = math.max(0, math.min(state.listScroll, maxListScroll))
    
    -- Определяем, на какой "странице" (трети) мы находимся
    local thirdHeight = area.h
    local currentThird = math.floor(state.listScroll / thirdHeight) + 1
    
    -- Если мы вышли за пределы первой или последней трети - обновляем список
    if currentThird == 1 and state.scrollY > 0 then
        -- Прокручиваем в начало
        state.listScroll = 0
    elseif currentThird == 3 and state.scrollY < maxListScroll then
        -- Прокручиваем к концу
        state.listScroll = maxListScroll
    end
    
    -- Вычисляем стартовый индекс для отрисовки
    local startIdx = math.floor((state.listScroll % virtualHeight) / state.listItemHeight) + 1
    local offsetInPixels = (state.listScroll % virtualHeight) % state.listItemHeight
    
    -- Фон списка
    ui.rect(area.x, area.y, area.w, area.h, 0)
    
    -- Отрисовка элементов
    for i = 0, visibleItems do
        local idx = startIdx + i
        if idx <= #state.files then
            local file = state.files[idx]
            local y = area.y + i * state.listItemHeight - offsetInPixels
            
            -- Проверка видимости
            if y >= area.y and y + state.listItemHeight <= area.y + area.h then
                local color = 0x8410  -- Серый фон
                local textColor = 0xFFFF  -- Белый текст
                
                if state.selectedFile == file.path then
                    color = 0x001F  -- Синий для выбранного
                    textColor = 0xFFFF
                end
                
                -- Прямоугольник элемента
                ui.rect(area.x, y, area.w, state.listItemHeight, color)
                
                -- Иконка папки или файла
                local icon = file.isDir and "[D]" or "[F]"
                ui.text(area.x + 5, y + 8, icon, 1, 0x07E0)  -- Зелёный для папок
                
                -- Имя файла
                local name = file.name
                if #name > 30 then
                    name = name:sub(1, 27) .. "..."
                end
                ui.text(area.x + 40, y + 8, name, 1, textColor)
            end
        end
    end
    
    -- Индикатор страниц (внизу экрана)
    local pages = math.ceil(totalContentHeight / area.h)
    local currentPage = math.floor(state.listScroll / area.h) + 1
    
    if pages > 1 then
        ui.rect(area.x, area.y + area.h - 20, area.w, 20, 0x4208)
        ui.text(area.x + 10, area.y + area.h - 15, 
                string.format("Page %d/%d", currentPage, pages), 1, 0xFFFF)
    end
end

-- Отрисовка текста с постраничным скроллингом
function drawTextReader()
    local area = state.listArea
    local linesPerPage = 25
    local lineHeight = 15
    
    -- Рассчитываем текущую страницу на основе скролла
    local pageHeight = area.h
    local virtualHeight = pageHeight * 3
    local currentPage = math.floor(state.listScroll / pageHeight) + 1
    
    -- Если мы на первой трети и есть предыдущая страница
    if currentPage == 1 and state.currentPage > 1 then
        state.currentPage = state.currentPage - 1
        state.listScroll = pageHeight  -- Возвращаем на среднюю треть
    -- Если мы на третьей трети и есть следующая страница
    elseif currentPage == 3 and state.currentPage < state.totalPages then
        state.currentPage = state.currentPage + 1
        state.listScroll = pageHeight  -- Возвращаем на среднюю треть
    end
    
    -- Определяем строки для текущей страницы
    local startLine = (state.currentPage - 1) * linesPerPage + 1
    local endLine = math.min(startLine + linesPerPage - 1, #state.textLines)
    
    -- Фон
    ui.rect(area.x, area.y, area.w, area.h, 0)
    
    -- Отрисовка строк
    for i = 1, math.min(linesPerPage, endLine - startLine + 1) do
        local lineIdx = startLine + i - 1
        if lineIdx <= #state.textLines then
            local line = state.textLines[lineIdx]
            
            -- Перенос строк (грубый, но рабочий)
            local charsPerLine = math.floor(area.w / 8) - 4  ~8 пикселей на символ
            if #line > charsPerLine then
                -- Разбиваем длинные строки
                for j = 1, math.ceil(#line / charsPerLine) do
                    local startPos = (j-1) * charsPerLine + 1
                    local endPos = math.min(j * charsPerLine, #line)
                    local subline = line:sub(startPos, endPos)
                    local subY = area.y + (i-1 + (j-1)) * lineHeight
                    if subY + lineHeight <= area.y + area.h then
                        ui.text(area.x + 5, subY + 5, subline, 1, 0xFFFF)
                    end
                end
            else
                local y = area.y + (i-1) * lineHeight
                if y + lineHeight <= area.y + area.h then
                    ui.text(area.x + 5, y + 5, line, 1, 0xFFFF)
                end
            end
        end
    end
    
    -- Пагинация
    ui.rect(area.x, area.y + area.h - 25, area.w, 25, 0x2104)
    ui.text(area.x + 10, area.y + area.h - 20, 
            string.format("Page %d/%d", state.currentPage, state.totalPages), 
            1, 0xFFFF)
    
    -- Кнопки навигации
    if ui.button(area.x + 120, area.y + area.h - 25, 80, 25, "Prev", 0x001F) then
        if state.currentPage > 1 then
            state.currentPage = state.currentPage - 1
            state.listScroll = pageHeight  -- На среднюю треть
        end
    end
    
    if ui.button(area.x + 210, area.y + area.h - 25, 80, 25, "Next", 0x001F) then
        if state.currentPage < state.totalPages then
            state.currentPage = state.currentPage + 1
            state.listScroll = pageHeight  -- На среднюю треть
        end
    end
    
    -- Кнопка возврата
    if ui.button(area.x + 300, area.y + area.h - 25, 95, 25, "Back", 0xF800) then
        state.isTextMode = false
        state.listScroll = 0
    end
end

-- Обработка тапов в списке
function handleFileListTap()
    local area = state.listArea
    
    -- Вычисляем нажатый элемент
    if ui.touch.pressed then
        local tx, ty = ui.touch.x, ui.touch.y
        
        if tx >= area.x and tx <= area.x + area.w and
           ty >= area.y and ty <= area.y + area.h then
           
            -- Вычисляем индекс с учётом скролла
            local itemY = ty - area.y + state.listScroll
            local idx = math.floor(itemY / state.listItemHeight) + 1
            
            if idx <= #state.files then
                local file = state.files[idx]
                state.selectedFile = file.path
                
                -- Проверяем расширение (грубая проверка)
                local ext = file.name:match("%.(.+)$")
                if ext and (ext:lower() == "txt" or ext:lower() == "lua" or 
                           ext:lower() == "json" or ext:lower() == "md") then
                    -- Это текстовый файл - открываем
                    loadTextFile(file.path, state.mode)
                else
                    -- Можно добавить обработку других типов файлов
                    ui.rect(0, 0, SCR_W, SCR_H, 0xF800)  -- Красный фон
                    ui.text(50, 200, "Not a text file!", 3, 0xFFFF)
                    ui.text(50, 230, "Can only read .txt, .lua, .json, .md", 1, 0xFFFF)
                    ui.flush()
                    hw.millisDelay(2000)
                end
            end
        end
    end
end

-- Основной цикл отрисовки
function draw()
    -- Фон
    ui.rect(0, 0, SCR_W, SCR_H, 0)
    
    -- Заголовок
    ui.text(10, 20, "File Reader", 3, 0x07E0)
    ui.text(10, 50, "Path: " .. state.path, 1, 0xFFFF)
    
    -- Переключатель режима
    if ui.button(280, 15, 60, 30, state.mode:upper(), 
                 state.mode == "flash" and 0x001F or 0xF800) then
        state.mode = state.mode == "flash" and "sd" or "flash"
        if state.mode == "sd" and not sd_ok then
            state.mode = "flash"
            ui.text(10, 250, "SD card not mounted!", 2, 0xF800)
            ui.flush()
            hw.millisDelay(1000)
        else
            initFileViewer()
        end
    end
    
    -- Кнопка обновления
    if ui.button(350, 15, 60, 30, "Refresh", 0x8410) then
        initFileViewer()
    end
    
    if not state.isTextMode then
        -- Режим списка файлов
        ui.beginList(state.listArea.x, state.listArea.y, 
                    state.listArea.w, state.listArea.h, 
                    state.listScroll, state.listArea.h * 3)
        drawFileList()
        handleFileListTap()
        ui.endList()
        
        -- Статус
        ui.text(10, SCR_H - 30, string.format("Files: %d", #state.files), 1, 0xFFFF)
        
    else
        -- Режим чтения текста
        ui.beginList(state.listArea.x, state.listArea.y,
                    state.listArea.w, state.listArea.h,
                    state.listScroll, state.listArea.h * 3)
        drawTextReader()
        ui.endList()
    end
end

-- Функция задержки (хелпер)
function millisDelay(ms)
    local start = hw.millis()
    while hw.millis() - start < ms do
        -- Просто ждём
    end
end

-- Инициализация при запуске
initFileViewer()
        end
    elseif mode == "sd" and sd_ok then
        local res = sd.list(path)
        if res.ok then
            for i, name in ipairs(res) do
                table.insert(files, {
                    name = name,
                    path = path .. (path:sub(-1) == "/" and "" or "/") .. name
                })
            end
        end
    end
    
    return files
end

-- Загрузка текстового файла
local function loadTextFile(path, mode)
    state.isTextMode = true
    state.currentFile = path
    state.currentPage = 1
    state.textLines = {}
    state.scrollOffset = 0
    
    local content = ""
    local success = false
    
    if mode == "flash" then
        local res = fs.load(path)
        if res then
            content = res
            success = true
        end
    elseif mode == "sd" and sd_ok then
        local res = sd.readBytes(path)
        if res and type(res) == "string" then
            content = res
            success = true
        end
    end
    
    if success then
        -- Разбиваем на строки
        for line in content:gmatch("[^\r\n]+") do
            table.insert(state.textLines, line)
        end
        
        -- Рассчитываем страницы
        state.totalPages = math.ceil(#state.textLines / CONFIG.maxLinesPerPage)
        if state.totalPages == 0 then state.totalPages = 1 end
        
        print("Loaded file:", path)
        print("Lines:", #state.textLines)
        print("Pages:", state.totalPages)
    else
        state.textLines = {"[ERROR: Cannot read file]"}
        state.totalPages = 1
    end
end

-- Отрисовка списка файлов (без использования beginList)
local function drawFileList()
    local area = CONFIG
    local startIdx = math.floor(state.scrollOffset / area.itemHeight)
    local maxVisible = math.floor(area.listH / area.itemHeight) + 1
    
    -- Фон
    ui.rect(area.listX, area.listY, area.listW, area.listH, 0)
    
    -- Отрисовка видимых файлов
    for i = 0, maxVisible do
        local idx = startIdx + i + 1
        if idx <= #state.files then
            local file = state.files[idx]
            local y = area.listY + i * area.itemHeight - (state.scrollOffset % area.itemHeight)
            
            -- Проверка видимости
            if y >= area.listY and y + area.itemHeight <= area.listY + area.listH then
                -- Подсветка при наведении
                local touch = ui.getTouch()
                local isOver = touch.touching and 
                              touch.x >= area.listX and touch.x <= area.listX + area.listW and
                              touch.y >= y and touch.y <= y + area.itemHeight
                
                local bgColor = isOver and 0x39E7 or 0x2104
                ui.rect(area.listX, y, area.listW, area.itemHeight, bgColor)
                
                -- Имя файла
                local displayName = file.name
                if #displayName > 35 then
                    displayName = displayName:sub(1, 32) .. "..."
                end
                
                ui.text(area.listX + 10, y + 12, displayName, 1, 0xFFFF)
            end
        end
    end
    
    -- Скроллбар если нужно
    local totalHeight = #state.files * area.itemHeight
    if totalHeight > area.listH then
        drawScrollbar(area.listX + area.listW - 5, area.listY, area.listH, 
                     totalHeight, state.scrollOffset)
    end
end

-- Отрисовка текстового файла
local function drawTextReader()
    local area = CONFIG
    
    -- Фон
    ui.rect(area.listX, area.listY, area.listW, area.listH, 0)
    
    -- Рассчитываем, какие строки показывать
    local startLine = (state.currentPage - 1) * CONFIG.maxLinesPerPage + 1
    local endLine = math.min(startLine + CONFIG.maxLinesPerPage - 1, #state.textLines)
    
    -- Отступ для текста
    local textX = area.listX + 10
    local textY = area.listY + 10
    
    -- Отрисовка строк текущей страницы
    for i = startLine, endLine do
        local lineIdx = i - startLine + 1
        local line = state.textLines[i]
        
        if line then
            -- Перенос строк (грубый)
            local charsPerLine = CONFIG.maxCharsPerLine
            local yPos = textY + (lineIdx - 1) * CONFIG.textLineHeight
            
            if #line <= charsPerLine then
                ui.text(textX, yPos, line, 1, 0xFFFF)
            else
                -- Разбиваем длинные строки
                for chunk = 1, math.ceil(#line / charsPerLine) do
                    local startChar = (chunk-1) * charsPerLine + 1
                    local endChar = math.min(chunk * charsPerLine, #line)
                    local chunkY = yPos + (chunk-1) * CONFIG.textLineHeight
                    if chunkY < area.listY + area.listH - CONFIG.textLineHeight then
                        ui.text(textX, chunkY, line:sub(startChar, endChar), 1, 0xFFFF)
                    end
                end
            end
        end
    end
    
    -- Панель управления внизу
    local panelY = area.listY + area.listH + 5
    ui.rect(0, panelY, SCR_W, 40, 0x2104)
    
    -- Информация о странице
    ui.text(10, panelY + 12, 
           string.format("Page %d/%d - %s", state.currentPage, state.totalPages, 
                        state.currentFile or "Unknown"), 1, 0xFFFF)
    
    -- Кнопки навигации
    if ui.button(SCR_W - 180, panelY + 5, 55, 30, "Back", 0xF800) then
        state.isTextMode = false
        state.scrollOffset = 0
    end
    
    if ui.button(SCR_W - 120, panelY + 5, 55, 30, "Prev", 0x001F) and state.currentPage > 1 then
        state.currentPage = state.currentPage - 1
    end
    
    if ui.button(SCR_W - 60, panelY + 5, 55, 30, "Next", 0x001F) and state.currentPage < state.totalPages then
        state.currentPage = state.currentPage + 1
    end
end

-- Обработка ввода в режиме списка файлов
local function handleFileListInput()
    local area = CONFIG
    local touch = ui.getTouch()
    
    -- Обычный скролл мышью/тапом
    if touch.touching then
        local deltaY = touch.y - state.lastTouchY
        state.lastTouchY = touch.y
        
        -- Прокрутка
        local maxScroll = math.max(0, #state.files * area.itemHeight - area.listH)
        state.scrollOffset = state.scrollOffset - deltaY * 2
        state.scrollOffset = math.max(0, math.min(state.scrollOffset, maxScroll))
    else
        state.lastTouchY = touch.y
    end
    
    -- Обработка кликов по файлам (когда отпускаем палец)
    if touch.released then
        local clickY = touch.y - area.listY + state.scrollOffset
        local clickedIdx = math.floor(clickY / area.itemHeight) + 1
        
        if clickedIdx >= 1 and clickedIdx <= #state.files then
            local file = state.files[clickedIdx]
            
            -- Проверяем, текстовый ли это файл
            local ext = file.name:match("%.(.+)$")
            local isTextFile = ext and (
                ext:lower() == "txt" or
                ext:lower() == "lua" or
                ext:lower() == "json" or
                ext:lower() == "md" or
                ext:lower() == "xml" or
                ext:lower() == "csv" or
                ext:lower() == "ini" or
                ext:lower() == "cfg"
            )
            
            if isTextFile then
                loadTextFile(file.path, state.mode)
            else
                -- Можно открыть диалог с ошибкой
                print("Not a text file:", file.name)
            end
        end
    end
end

-- Обработка ввода в текстовом режиме
local function handleTextReaderInput()
    local touch = ui.getTouch()
    
    if touch.pressed then
        -- Простой свайп для смены страниц
        state.lastTouchY = touch.y
    end
    
    if touch.released then
        local deltaY = state.lastTouchY - touch.y
        
        -- Свайп вверх/вниз для смены страниц
        if math.abs(deltaY) > 50 then
            if deltaY > 0 and state.currentPage < state.totalPages then
                state.currentPage = state.currentPage + 1
            elseif deltaY < 0 and state.currentPage > 1 then
                state.currentPage = state.currentPage - 1
            end
        end
    end
end

-- Загрузка файлов при старте
local function refreshFileList()
    state.files = getFiles(state.path, state.mode)
    state.scrollOffset = 0
    print("Refreshed file list, found", #state.files, "files")
end

-- Инициализация
refreshFileList()

-- Основной цикл отрисовки
function draw()
    -- Фон
    ui.rect(0, 0, SCR_W, SCR_H, 0)
    
    -- Заголовок
    ui.text(10, 20, "File Reader", 3, 0x07E0)
    ui.text(10, 50, string.format("Mode: %s | Path: %s", state.mode:upper(), state.path), 1, 0xFFFF)
    
    -- Переключатель режима
    if ui.button(280, 15, 60, 30, state.mode:upper(), 
                 state.mode == "flash" and 0x001F or 0xF800) then
        state.mode = state.mode == "flash" and "sd" or "flash"
        if state.mode == "sd" and not sd_ok then
            state.mode = "flash"
            ui.text(150, 200, "No SD Card!", 2, 0xF800)
            ui.flush()
            delay(1000)
        else
            refreshFileList()
        end
    end
    
    -- Кнопка обновления
    if ui.button(350, 15, 55, 30, "Refresh", 0x8410) then
        refreshFileList()
    end
    
    if not state.isTextMode then
        -- Режим списка файлов
        drawFileList()
        handleFileListInput()
        
        -- Статистика внизу
        ui.text(10, SCR_H - 25, string.format("Files: %d", #state.files), 1, 0xFFFF)
    else
        -- Режим чтения текста
        drawTextReader()
        handleTextReaderInput()
    end
    
    ui.flush()
end

-- Хелпер для задержки
function delay(ms)
    local start = hw.millis()
    while hw.millis() - start < ms do end
end
