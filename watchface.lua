-- Константы
local W, H = 410, 502
local HEADER_H = 60
local MARGIN_X = 15
local LINE_HEIGHT = 32
local TEXT_SIZE = 2
local CHARS_LIMIT = 28 -- Максимальное кол-во СИМВОЛОВ (не байт) в строке

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
local scrollY = pageH 

-- Функция для корректной работы с UTF-8 (подсчет символов и подстроки)
local function utf8_len(s)
    local _, count = string.gsub(s, "[^\128-\193]", "")
    return count
end

-- Умный перенос текста по словам
local function wrapText(text)
    local res = {}
    for paragraph in (text .. "\n"):gmatch("(.-)\r?\n") do
        if paragraph == "" then 
            table.insert(res, "") 
        else
            local line = ""
            local lineLen = 0
            for word in paragraph:gmatch("%S+") do
                local wLen = utf8_len(word)
                if lineLen + wLen + 1 <= CHARS_LIMIT then
                    line = line .. (line == "" and "" or " ") .. word
                    lineLen = lineLen + wLen + (line == "" and 0 or 1)
                else
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

-- Загрузка файла
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
    end
end

-- Отрисовка страницы
local function renderPage(pIdx, baseY)
    if pIdx < 0 or pIdx >= totalPages then
        local msg = (pIdx < 0) and "--- НАЧАЛО ФАЙЛА ---" or "--- КОНЕЦ ФАЙЛА ---"
        ui.text(W/2 - 100, baseY + visibleH/2, msg, 2, 0x8410)
        return
    end

    local start = pIdx * linesPerPage + 1
    local stop = math.min(start + linesPerPage - 1, #lines)
    for i = start, stop do
        ui.text(MARGIN_X, baseY + 15 + (i - start) * LINE_HEIGHT, lines[i], TEXT_SIZE, 0xFFFF)
    end
end

-- РИДЕР
local function drawReader()
    ui.rect(0, 0, W, H, 0)
    
    -- Инфо-панель
    ui.text(10, 15, (currentPage + 1) .. " / " .. totalPages, 2, 0x07E0)
    if ui.button(W - 80, 10, 70, 40, "EXIT", 0xF800) then mode = "browser" end

    -- Список (3 страницы)
    ui.setListInertia(false)
    local updatedScroll = ui.beginList(0, HEADER_H, W, visibleH, scrollY, contentH)
        renderPage(currentPage - 1, 0)
        renderPage(currentPage, pageH)
        renderPage(currentPage + 1, pageH * 2)
    ui.endList()

    local touch = ui.getTouch()
    
    if touch.touching then
        -- Ограничители, чтобы не листать в пустоту на первой и последней странице
        if currentPage == 0 and updatedScroll < pageH then
            scrollY = pageH -- Блокируем скролл вверх на 1-й странице
        elseif currentPage == totalPages - 1 and updatedScroll > pageH then
            scrollY = pageH -- Блокируем скролл вниз на последней
        else
            scrollY = updatedScroll
        end
    else
        -- Логика переключения
        local diff = scrollY - pageH
        local threshold = pageH * 0.3 -- 30% экрана для листания

        if diff < -threshold and currentPage > 0 then
            currentPage = currentPage - 1
            scrollY = pageH -- Мгновенная подмена
        elseif diff > threshold and currentPage < totalPages - 1 then
            currentPage = currentPage + 1
            scrollY = pageH -- Мгновенная подмена
        else
            -- ПЛАВНАЯ ДОВОДКА (Анимация)
            if math.abs(diff) > 2 then
                scrollY = scrollY - (diff * 0.15) -- Коэффициент 0.15 для плавности
            else
                scrollY = pageH
            end
        end
    end
end

-- БРАУЗЕР
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

-- Инициализация
refreshFiles()
