-- Настройки экрана
local SCR_W, SCR_H = 410, 502
local LIST_Y, LIST_H = 65, 375
local PAGE_H = LIST_H
local TOTAL_VIRTUAL_H = PAGE_H * 3

-- Состояние приложения
local state = "browser" -- "browser" или "reader"
local storage = "fs"    -- "fs" или "sd"
local files = {}
local current_file = ""

-- Состояние читалки
local scroll_y = PAGE_H -- Начинаем с центра (вторая страница)
local file_offset = 0   -- Базовое смещение в файле для "верхней" страницы
local pages = {"", "", ""} -- Буфер текста (Prev, Curr, Next)
local char_per_page = 600 -- Примерное кол-во символов на страницу (подбери под шрифт)

function load_pages(start_offset)
    for i = 1, 3 do
        local offset = start_offset + (i - 1) * char_per_page
        if offset < 0 then
            pages[i] = "--- Начало файла ---"
        else
            local content = ""
            if storage == "fs" then
                -- В твоем API fs.readBytes/load читает весь файл. 
                -- Для больших файлов лучше использовать частичное чтение, 
                -- но пока используем упрощенную эмуляцию из того что есть:
                local full = fs.load(current_file) or ""
                pages[i] = full:sub(offset + 1, offset + char_per_page)
            else
                local res = sd.readBytes(current_file)
                local full = (type(res) == "table" and res.ok) and res.body or ""
                pages[i] = full:sub(offset + 1, offset + char_per_page)
            end
        end
    end
end

function draw_browser()
    ui.text(20, 10, "File Browser: " .. storage:upper(), 2, 0x07E0)
    
    if ui.button(300, 5, 100, 40, storage == "fs" and "to SD" or "to Flash", 0x3186) then
        storage = (storage == "fs") and "sd" or "fs"
        files = _G[storage].list("/") or {}
    end

    local list_scroll = 0
    list_scroll = ui.beginList(5, 60, 400, 400, list_scroll, #files * 50)
    for i, f in ipairs(files) do
        if ui.button(10, (i-1)*50, 380, 45, f, 0x2104) then
            current_file = "/" .. f
            file_offset = 0
            load_pages(0)
            scroll_y = PAGE_H
            state = "reader"
        end
    end
    ui.endList()
end

function draw_reader()
    ui.text(10, 10, "File: " .. current_file, 1, 0xFFFF)
    if ui.button(340, 5, 60, 40, "Back", 0xF800) then state = "browser" end

    -- Виртуальный скролл (высота контента = PAGE_H * 3)
    local new_scroll = ui.beginList(5, LIST_Y, 400, LIST_H, scroll_y, TOTAL_VIRTUAL_H)
    
    -- Отрисовка трех страниц
    for i = 1, 3 do
        ui.text(10, (i-1) * PAGE_H + 5, pages[i], 1, 0xFFFF)
        -- Разделитель страниц
        ui.rect(5, i * PAGE_H - 1, 390, 1, 0x4444)
    end
    ui.endList()

    local touch = ui.getTouch()

    -- Логика переключения страниц (когда палец отпущен)
    if not touch.touching and scroll_y ~= new_scroll then
        if new_scroll < PAGE_H * 0.5 then
            -- Перелистнули вверх (на предыдущую)
            file_offset = math.max(0, file_offset - char_per_page)
            load_pages(file_offset)
            scroll_y = PAGE_H -- Возвращаем в центр
        elseif new_scroll > PAGE_H * 1.5 then
            -- Перелистнули вниз (на следующую)
            file_offset = file_offset + char_per_page
            load_pages(file_offset)
            scroll_y = PAGE_H -- Возвращаем в центр
        else
            -- Доводчик (Snap to center)
            scroll_y = PAGE_H
        end
    else
        scroll_y = new_scroll
    end
end

-- Инициализация списка файлов
files = fs.list("/") or {}

function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000) -- Clear screen
    if state == "browser" then
        draw_browser()
    else
        draw_reader()
    end
end
