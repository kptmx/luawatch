-- Читалка текстовых файлов с выбором из SD / Flash
-- 2025-2026 версия для LuaWatch

-- Константы
local SCR_W, SCR_H = 410, 502
local TEXT_SIZE    = 2
local CHAR_W       = 16
local LINE_H       = 20
local MARGIN_X     = 12
local MARGIN_Y     = 45
local LINES_PER_PAGE = math.floor((SCR_H - MARGIN_Y - 60) / LINE_H)  -- ~20-21 строк
local STATUS_H     = 35
local FADE_STEPS   = 8
local FADE_DELAY   = 25   -- мс

-- Цвета
local BG       = 0x0000
local TEXT     = 0xFFFF
local GRAY     = 0x8410
local ACCENT   = 0x07E0   -- зелёный
local WARN     = 0xF800
local SELECTED = 0xFFE0   -- жёлто-зелёный для выделения
local TAB_ACTIVE   = 0x07E0
local TAB_INACTIVE = 0x4208

-- Состояние
local mode = "browser"          -- "browser" или "reader"
local current_tab = "SD"        -- "SD" или "Flash"
local current_dir_sd    = "/sdcard/books"
local current_dir_flash = "/books"
local files_sd    = {}
local files_flash = {}
local selected_file = nil
local full_text = ""
local pages = {}
local current_page = 1
local total_pages = 0
local error_msg = ""
local touch_start_x, touch_start_y = -1, -1
local is_swiping = false

-- ────────────────────────────────────────────────
-- Вспомогательные функции
-- ────────────────────────────────────────────────

function darken(c, f)
    local r = bit.band(bit.rshift(c,11),31)
    local g = bit.band(bit.rshift(c,5), 63)
    local b = bit.band(c,31)
    return bit.bor(bit.lshift(math.floor(r*f/255),11),
                   bit.lshift(math.floor(g*f/255),5),
                   math.floor(b*f/255))
end

function wrap_line(line)
    local words = {}
    for w in string.gmatch(line, "%S+") do table.insert(words, w) end
    
    local lines = {}
    local cur = ""
    for _, w in ipairs(words) do
        local test = cur .. (cur == "" and "" or " ") .. w
        if #test * CHAR_W <= SCR_W - 2*MARGIN_X then
            cur = test
        else
            if cur ~= "" then table.insert(lines, cur) end
            cur = w
        end
    end
    if cur ~= "" then table.insert(lines, cur) end
    return lines
end

function paginate()
    pages = {}
    local all_lines = {}
    
    -- Разбиваем на параграфы и оборачиваем
    for para in string.gmatch(full_text, "([^\n]*)\n?") do
        local wrapped = wrap_line(para)
        for _, ln in ipairs(wrapped) do table.insert(all_lines, ln) end
        table.insert(all_lines, "")   -- пустая строка между параграфами
    end
    
    local page = {}
    for _, line in ipairs(all_lines) do
        table.insert(page, line)
        if #page >= LINES_PER_PAGE then
            table.insert(pages, page)
            page = {}
        end
    end
    if #page > 0 then table.insert(pages, page) end
    
    total_pages = #pages
end

-- ────────────────────────────────────────────────
-- Загрузка списков файлов
-- ────────────────────────────────────────────────
function load_files(tab)
    local dir = (tab == "SD") and current_dir_sd or current_dir_flash
    local fs = (tab == "SD") and sd or fs
    
    local res = fs.list(dir)
    local list = (tab == "SD") and files_sd or files_flash
    
    list = {}
    
    if not res.ok then
        error_msg = "Не открыта папка: " .. dir
        return
    end
    
    for _, name in ipairs(res) do
        if name:match("%.txt$") or name:match("%.TXT$") then
            table.insert(list, {name = name, path = dir .. "/" .. name})
        end
    end
    
    if tab == "SD" then files_sd = list else files_flash = list end
end

-- ────────────────────────────────────────────────
-- Отрисовка вкладок и списка файлов
-- ────────────────────────────────────────────────
function draw_browser()
    ui.rect(0, 0, SCR_W, SCR_H, BG)
    
    -- Вкладки
    local tab_w = SCR_W / 2
    ui.fillRoundRect(0, 0, tab_w, 38, 8, current_tab=="SD" and TAB_ACTIVE or TAB_INACTIVE)
    ui.fillRoundRect(tab_w, 0, tab_w, 38, 8, current_tab=="Flash" and TAB_ACTIVE or TAB_INACTIVE)
    
    ui.text(tab_w/2 - 30, 12, "SD-карта", 2, current_tab=="SD" and 0 or GRAY)
    ui.text(tab_w + tab_w/2 - 40, 12, "Flash", 2, current_tab=="Flash" and 0 or GRAY)
    
    -- Текущая папка
    local cur_dir = (current_tab == "SD") and current_dir_sd or current_dir_flash
    ui.text(MARGIN_X, 45, cur_dir, 1, GRAY)
    
    -- Список файлов
    local files = (current_tab == "SD") and files_sd or files_flash
    local start_y = 80
    local item_h = 42
    
    for i, f in ipairs(files) do
        local y = start_y + (i-1)*item_h
        if y + item_h > SCR_H - 60 then break end
        
        local selected = (selected_file == f.path)
        local col = selected and SELECTED or TEXT
        
        if ui.button(MARGIN_X, y, SCR_W - 2*MARGIN_X, item_h-6, f.name, col) then
            selected_file = f.path
            mode = "reader"
            
            local content = (current_tab == "SD") and sd.readBytes(f.path) or fs.readBytes(f.path)
            if content and #content > 0 then
                full_text = content
                full_text = string.gsub(full_text, "\r\n", "\n")
                paginate()
                current_page = 1
                error_msg = (total_pages == 0) and "Файл пустой" or ""
            else
                error_msg = "Не удалось прочитать файл"
            end
        end
    end
    
    -- Кнопки управления
    if ui.button(20, SCR_H-55, 120, 40, "Обновить", ACCENT) then
        load_files(current_tab)
    end
    
    if ui.button(SCR_W-140, SCR_H-55, 120, 40, "Назад", WARN) then
        -- можно добавить выход в меню или просто ничего не делать
    end
end

-- ────────────────────────────────────────────────
-- Отрисовка страницы книги
-- ────────────────────────────────────────────────
function draw_page(fade)
    fade = fade or 255
    local col = darken(TEXT, fade)
    
    ui.rect(0, 0, SCR_W, SCR_H, BG)
    
    -- статус
    local t = hw.getTime()
    local b = hw.getBatt()
    local prog = total_pages > 0 and math.floor(current_page / total_pages * 100) or 0
    local status = string.format("%02d:%02d  %d%%  %d / %d  (%d%%)", 
                                 t.h, t.m, b, current_page, total_pages, prog)
    ui.text(MARGIN_X, 8, status, 1, GRAY)
    
    -- прогресс-бар
    local pw = math.floor((SCR_W - 2*MARGIN_X) * (current_page / total_pages))
    ui.rect(MARGIN_X, 32, SCR_W-2*MARGIN_X, 4, 0x4208)
    ui.rect(MARGIN_X, 32, pw, 4, ACCENT)
    
    -- текст
    local page = pages[current_page] or {}
    for i, line in ipairs(page) do
        ui.text(MARGIN_X, MARGIN_Y + (i-1)*LINE_H, line, TEXT_SIZE, col)
    end
    
    -- кнопки
    if ui.button(20, SCR_H-55, 170, 40, "Предыдущая", ACCENT) then
        if current_page > 1 then current_page = current_page - 1 end
    end
    if ui.button(SCR_W-190, SCR_H-55, 170, 40, "Следующая", ACCENT) then
        if current_page < total_pages then current_page = current_page + 1 end
    end
end

-- ────────────────────────────────────────────────
-- Плавное перелистывание
-- ────────────────────────────────────────────────
function flip_page(new_page)
    if new_page < 1 or new_page > total_pages then return end
    
    -- fade out
    for i = FADE_STEPS, 1, -1 do
        local f = math.floor(255 * i / FADE_STEPS)
        draw_page(f)
        ui.flush()
        local st = hw.millis()
        while hw.millis() - st < FADE_DELAY do end
    end
    
    current_page = new_page
    
    -- fade in
    for i = 1, FADE_STEPS do
        local f = math.floor(255 * i / FADE_STEPS)
        draw_page(f)
        ui.flush()
        local st = hw.millis()
        while hw.millis() - st < FADE_DELAY do end
    end
end

-- ────────────────────────────────────────────────
-- Обработка свайпа
-- ────────────────────────────────────────────────
function handle_swipe()
    local t = ui.getTouch()
    if t.touching then
        if not is_swiping then
            touch_start_x = t.x
            touch_start_y = t.y
            is_swiping = true
        end
    else
        if is_swiping then
            local dx = t.x - touch_start_x
            if math.abs(dx) > 90 and math.abs(t.y - touch_start_y) < 60 then
                if dx < 0 then
                    if current_page < total_pages then flip_page(current_page + 1) end
                else
                    if current_page > 1 then flip_page(current_page - 1) end
                end
            end
            is_swiping = false
        end
    end
end

-- ────────────────────────────────────────────────
-- Главный draw
-- ────────────────────────────────────────────────
function draw()
    if mode == "browser" then
        draw_browser()
    else
        if error_msg ~= "" then
            ui.rect(0, 0, SCR_W, SCR_H, BG)
            ui.text(40, SCR_H/2 - 30, error_msg, 2, WARN)
        else
            handle_swipe()
            draw_page()
        end
    end
    
    -- Переключение вкладок по нажатию (верхняя полоса)
    local touch = ui.getTouch()
    if touch.pressed then
        if touch.y < 38 then
            if touch.x < SCR_W/2 then
                current_tab = "SD"
            else
                current_tab = "Flash"
            end
            load_files(current_tab)
        end
    end
    
    ui.flush()
end

-- ────────────────────────────────────────────────
-- Инициализация
-- ────────────────────────────────────────────────
if sd_ok then
    load_files("SD")
else
    current_tab = "Flash"
end
load_files("Flash")

if #files_sd == 0 and #files_flash == 0 then
    error_msg = "Нет .txt файлов"
end
