-- Читалка текстовых файлов для LuaWatch
-- Поддержка: word wrap, анимация fade страниц, HUD (время, батарея, прогресс), выбор файлов из fs/sd
-- Исправление: правильная обработка возвращаемого значения от readBytes (string если ok, table если error)

-- Константы экрана и шрифта
local SCR_W, SCR_H = 410, 502
local FONT_SIZE = 1  -- Размер шрифта (1 для unifont ~16px высота)
local CHAR_W = 8     -- Примерная ширина символа (под unifont, скорректируйте по тесту)
local LINE_H = 16    -- Высота строки (с пробелом)
local MAX_CHARS_PER_LINE = math.floor((SCR_W - 20) / CHAR_W)  -- ~50 символов, с отступами
local TOP_H = 30     -- Верхняя панель
local BOT_H = 30     -- Нижняя панель
local TEXT_H = SCR_H - TOP_H - BOT_H
local LINES_PER_PAGE = math.floor(TEXT_H / LINE_H)  -- ~28 строк

-- Цвета (RGB565)
local COL_BG = 0xFFFF      -- Белый
local COL_TEXT = 0x0000    -- Черный
local COL_ACCENT = 0xF800  -- Красный
local COL_GRAY = 0x8410    -- Серый
local COL_PANEL = 0xCE59   -- Светло-серый

-- Состояние приложения
local mode = 'menu'        -- 'menu' или 'reader'
local files = {}           -- Список файлов {path, source} -- path="/file.txt", source="fs" или "sd"
local selected_file = nil
local content = nil        -- Полный текст файла
local lines = {}           -- Массив завернутых строк
local current_page = 1
local total_pages = 1
local anim_state = nil     -- nil, 'fade_out', 'fade_in'
local anim_start = 0
local anim_dur = 500       -- Длительность анимации в мс
local next_page = nil      -- Для анимации, направление (1 или -1)
local touch = {x=0, y=0, touching=false}
local drag_start_x = 0
local drag_start_y = 0
local is_dragging = false
local swipe_threshold = 100
local menu_scroll_y = 0    -- Сохраняем скролл меню
local error_msg = ""       -- Для отображения ошибок

-- Вспомогательные функции
function rgb565(r, g, b) return (r << 11) | (g << 5) | b end

function lerp(a, b, t) return a + (b - a) * t end

function darken_color(col, factor)
    -- Разбор RGB565
    local r = bit.rshift(col, 11) % 32
    local g = bit.rshift(col, 5) % 64
    local b = col % 32
    -- Затемнение
    r = math.floor(r * factor)
    g = math.floor(g * factor)
    b = math.floor(b * factor)
    -- Сборка
    return rgb565(r, g, b)
end

-- Word wrap: Разбивает текст на строки без разрыва слов
function wrap_text(text)
    local wrapped = {}
    for para in (text .. "\n"):gmatch("(.-)\n") do  -- По параграфам
        local words = {}
        for word in para:gmatch("%S+") do table.insert(words, word) end
        local line = ""
        for _, word in ipairs(words) do
            local test = (line == "" and "" or line .. " ") .. word
            if #test > MAX_CHARS_PER_LINE then
                table.insert(wrapped, line)
                line = word
            else
                line = test
            end
        end
        if line ~= "" then table.insert(wrapped, line) end
        table.insert(wrapped, "")  -- Пустая строка для абзаца
    end
    return wrapped
end

-- Загрузка файла
function load_file(path, source)
    local read_func = (source == "sd" and sd.readBytes or fs.readBytes)
    local res = read_func(path)
    if type(res) == "string" then
        return res
    elseif type(res) == "table" then
        if res.ok then
            return res[1]  -- На случай, если ok но table (хотя по C++ нет)
        else
            return nil, res.err or "unknown error"
        end
    else
        return nil, "invalid response type"
    end
end

-- Сбор списка файлов .txt из fs и sd
function load_files()
    files = {}
    -- Internal (fs)
    local fs_list = fs.list("/")
    if type(fs_list) == "table" then
        for _, f in ipairs(fs_list) do
            if f:match("%.txt$") then
                table.insert(files, {path = "/" .. f, source = "fs"})
            end
        end
    end
    -- SD
    local sd_list = sd.list("/")
    if type(sd_list) == "table" then
        for _, f in ipairs(sd_list) do
            if f:match("%.txt$") then
                table.insert(files, {path = "/" .. f, source = "sd"})
            end
        end
    end
end

-- Открытие файла для чтения
function open_file(idx)
    local f = files[idx]
    if f then
        local txt, err = load_file(f.path, f.source)
        if txt then
            content = txt
            lines = wrap_text(content)
            total_pages = math.ceil(#lines / LINES_PER_PAGE)
            current_page = 1
            mode = 'reader'
            error_msg = ""
        else
            error_msg = "Error loading: " .. (err or "unknown")
        end
    end
end

-- Рисование HUD
function draw_hud()
    -- Top: Time and Battery
    ui.rect(0, 0, SCR_W, TOP_H, COL_PANEL)
    local t = hw.getTime()
    local time_str = string.format("%02d:%02d", t.h, t.m)
    ui.text(10, 5, time_str, FONT_SIZE, COL_TEXT)
    local batt = hw.getBatt()
    ui.text(SCR_W - 60, 5, batt .. "%", FONT_SIZE, batt < 20 and COL_ACCENT or COL_TEXT)

    -- Bottom: Progress
    ui.rect(0, SCR_H - BOT_H, SCR_W, BOT_H, COL_PANEL)
    local prog_str = string.format("Page %d/%d", current_page, total_pages)
    ui.text(10, SCR_H - BOT_H + 5, prog_str, FONT_SIZE, COL_TEXT)
    local percent = math.floor((current_page / total_pages) * 100)
    ui.text(SCR_W - 60, SCR_H - BOT_H + 5, percent .. "%", FONT_SIZE, COL_TEXT)
end

-- Рисование текста страницы
function draw_page(page, text_col)
    local start_line = (page - 1) * LINES_PER_PAGE + 1
    for i = 0, LINES_PER_PAGE - 1 do
        local ln = lines[start_line + i]
        if ln then
            ui.text(10, TOP_H + i * LINE_H, ln, FONT_SIZE, text_col)
        end
    end
end

-- Основная функция draw
function draw()
    touch = ui.getTouch()
    ui.rect(0, 0, SCR_W, SCR_H, COL_BG)  -- Фон

    if mode == 'menu' then
        -- Меню выбора файлов
        ui.text(10, 10, "Text Files:", 2, COL_TEXT)
        if error_msg ~= "" then
            ui.text(10, 30, error_msg, 1, COL_ACCENT)
        end
        menu_scroll_y = ui.beginList(0, 50, SCR_W, SCR_H - 50, menu_scroll_y, #files * 40)
        for i, f in ipairs(files) do
            local y = (i - 1) * 40
            local src = (f.source == "sd" and "[SD] " or "[Int] ")
            if ui.button(10, y, SCR_W - 20, 35, src .. f.path, COL_GRAY) then
                open_file(i)
            end
        end
        ui.endList()
    elseif mode == 'reader' then
        -- Читалка
        draw_hud()

        -- Анимация
        local now = hw.millis()
        local progress = 0
        local text_col = COL_TEXT
        local draw_p = current_page

        if anim_state then
            progress = (now - anim_start) / anim_dur
            if progress > 1 then progress = 1 end

            if anim_state == 'fade_out' then
                local factor = progress
                local r1, g1, b1 = bit.rshift(COL_TEXT,11)%32, bit.rshift(COL_TEXT,5)%64, COL_TEXT%32
                local r2, g2, b2 = bit.rshift(COL_BG,11)%32, bit.rshift(COL_BG,5)%64, COL_BG%32
                local lr = math.floor(lerp(r1, r2, factor))
                local lg = math.floor(lerp(g1, g2, factor))
                local lb = math.floor(lerp(b1, b2, factor))
                text_col = rgb565(lr, lg, lb)
                if progress >= 1 then
                    current_page = current_page + next_page
                    anim_state = 'fade_in'
                    anim_start = now
                end
            elseif anim_state == 'fade_in' then
                local factor = 1 - progress
                local r1, g1, b1 = bit.rshift(COL_TEXT,11)%32, bit.rshift(COL_TEXT,5)%64, COL_TEXT%32
                local r2, g2, b2 = bit.rshift(COL_BG,11)%32, bit.rshift(COL_BG,5)%64, COL_BG%32
                local lr = math.floor(lerp(r1, r2, factor))
                local lg = math.floor(lerp(g1, g2, factor))
                local lb = math.floor(lerp(b1, b2, factor))
                text_col = rgb565(lr, lg, lb)
                if progress >= 1 then
                    anim_state = nil
                end
            end
            draw_page(draw_p, text_col)
        else
            draw_page(current_page, COL_TEXT)
            -- Обработка свайпа
            if touch.touching then
                if not is_dragging then
                    drag_start_x = touch.x
                    drag_start_y = touch.y
                    is_dragging = true
                end
            else
                if is_dragging then
                    local dx = drag_start_x - touch.x  -- Положительный для свайпа влево (next)
                    if math.abs(dx) > swipe_threshold then
                        if dx > 0 and current_page < total_pages then
                            next_page = 1
                            draw_p = current_page
                            anim_state = 'fade_out'
                            anim_start = hw.millis()
                        elseif dx < 0 and current_page > 1 then
                            next_page = -1
                            draw_p = current_page
                            anim_state = 'fade_out'
                            anim_start = hw.millis()
                        end
                    end
                    is_dragging = false
                end
            end
        end
    end

    ui.flush()
end

-- Инициализация
load_files()
ui.setListInertia(true)  -- Включаем инерцию для списка файлов-- Читалка текстовых файлов для LuaWatch
-- Поддержка: word wrap, анимация fade страниц, HUD (время, батарея, прогресс), выбор файлов из fs/sd

-- Константы экрана и шрифта
local SCR_W, SCR_H = 410, 502
local FONT_SIZE = 1  -- Размер шрифта (1 для unifont ~16px высота)
local CHAR_W = 8     -- Примерная ширина символа (под unifont, скорректируйте по тесту)
local LINE_H = 16    -- Высота строки (с пробелом)
local MAX_CHARS_PER_LINE = math.floor((SCR_W - 20) / CHAR_W)  -- ~50 символов, с отступами
local TOP_H = 30     -- Верхняя панель
local BOT_H = 30     -- Нижняя панель
local TEXT_H = SCR_H - TOP_H - BOT_H
local LINES_PER_PAGE = math.floor(TEXT_H / LINE_H)  -- ~28 строк

-- Цвета (RGB565)
local COL_BG = 0xFFFF      -- Белый
local COL_TEXT = 0x0000    -- Черный
local COL_ACCENT = 0xF800  -- Красный
local COL_GRAY = 0x8410    -- Серый
local COL_PANEL = 0xCE59   -- Светло-серый

-- Состояние приложения
local mode = 'menu'        -- 'menu' или 'reader'
local files = {}           -- Список файлов {path, source} -- path="/file.txt", source="fs" или "sd"
local selected_file = nil
local content = nil        -- Полный текст файла
local lines = {}           -- Массив завернутых строк
local current_page = 1
local total_pages = 1
local anim_state = nil     -- nil, 'fade_out', 'fade_in'
local anim_start = 0
local anim_dur = 500       -- Длительность анимации в мс
local next_page = nil      -- Для анимации, направление (1 или -1)
local touch = {x=0, y=0, touching=false}
local drag_start_x = 0
local drag_start_y = 0
local is_dragging = false
local swipe_threshold = 100

-- Вспомогательные функции
function rgb565(r, g, b) return (r << 11) | (g << 5) | b end

function lerp(a, b, t) return a + (b - a) * t end

function darken_color(col, factor)
    -- Разбор RGB565
    local r = bit.rshift(col, 11) % 32
    local g = bit.rshift(col, 5) % 64
    local b = col % 32
    -- Затемнение
    r = math.floor(r * factor)
    g = math.floor(g * factor)
    b = math.floor(b * factor)
    -- Сборка
    return rgb565(r, g, b)
end

-- Word wrap: Разбивает текст на строки без разрыва слов
function wrap_text(text)
    local wrapped = {}
    for para in (text .. "\n"):gmatch("(.-)\n") do  -- По параграфам
        local words = {}
        for word in para:gmatch("%S+") do table.insert(words, word) end
        local line = ""
        for _, word in ipairs(words) do
            local test = (line == "" and "" or line .. " ") .. word
            if #test > MAX_CHARS_PER_LINE then
                table.insert(wrapped, line)
                line = word
            else
                line = test
            end
        end
        if line ~= "" then table.insert(wrapped, line) end
        table.insert(wrapped, "")  -- Пустая строка для абзаца
    end
    return wrapped
end

-- Загрузка файла
function load_file(path, source)
    local res
    if source == "sd" then
        res = sd.readBytes(path)
    else
        res = fs.readBytes(path)
    end
    if res.ok then
        return res[1]  -- lstring
    else
        return nil, res.err
    end
end

-- Сбор списка файлов .txt из fs и sd
function load_files()
    files = {}
    -- Internal (fs)
    local fs_list = fs.list("/")
    if type(fs_list) == "table" then
        for _, f in ipairs(fs_list) do
            if f:match("%.txt$") then
                table.insert(files, {path = "/" .. f, source = "fs"})
            end
        end
    end
    -- SD
    local sd_list = sd.list("/")
    if type(sd_list) == "table" then
        for _, f in ipairs(sd_list) do
            if f:match("%.txt$") then
                table.insert(files, {path = "/" .. f, source = "sd"})
            end
        end
    end
end

-- Открытие файла для чтения
function open_file(idx)
    local f = files[idx]
    if f then
        local txt, err = load_file(f.path, f.source)
        if txt then
            content = txt
            lines = wrap_text(content)
            total_pages = math.ceil(#lines / LINES_PER_PAGE)
            current_page = 1
            mode = 'reader'
        else
            -- Ошибка, показать в меню
            print("Error loading: " .. (err or "unknown"))
        end
    end
end

-- Рисование HUD
function draw_hud()
    -- Top: Time and Battery
    ui.rect(0, 0, SCR_W, TOP_H, COL_PANEL)
    local t = hw.getTime()
    local time_str = string.format("%02d:%02d", t.h, t.m)
    ui.text(10, 5, time_str, FONT_SIZE, COL_TEXT)
    local batt = hw.getBatt()
    ui.text(SCR_W - 60, 5, batt .. "%", FONT_SIZE, batt < 20 and COL_ACCENT or COL_TEXT)

    -- Bottom: Progress
    ui.rect(0, SCR_H - BOT_H, SCR_W, BOT_H, COL_PANEL)
    local prog_str = string.format("Page %d/%d", current_page, total_pages)
    ui.text(10, SCR_H - BOT_H + 5, prog_str, FONT_SIZE, COL_TEXT)
    local percent = math.floor((current_page / total_pages) * 100)
    ui.text(SCR_W - 60, SCR_H - BOT_H + 5, percent .. "%", FONT_SIZE, COL_TEXT)
end

-- Рисование текста страницы
function draw_page(page, text_col)
    local start_line = (page - 1) * LINES_PER_PAGE + 1
    for i = 0, LINES_PER_PAGE - 1 do
        local ln = lines[start_line + i]
        if ln then
            ui.text(10, TOP_H + i * LINE_H, ln, FONT_SIZE, text_col)
        end
    end
end

-- Основная функция draw
function draw()
    touch = ui.getTouch()
    ui.rect(0, 0, SCR_W, SCR_H, COL_BG)  -- Фон

    if mode == 'menu' then
        -- Меню выбора файлов
        ui.text(10, 10, "Text Files:", 2, COL_TEXT)
        local scroll_y = ui.beginList(0, 50, SCR_W, SCR_H - 50, scroll_y or 0, #files * 40)
        for i, f in ipairs(files) do
            local y = (i - 1) * 40
            local src = (f.source == "sd" and "[SD] " or "[Int] ")
            if ui.button(10, y, SCR_W - 20, 35, src .. f.path, COL_GRAY) then
                open_file(i)
            end
        end
        ui.endList()
    elseif mode == 'reader' then
        -- Читалка
        draw_hud()

        -- Анимация
        local now = hw.millis()
        local progress = 0
        local text_col = COL_TEXT
        local draw_p = current_page

        if anim_state then
            progress = (now - anim_start) / anim_dur
            if progress > 1 then progress = 1 end

            if anim_state == 'fade_out' then
                -- Затемнение: текст к фону (от черного к белому)
                local factor = progress  -- 0: full, 1: faded
                text_col = darken_color(COL_TEXT, 1 - factor)  -- Но darken от черного будет серым, для fade to white нужно lerp to BG
                -- Лучше lerp colors
                local r1, g1, b1 = bit.rshift(COL_TEXT,11)%32, bit.rshift(COL_TEXT,5)%64, COL_TEXT%32
                local r2, g2, b2 = bit.rshift(COL_BG,11)%32, bit.rshift(COL_BG,5)%64, COL_BG%32
                local lr = math.floor(lerp(r1, r2, progress))
                local lg = math.floor(lerp(g1, g2, progress))
                local lb = math.floor(lerp(b1, b2, progress))
                text_col = rgb565(lr, lg, lb)
                if progress >= 1 then
                    current_page = current_page + next_page
                    anim_state = 'fade_in'
                    anim_start = now
                end
            elseif anim_state == 'fade_in' then
                -- Проявление: от фона к тексту
                progress = 1 - progress  -- Инверт для fade in
                local r1, g1, b1 = bit.rshift(COL_TEXT,11)%32, bit.rshift(COL_TEXT,5)%64, COL_TEXT%32
                local r2, g2, b2 = bit.rshift(COL_BG,11)%32, bit.rshift(COL_BG,5)%64, COL_BG%32
                local lr = math.floor(lerp(r1, r2, progress))
                local lg = math.floor(lerp(g1, g2, progress))
                local lb = math.floor(lerp(b1, b2, progress))
                text_col = rgb565(lr, lg, lb)
                if progress <= 0 then
                    anim_state = nil
                end
            end
        else
            -- Обработка свайпа
            if touch.touching then
                if not is_dragging then
                    drag_start_x = touch.x
                    drag_start_y = touch.y
                    is_dragging = true
                end
            else
                if is_dragging then
                    local dx = drag_start_x - touch.x  -- Левый свайп: dx >0 для next
                    if math.abs(dx) > swipe_threshold then
                        if dx > 0 and current_page < total_pages then
                            next_page = 1
                            anim_state = 'fade_out'
                            anim_start = hw.millis()
                        elseif dx < 0 and current_page > 1 then
                            next_page = -1
                            anim_state = 'fade_out'
                            anim_start = hw.millis()
                        end
                    end
                    is_dragging = false
                end
            end
        end

        -- Рисуем текст
        draw_page(draw_p, text_col)
    end

    ui.flush()
end

-- Инициализация
load_files()
ui.setListInertia(true)  -- Включаем инерцию для списка файлов
