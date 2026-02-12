-- Константы оформления
local W, H = 410, 502
local HEADER_H = 60
local MARGIN_X = 20
local LINE_HEIGHT = 32
local TEXT_SIZE = 2

-- Расчетные параметры
local visibleH = H - HEADER_H
local pageH = visibleH
local contentH = pageH * 3
local linesPerPage = math.floor((visibleH - 20) / LINE_HEIGHT)

-- Состояние
local mode = "browser"
local currentSource = "sd"
local fileList = {}
local fileName = ""
local lines = {}
local totalPages = 0
local currentPage = 0
local scrollY = pageH -- Начальная позиция (центр списка)

-- Загрузка списка файлов
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

-- Загрузка контента
local function loadFile(path)
    local data = (currentSource == "sd") and sd.readBytes(path) or fs.readBytes(path)
    if type(data) ~= "string" then return false end
    
    lines = {}
    for line in (data .. "\n"):gmatch("(.-)\r?\n") do
        table.insert(lines, line)
    end
    
    totalPages = math.max(1, math.ceil(#lines / linesPerPage))
    currentPage = 0
    scrollY = pageH
    mode = "reader"
    return true
end

-- Отрисовка одной страницы
local function renderPage(pIdx, baseY)
    if pIdx < 0 or pIdx >= totalPages then
        local msg = (pIdx < 0) and "--- НАЧАЛО ---" or "--- КОНЕЦ ---"
        ui.text(W/2 - 60, baseY + visibleH/2, msg, 2, 0x421F)
        return
    end

    local start = pIdx * linesPerPage + 1
    local stop = math.min(start + linesPerPage - 1, #lines)
    for i = start, stop do
        ui.text(MARGIN_X, baseY + 10 + (i - start) * LINE_HEIGHT, lines[i], TEXT_SIZE, 0xFFFF)
    end
end

-- Основной цикл ридера
local function drawReader()
    ui.rect(0, 0, W, H, 0)
    
    -- Шапка
    ui.text(10, 15, fileName, 2, 0x07E0)
    ui.text(W - 120, 15, (currentPage + 1) .. "/" .. totalPages, 2, 0xFFFF)
    if ui.button(10, H - 50, 80, 40, "BACK", 0xF800) then mode = "browser" end

    -- Работа со списком
    ui.setListInertia(false) -- Выключаем системную инерцию для четкого контроля snap-логики
    local newScroll = ui.beginList(0, HEADER_H, W, visibleH, scrollY, contentH)
        renderPage(currentPage - 1, 0)         -- Секция 1
        renderPage(currentPage, pageH)         -- Секция 2 (Текущая)
        renderPage(currentPage + 1, pageH * 2) -- Секция 3
    ui.endList()

    local touch = ui.getTouch()
    
    if touch.touching then
        scrollY = newScroll
    else
        -- Логика перелистывания (порог 25% высоты экрана)
        local diff = newScroll - pageH
        local threshold = pageH * 0.25

        if diff < -threshold and currentPage > 0 then
            currentPage = currentPage - 1
            scrollY = pageH -- Мгновенный прыжок (визуально незаметно)
        elseif diff > threshold and currentPage < totalPages - 1 then
            currentPage = currentPage + 1
            scrollY = pageH -- Мгновенный прыжок
        else
            -- Плавная доводка к центру (Lerp)
            if math.abs(diff) > 1 then
                scrollY = newScroll + (pageH - newScroll) * 0.2
            else
                scrollY = pageH
            end
        end
    end
end

-- Файловый браузер
local function drawBrowser()
    ui.rect(0, 0, W, H, 0)
    ui.text(20, 15, "BROWSER: " .. currentSource:upper(), 2, 0xFFFF)
    
    if ui.button(W - 100, 10, 80, 35, "SRC", 0x421F) then
        currentSource = (currentSource == "sd") and "internal" or "sd"
        refreshFiles()
    end

    local bScroll = 0
    bScroll = ui.beginList(0, 60, W, H - 60, bScroll, #fileList * 50)
    for i, f in ipairs(fileList) do
        if ui.button(10, (i-1)*50, W-20, 45, f, 0x2104) then
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
