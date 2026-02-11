-- Константы
local PAGE_H = 375
local TOTAL_V_H = PAGE_H * 3
local CENTER_Y = PAGE_H

-- Состояние ридера
local fileLines = {}
local pageOffsets = {1} -- Индексы строк, с которых начинаются страницы
local currentPageIdx = 1 -- Индекс в массиве pageOffsets
local scrollY = CENTER_Y
local mode = "browser"
local storage = "sd"

-- Функция разбивки текста на строки (простая версия)
function loadFile(path, source)
    local content = (source == "sd") and sd.readBytes(path) or fs.readBytes(path)
    if content then
        fileLines = {}
        for line in content:gmatch("([^\n]*)\n?") do
            table.insert(fileLines, line)
        end
        pageOffsets = {1}
        currentPageIdx = 1
        scrollY = CENTER_Y
        ui.setListInertia(false) -- Отключаем инерцию для ридера
        mode = "reader"
    end
end

-- Отрисовка страницы и возврат индекса следующей строки
function drawPage(startY, startLineIdx)
    if startLineIdx > #fileLines then return nil end
    
    local y = startY
    local curr = startLineIdx
    while y < startY + PAGE_H and curr <= #fileLines do
        ui.text(10, y + 5, fileLines[curr], 2, 0xFFFF)
        y = y + 25 -- Высота строки
        curr = curr + 1
    end
    return curr -- Индекс первой строки СЛЕДУЮЩЕЙ страницы
end

function draw()
    ui.rect(0, 0, 410, 502, 0x0000)

    if mode == "browser" then
        ui.text(10, 20, "Select File (" .. storage .. ")", 2, 0x07E0)
        if ui.button(300, 15, 100, 35, "Switch", 0x4444) then
            storage = (storage == "sd") and "fs" or "sd"
        end

        local files = (storage == "sd") and sd.list("/") or fs.list("/")
        local _s = 0
        _s = ui.beginList(5, 65, 400, 375, _s, #files * 50)
        for i, f in ipairs(files) do
            if ui.button(0, (i-1)*50, 380, 45, f, 0x2104) then
                loadFile("/" .. f, storage)
            end
        end
        ui.endList()

    elseif mode == "reader" then
        -- Панель управления
        if ui.button(5, 10, 80, 40, "Exit", 0x8000) then mode = "browser" end
        ui.text(100, 20, "Page: " .. currentPageIdx, 2, 0xFFFF)

        -- Работа со списком
        -- Важно: мы управляем scrollY сами
        local newY = ui.beginList(5, 65, 400, 375, scrollY, TOTAL_V_H)
        
        -- 1. Отрисовка ТЕКУЩЕЙ страницы (в центре)
        local nextStart = drawPage(PAGE_H, pageOffsets[currentPageIdx])
        
        -- 2. Отрисовка ПРЕДЫДУЩЕЙ страницы (сверху)
        if currentPageIdx > 1 then
            drawPage(0, pageOffsets[currentPageIdx - 1])
        end
        
        -- 3. Отрисовка СЛЕДУЮЩЕЙ страницы (снизу)
        if nextStart and nextStart <= #fileLines then
            drawPage(PAGE_H * 2, nextStart)
            -- Сохраняем "закладку" для следующей страницы, если ее еще нет
            if not pageOffsets[currentPageIdx + 1] then
                pageOffsets[currentPageIdx + 1] = nextStart
            end
        end

        ui.endList()

        -- Логика перелистывания (ручное управление)
        local touch = ui.getTouch()
        
        if touch.touching then
            -- Пока ведем пальцем — обновляем scrollY напрямую
            scrollY = newY
        else
            -- Палец отпущен — проверяем, куда довести
            local diff = newY - CENTER_Y
            
            if diff < -50 and pageOffsets[currentPageIdx + 1] then
                -- Листаем ВПЕРЕД
                currentPageIdx = currentPageIdx + 1
                scrollY = CENTER_Y -- Мгновенный сброс в центр
            elseif diff > 50 and currentPageIdx > 1 then
                -- Листаем НАЗАД
                currentPageIdx = currentPageIdx - 1
                scrollY = CENTER_Y -- Мгновенный сброс в центр
            else
                -- Возврат в центр (плавная доводка)
                if math.abs(diff) > 1 then
                    scrollY = scrollY + (CENTER_Y - scrollY) * 0.3
                else
                    scrollY = CENTER_Y
                end
            end
        end
    end
    ui.flush()
end
