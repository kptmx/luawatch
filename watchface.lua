-- === [КОНСТАНТЫ И НАСТРОЙКИ] ===
local W, H = 410, 502
local HEADER_H = 50
local MARGIN_X = 20
local LINE_HEIGHT = 30
local TEXT_SIZE = 2
local CHARS_LIMIT = 28
local visibleH = H - HEADER_H
local linesPerPage = math.floor((visibleH - 20) / LINE_HEIGHT)

-- Состояние
local mode = "browser"
local lines = {}
local currentPage = 0
local totalPages = 0
local fadeProgress = 0.0 -- 0: текущая, 1: переход назад, -1: переход вперед
local lastTouchY = nil

-- === [СЕРВИСНЫЕ ФУНКЦИИ] ===

-- Функция смешивания цвета с черным (Fade)
local function getColor(opacity)
    if opacity <= 0 then return 0x0000 end
    if opacity >= 1 then return 0xFFFF end
    local val = math.floor(31 * opacity) -- Для 5-бит R и B
    local valG = math.floor(63 * opacity) -- Для 6-бит G
    return (val << 11) | (valG << 5) | val
end

-- Отрисовка конкретной страницы с заданной прозрачностью
local function drawPage(pIdx, opacity)
    if pIdx < 0 or pIdx >= totalPages or opacity <= 0.05 then return end
    
    local color = getColor(opacity)
    local startLine = pIdx * linesPerPage + 1
    local endLine = math.min(startLine + linesPerPage - 1, #lines)
    
    for i = startLine, endLine do
        local y = HEADER_H + 15 + (i - startLine) * LINE_HEIGHT
        ui.text(MARGIN_X, y, lines[i], TEXT_SIZE, color)
    end
end

-- === [ОСНОВНОЙ ЦИКЛ РИДЕРА] ===

local function drawReader()
    -- 1. Очистка фона (обязательно, чтобы текст не накладывался)
    ui.rect(0, 0, W, H, 0x0000)
    
    -- 2. Обработка ввода и анимации
    local touch = ui.getTouch()
    
    if touch.touching then
        if not lastTouchY then lastTouchY = touch.y end
        local delta = touch.y - lastTouchY
        
        -- Вычисляем прогресс свайпа (-1.0 до 1.0)
        fadeProgress = delta / (visibleH * 0.6)
        
        -- Ограничители (чтобы не листать за пределы файла)
        if currentPage <= 0 and fadeProgress > 0 then fadeProgress = 0 end
        if currentPage >= totalPages - 1 and fadeProgress < 0 then fadeProgress = 0 end
    else
        lastTouchY = nil
        -- Если палец отпущен, доводим анимацию до конца или возвращаем
        if math.abs(fadeProgress) > 0.25 then
            local target = (fadeProgress > 0) and 1.0 or -1.0
            fadeProgress = fadeProgress + (target - fadeProgress) * 0.3
            
            -- Если почти довели, переключаем страницу
            if math.abs(fadeProgress) > 0.95 then
                if fadeProgress > 0 then currentPage = currentPage - 1 else currentPage = currentPage + 1 end
                fadeProgress = 0
            end
        else
            -- Возврат к текущей странице
            fadeProgress = fadeProgress * 0.7
            if math.abs(fadeProgress) < 0.01 then fadeProgress = 0 end
        end
    end

    -- 3. Отрисовка страниц (Слои)
    if fadeProgress > 0 then
        -- Тянем вниз (проявляется предыдущая)
        drawPage(currentPage, 1.0 - fadeProgress)
        drawPage(currentPage - 1, fadeProgress)
    elseif fadeProgress < 0 then
        -- Тянем вверх (проявляется следующая)
        drawPage(currentPage, 1.0 + fadeProgress)
        drawPage(currentPage + 1, -fadeProgress)
    else
        -- Статичное состояние
        drawPage(currentPage, 1.0)
    end

    -- 4. Шапка (рисуется поверх, чтобы текст под нее "уходил")
    ui.fillRoundRect(0, 0, W, HEADER_H - 5, 0, 0x10A2)
    ui.text(15, 12, string.format("Стр %d / %d", currentPage + 1, totalPages), 2, 0xFFFF)
    
    if ui.button(W - 90, 5, 80, 35, "ВЫХОД", 0xF800) then 
        mode = "browser" 
    end
end

-- === [ЛОГИКА БРАУЗЕРА] ===

local function drawBrowser()
    ui.rect(0, 0, W, H, 0)
    ui.text(20, 15, "ФАЙЛЫ: " .. currentSource:upper(), 2, 0xFFFF)
    
    if ui.button(W - 120, 10, 110, 35, "ПАМЯТЬ", 0x421F) then
        currentSource = (currentSource == "sd") and "internal" or "sd"
        refreshFiles()
    end

    -- Обычный список файлов
    local bScroll = 0
    bScroll = ui.beginList(0, 60, W, H - 60, bScroll, #fileList * 60)
    for i, f in ipairs(fileList) do
        if ui.button(10, (i-1)*60, W-20, 50, f, 0x2104) then
            if loadFile("/" .. f) then
                mode = "reader"
            end
        end
    end
    ui.endList()
end

-- Главная функция отрисовки
function draw()
    if mode == "browser" then
        drawBrowser()
    else
        drawReader()
    end
    ui.flush()
end

-- Старт
refreshFiles()
