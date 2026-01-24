local SCR_W, SCR_H = 410, 502

local state = "menu"            -- menu, loading, view
local rating = nil              -- nil = any, "s", "q", "e"
local image_path = "/current.jpg"   -- file on SD card (root)
local sd_path = "/sdcard" .. image_path

local function load_random_post()
    state = "loading"
    
    -- Unload previous image from cache to free PSRAM
    ui.unload(image_path)

    local tags = "order:random"
    if rating then
        tags = tags .. " rating:" .. rating
    end

    local api_url = "https://e621.net/posts.json?limit=1&tags=" .. tags

    local res = net.get(api_url)
    if not (res.ok and res.code == 200) then
        state = "menu"
        return
    end

    local body = res.body

    -- Prioritize sample_url (always JPEG, scaled down)
    local sample_url = string.match(body, '"sample_url":"(//[^"]+)"')
    local preview_url = string.match(body, '"preview_url":"(//[^"]+)"')

    local chosen_url = nil
    if sample_url then
        chosen_url = "https:" .. sample_url
    elseif preview_url then
        chosen_url = "https:" .. preview_url
    end

    if not chosen_url then
        state = "menu"
        return
    end

    -- Download to SD card
    local ok = net.download(chosen_url, sd_path)
    if ok then
        state = "view"
    else
        state = "menu"
    end
end

function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0)  -- black background

    if state == "menu" then
        ui.text(20, 40, "e621 Random Viewer", 3, 0xFFFF)
        ui.text(20, 100, "Warning: May contain NSFW content", 2, 0xF800)

        ui.text(20, 160, "Select rating:", 2, 0xFFFF)

        local btn_w = 90
        local spacing = 15
        local start_x = 35

        -- Any
        local color_any = (rating == nil) and 0x07E0 or 0x4444
        if ui.button(start_x, 220, btn_w, 60, "Any", color_any) then rating = nil end

        -- Safe
        local color_s = (rating == "s") and 0x07E0 or 0x4444
        if ui.button(start_x + btn_w + spacing, 220, btn_w, 60, "Safe", color_s) then rating = "s" end

        -- Questionable
        local color_q = (rating == "q") and 0x07E0 or 0x4444
        if ui.button(start_x + 2*(btn_w + spacing), 220, btn_w, 60, "Quest.", color_q) then rating = "q" end

        -- Explicit
        local color_e = (rating == "e") and 0x07E0 or 0x4444
        if ui.button(start_x + 3*(btn_w + spacing), 220, btn_w, 60, "Expl.", color_e) then rating = "e" end

        -- Load button
        if ui.button(105, 320, 200, 80, "Get Random", 0x07E0) then
            load_random_post()
        end

    elseif state == "loading" then
        ui.text(80, 200, "Loading...", 3, 0xFFFF)
        ui.text(80, 260, "This may take a while", 2, 0xAAAA)

    elseif state == "view" then
        -- Display the downloaded sample/preview JPEG
        local drawn = ui.drawJPEG_SD(0, 0, image_path)

        if not drawn then
            ui.text(50, 200, "Failed to display image", 3, 0xF800)
        end

        -- Controls
        if ui.button(10, SCR_H - 90, 180, 80, "Back", 0xF800) then
            state = "menu"
        end

        if ui.button(SCR_W - 190, SCR_H - 90, 180, 80, "Next", 0x07E0) then
            load_random_post()
        end
    end
end
