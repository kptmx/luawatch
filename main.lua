-- file_manager_touch.lua
-- Полностью тач-управление: скролл + тап по файлу

local SCR_W = 410
local SCR_H = 502

local current_path = "/"
local files = {}
local selected_idx = 0          -- 0 = ничего не выбрано
local scroll_y = 0
local mode = "list"             -- list, create, edit, run_confirm, delete_confirm

local new_filename = ""
local new_content  = ""
local edit_content = ""
local message = ""

local ITEM_HEIGHT = 44          -- увеличил для удобства тапа пальцем

local function refresh_files()
    files = fs.list(current_path) or {}
    table.sort(files)
    selected_idx = 0
end

local function is_lua_file(name)
    return name:lower():match("%.lua$") ~= nil
end

local function try_run_file(fullpath)
    local code = fs.load(fullpath)
    if not code or code == "" then
        message = "File empty or read error"
        return
    end

    local chunk, err = load(code, fullpath, "t")
    if not chunk then
        message = "Compile error: " .. (err or "unknown")
        return
    end

    local ok, run_err = pcall(chunk)
    if not ok then
        message = "Runtime error: " .. tostring(run_err)
    else
        message = "Script launched ✓ (see serial)"
    end
end

-- ────────────────────────────────────────────────
refresh_files()

function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000)

    -- Заголовок
    ui.text(12, 12, "Path: " .. current_path, 2, 0x07FF)
    ui.text(12, 38, message, 2, 0xFFFF00)
    message = ""

    if mode == "list" then
        -- =====================================
        --   СКРОЛЛИРУЕМЫЙ СПИСОК — ТАЧ ОСНОВА
        -- =====================================
        local content_height = #files * ITEM_HEIGHT + 20

        local old_scroll = scroll_y
        scroll_y = ui.beginList(8, 70, SCR_W-16, SCR_H-150, scroll_y, content_height)

        for i, fname in ipairs(files) do
            local y = (i-1) * ITEM_HEIGHT + 12
            local is_selected = (i == selected_idx)
            local color = is_selected and 0x001F or 0xCE59   -- тёмно-синий / серо-голубой
            local text_color = is_selected and 0xFFFF or 0xFFFF

            local icon = fs.exists(current_path .. fname .. "/") and "[DIR]" or (is_lua_file(fname) and "[LUA]" or "     ")
            local display_text = icon .. "  " .. fname

            ui.fillRect(12, y-4, SCR_W-24, ITEM_HEIGHT-8, color)
            ui.text(24, y, display_text, 2, text_color)
        end

        ui.endList()

        -- Если скролл изменился → снимаем выделение (чтобы не было "залипания")
        if scroll_y ~= old_scroll then
            selected_idx = 0
        end

        -- Кнопки действий (крупные, для пальца)
        local btn_y = SCR_H - 110
        if ui.button(8, btn_y, 130, 60, "↑ Up", 0x07E0) then
            if current_path ~= "/" then
                current_path = current_path:match("^(.*)/[^/]+/?$") or "/"
                if current_path == "" then current_path = "/" end
                refresh_files()
            end
        end

        if ui.button(146, btn_y, 130, 60, "New .lua", 0x07FF) then
            mode = "create"
            new_filename = ""
            new_content = ""
        end

        if selected_idx > 0 then
            local sel_name = files[selected_idx]
            local is_dir = fs.exists(current_path .. sel_name .. "/")

            if ui.button(284, btn_y, 118, 60, is_dir and "Open" or "Run/Edit", 0xFFE0) then
                if is_dir then
                    current_path = current_path .. sel_name .. "/"
                    refresh_files()
                elseif is_lua_file(sel_name) then
                    mode = "run_confirm"
                else
                    mode = "edit"
                    edit_content = fs.load(current_path .. sel_name) or ""
                end
            end

            if ui.button(8, SCR_H-45, 190, 40, "Delete " .. sel_name:sub(1,15).."...", 0xF800) then
                mode = "delete_confirm"
            end
        end

        -- Подсказка как выбрать
        if selected_idx == 0 then
            ui.text(20, SCR_H-145, "Tap file to select", 1, 0x9492)
        end

    elseif mode == "create" then
        ui.text(20, 90, "New filename (no .lua needed):", 2, 0xFFFF)
        new_filename = ui.input(20, 125, 370, 50, new_filename, true)

        ui.text(20, 190, "Initial content:", 2, 0xFFFF)
        new_content = ui.input(20, 225, 370, 140, new_content, true)

        if ui.button(20, 380, 180, 60, "Save", 0x07E0) then
            if new_filename == "" then
                message = "Name required"
            else
                local fname = new_filename
                if not fname:match("%.lua$") then fname = fname .. ".lua" end
                local full = current_path .. fname
                local ok = fs.save(full, new_content or "")
                if ok then
                    message = "Created: " .. fname
                    mode = "list"
                    refresh_files()
                else
                    message = "Save failed"
                end
            end
        end

        if ui.button(210, 380, 180, 60, "Cancel", 0xF800) then
            mode = "list"
        end

    elseif mode == "edit" then
        local fname = files[selected_idx]
        ui.text(20, 80, "Editing: " .. fname, 2, 0x07FF)

        ui.text(20, 120, "Append line:", 2, 0xFFFF)
        local added = ui.input(20, 150, 370, 100, "", true)
        if added and added ~= "" then
            fs.append(current_path .. fname, "\n" .. added)
            edit_content = fs.load(current_path .. fname) or ""
            message = "Appended ✓"
        end

        ui.text(20, 270, "Preview (first 180 chars):", 2, 0xBDF7)
        ui.text(28, 300, edit_content:sub(1,180) .. (#edit_content>180 and "..." or ""), 1, 0xFFFF)

        if ui.button(20, SCR_H-70, 180, 50, "Back", 0x07E0) then
            mode = "list"
        end

    elseif mode == "run_confirm" then
        local fname = files[selected_idx]
        ui.text(50, 140, "Run script?", 3, 0xFFFF)
        ui.text(50, 190, fname, 2, 0x07FF)

        if ui.button(40, 260, 160, 70, "YES, Run", 0x07E0) then
            try_run_file(current_path .. fname)
            mode = "list"
        end
        if ui.button(210, 260, 160, 70, "No", 0xF800) then
            mode = "list"
        end

    elseif mode == "delete_confirm" then
        local fname = files[selected_idx]
        ui.text(50, 140, "Delete file?", 3, 0xFFFF)
        ui.text(50, 190, fname, 2, 0xF800)

        if ui.button(40, 260, 160, 70, "YES, Delete", 0xF800) then
            fs.remove(current_path .. fname)
            message = "Deleted"
            mode = "list"
            refresh_files()
        end
        if ui.button(210, 260, 160, 70, "No", 0x07E0) then
            mode = "list"
        end
    end
end
