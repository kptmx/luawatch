-- Simple TXT Reader with file browser
-- Fixed: no dependency on sd_ok (check SD availability via sd.list())
-- Large files now possible if you remove 128KB limit in C++ bindings

local W, H = 410, 502
local HEADER_H = 60
local ITEM_H = 55
local LINE_HEIGHT = 32
local TEXT_SIZE = 2
local MARGIN_X = 20
local MARGIN_TOP = HEADER_H + 10

local visibleH = H - HEADER_H
local pageH = visibleH
local contentH_reader = pageH * 3

local mode = "browser"              -- "browser" or "reader"
local currentSource = "internal"    -- "internal" or "sd"
local fileList = {}
local fileName = ""
local errorMsg = nil
local scrollBrowserY = 0
local scrollY = pageH               -- middle of triple buffer

local lines = {}
local linesPerPage = math.floor((visibleH - 20) / LINE_HEIGHT)
local totalPages = 0
local currentPage = 0

-- Check if SD is available (by trying to list root)
local function isSDAvailable()
    local res = sd.list("/")
    if res and res.ok == false then
        return false, res.err or "SD error"
    end
    return true
end

-- Load file (handle both sources)
local function loadFile(path, isSD)
    local content
    if isSD then
        local ok, err = pcall(function()
            local res = sd.readBytes(path)
            if res and type(res) == "string" then
                content = res
            else
                error("read failed")
            end
        end)
        if not ok then return false, "SD read error (file too large?)" end
    else
        local res = fs.readBytes(path)
        if type(res) ~= "string" then
            return false, "Flash read error (file too large?)"
        end
        content = res
    end

    lines = {}
    for line in (content .. "\n"):gmatch("(.-)\r?\n") do
        table.insert(lines, line)
    end
    if #lines > 0 and lines[#lines] == "" then
        table.remove(lines)
    end

    totalPages = math.max(1, math.ceil(#lines / linesPerPage))
    currentPage = 0
    scrollY = pageH
    return true
end

local function refreshFileList()
    fileList = {}
    errorMsg = nil

    local res
    if currentSource == "internal" then
        res = fs.list("/")
    else
        res = sd.list("/")
        if res and res.ok == false then
            errorMsg = res.err or "SD not available"
            return
        end
    end

    -- res is either numbered table (files) or error table (for SD)
    if type(res) ~= "table" or res.ok == false then
        errorMsg = "Failed to list directory"
        return
    end

    -- For internal fs.list returns numbered table, for SD also numbered if ok
    for _, name in ipairs(res) do
        if name:lower():match("%.txt$") then
            table.insert(fileList, name)
        end
    end
    table.sort(fileList)
end

local function drawPage(page, baseY)
    if page < 0 or page >= totalPages then
        local msg = page < 0 and "-- Beginning of file --" or "-- End of file --"
        ui.text(MARGIN_X, baseY + visibleH/2 - 30, msg, 3, 0x8410)
        return
    end

    local startLine = page * linesPerPage + 1
    local endLine = math.min(startLine + linesPerPage - 1, #lines)
    local y = baseY + 10

    for i = startLine, endLine do
        ui.text(MARGIN_X, y, lines[i], TEXT_SIZE, 0xFFFF)
        y = y + LINE_HEIGHT
    end
end

local function drawReader()
    ui.rect(0, 0, W, H, 0)

    ui.text(10, 12, fileName, 2, 0xFFFF)
    ui.text(W - 220, 12, string.format("Page %d/%d (%d lines)", currentPage + 1, totalPages, #lines), 2, 0xFFFF)
    if ui.button(W - 110, 8, 100, 44, "Back", 0xF800) then
        mode = "browser"
    end

    ui.setListInertia(false)
    local updatedScroll = ui.beginList(0, HEADER_H, W, visibleH, scrollY, contentH_reader)

    drawPage(currentPage - 1, 0)
    drawPage(currentPage, pageH)
    drawPage(currentPage + 1, pageH * 2)

    ui.endList()

    if ui.getTouch().released then
        local delta = updatedScroll - pageH
        local threshold = pageH * 0.3

        if delta < -threshold and currentPage > 0 then
            currentPage = currentPage - 1
        elseif delta > threshold and currentPage < totalPages - 1 then
            currentPage = currentPage + 1
        end
        scrollY = pageH
    else
        scrollY = updatedScroll
    end
end

local function drawBrowser()
    ui.rect(0, 0, W, H, 0)

    ui.text(10, 12, "TXT Reader - " .. (currentSource == "internal" and "Internal Flash" or "SD Card"), 2, 0xFFFF)

    local switchLabel = currentSource == "internal" and "Switch to SD Card" or "Switch to Internal Flash"
    local switchColor = 0x07E0

    if ui.button(10, 65, 380, 50, switchLabel, switchColor) then
        currentSource = currentSource == "internal" and "sd" or "internal"
        refreshFileList()
        scrollBrowserY = 0
    end

    if errorMsg then
        ui.text(20, 150, errorMsg, 2, 0xF800)
        return
    end

    if #fileList == 0 then
        ui.text(20, 180, "No .txt files found in root", 3, 0x8410)
        return
    end

    local contentH_browser = #fileList * ITEM_H
    ui.setListInertia(true)
    scrollBrowserY = ui.beginList(0, HEADER_H + 70, W, visibleH - 70, scrollBrowserY, contentH_browser)

    for i, f in ipairs(fileList) do
        local y = (i - 1) * ITEM_H
        if ui.button(10, y, W - 20, ITEM_H - 8, f, 0x0528) then
            local fullPath = "/" .. f
            local ok, err = loadFile(fullPath, currentSource == "sd")
            if ok then
                fileName = f
                mode = "reader"
            else
                errorMsg = err or "Load failed"
            end
        end
    end

    ui.endList()
end

function draw()
    if mode == "browser" then
        drawBrowser()
    else
        drawReader()
    end
    ui.flush()
end

-- Initialization: try SD first, if available
local sdAvail, sdErr = isSDAvailable()
if sdAvail then
    currentSource = "sd"
end
refreshFileList()
