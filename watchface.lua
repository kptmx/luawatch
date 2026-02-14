-- Константы
local W, H = 410, 502
local HEADER_H = 50
local MARGIN_X = 15
local LINE_HEIGHT = 32
local TEXT_SIZE = 2
local CHARS_LIMIT = 28 -- Символов в строке (не байт!)
-- Расчетные высоты
local visibleH = H - HEADER_H
local pageH = visibleH
local contentH = pageH * 3 -- Три экрана высоты
local linesPerPage = math.floor((visibleH - 20) / LINE_HEIGHT)
-- Переменные
local mode = "browser"
local currentSource = "sd" -- или "internal"
local fileList = {}
local fileName = ""
local lines = {}
local totalPages = 0
local currentPage = 0
local scrollY = pageH -- Начинаем всегда с центра (вторая страница)
local animDir = 0
local animProgress = 0
local targetProgress = 0
local isFlip = false
-- === [ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ] ===
-- Подсчет длины строки UTF-8 (чтобы кириллица считалась за 1 символ)
local function utf8_len(s)
    local _, count = string.gsub(s, "[^\128-\193]", "")
    return count
end
-- Умный перенос слов
local function wrapText(text)
    local res = {}
    -- Разбиваем на параграфы
    for paragraph in (text .. "\n"):gmatch("(.-)\r?\n") do
        if paragraph == "" then
            table.insert(res, "")
        else
            local line = ""
            local lineLen = 0
            -- Разбиваем параграф на слова
            for word in paragraph:gmatch("%S+") do
                local wLen = utf8_len(word)
                -- Влезет ли слово в текущую строку?
                if lineLen + wLen + 1 <= CHARS_LIMIT then
                    line = line .. (line == "" and "" or " ") .. word
                    lineLen = lineLen + wLen + (line == "" and 0 or 1)
                else
                    -- Не влезло, сохраняем строку и начинаем новую
                    table.insert(res, line)
                    line = word
                    lineLen = wLen
                end
            end
            if line ~= "" then table.insert(res, line) end
        end
    end
    return res
end
local function loadFile(path)
    local data = (currentSource == "sd") and sd.readBytes(path) or fs.readBytes(path)
    if not data or #data == 0 then return false end
   
    lines = wrapText(data)
    totalPages = math.ceil(#lines / linesPerPage)
    currentPage = 0
    scrollY = pageH
    mode = "reader"
    return true
end
local function refreshFiles()
    fileList = {}
    local res = (currentSource == "sd") and sd.list("/") or fs.list("/")
    if type(res) == "table" then
        for _, name in ipairs(res) do
            if name:lower():match("%.txt$") then table.insert(fileList, name) end
        end
        table.sort(fileList)
    end
end
-- === [ОТРИСОВКА] ===
-- Рисует одну страницу текста по указанному смещению Y
-- Оптимизированная отрисовка страницы
-- Вспомогательная функция для интерполяции цвета (затемнения)
-- t: 0.0 (черный) до 1.0 (полный цвет)
local function getFadeColor(t, maxColor)
    if t <= 0 then return 0x0000 end
    if t >= 1 then return maxColor end
    
    -- Раскладываем 565 цвет на R, G, B
    local r = math.floor(((maxColor >> 11) & 0x1F) * t)
    local g = math.floor(((maxColor >> 5) & 0x3F) * t)
    local b = math.floor((maxColor & 0x1F) * t)
    
    return (r << 11) | (g << 5) | b
end

local function renderPageFade(pIdx, opacity)
    if pIdx < 0 or pIdx >= totalPages or opacity <= 0 then return end
    
    local textColor = getFadeColor(opacity, 0xFFFF)
    local metaColor = getFadeColor(opacity, 0x8410) -- Для служебного текста
    
    local start = pIdx * linesPerPage + 1
    local stop = math.min(start + linesPerPage - 1, #lines)
    
    for i = start, stop do
        local y = HEADER_H + 10 + (i - start) * LINE_HEIGHT
        ui.text(MARGIN_X, y, lines[i], TEXT_SIZE, textColor)
    end
end

-- Переменные для логики фейда
local fadeProgress = 0 -- от -1 (предыдущая) до 1 (следующая)

local function drawReader()
    ui.rect(0, 0, W, H, 0)
    
    -- Шапка (всегда яркая)
    ui.fillRoundRect(0, 0, W, HEADER_H - 5, 0, 0x10A2)
    ui.text(10, 15, string.format("%d / %d", currentPage + 1, totalPages), 2, 0xFFFF)
    if ui.button(W - 80, 5, 70, 35, "EXIT", 0xF800) then mode = "browser" end

    local touch = ui.getTouch()
    local targetFade = 0

    if touch.touching then
        if not lastTouchX then lastTouchX = touch.x end
        -- Считаем горизонтальный или вертикальный свайп (тут по Y, как ты просил)
        local delta = touch.y - lastTouchX
        fadeProgress = delta / (visibleH * 0.8) -- чувствительность
        
        -- Ограничиваем, чтобы не уходить за пределы существующих страниц
        if currentPage == 0 and fadeProgress > 0 then fadeProgress = 0 end
        if currentPage == totalPages - 1 and fadeProgress < 0 then fadeProgress = 0 end
    else
        lastTouchX = nil
        -- Логика переключения
        if math.abs(fadeProgress) > 0.3 then
            targetFade = (fadeProgress > 0) and 1 or -1
        else
            targetFade = 0
        end
        
        -- Плавный довод к цели
        if math.abs(fadeProgress - targetFade) > 0.05 then
            fadeProgress = fadeProgress + (targetFade - fadeProgress) * 0.2
        else
            -- Завершаем переход
            if targetFade == 1 then currentPage = currentPage - 1 end
            if targetFade == -1 then currentPage = currentPage + 1 end
            fadeProgress = 0
        end
    end

    -- Рендеринг с эффектом
    if fadeProgress > 0 then
        -- Листаем назад (предыдущая страница проявляется)
        renderPageFade(currentPage, 1 - fadeProgress)
        renderPageFade(currentPage - 1, fadeProgress)
    elseif fadeProgress < 0 then
        -- Листаем вперед (следующая страница проявляется)
        renderPageFade(currentPage, 1 + fadeProgress)
        renderPageFade(currentPage + 1, -fadeProgress)
    else
        -- Просто текущая страница
        renderPageFade(currentPage, 1.0)
    end
end
local function drawBrowser()
    ui.rect(0, 0, W, H, 0)
    ui.text(20, 15, "FILES (" .. currentSource .. ")", 2, 0xFFFF)
   
    if ui.button(W - 100, 10, 90, 35, "SOURCE", 0x421F) then
        currentSource = (currentSource == "sd") and "internal" or "sd"
        refreshFiles()
    end
    local bScroll = 0
    bScroll = ui.beginList(0, 60, W, H - 60, bScroll, #fileList * 55)
    for i, f in ipairs(fileList) do
        if ui.button(10, (i-1)*55, W-20, 45, f, 0x2104) then
            fileName = f
            loadFile("/" .. f)
        end
    end
    ui.endList()
end
function draw()
    if mode == "browser" then drawBrowser() else drawReader() end
    ui.flush()
end
-- Старт
refreshFiles()
