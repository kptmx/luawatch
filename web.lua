-- 1. Обязательно объявляем константы экрана в начале файла
local SCR_W = 410
local SCR_H = 502

local STYLES = {
    h1 = {size = 3, color = 0xF800},
    h2 = {size = 2, color = 0xFDA0},
    text = {size = 1, color = 0xFFFF},
    link = {size = 1, color = 0x001F}
}

local browser = {
    url = "http://google.com",
    elements = {},
    scroll = 0,
    history = {},
    show_kbd = false
}

-- Вспомогательная функция для разбиения длинного текста на строки
local function wrap_text(text, limit)
    local lines = {}
    while #text > limit do
        local chunk = text:sub(1, limit)
        table.insert(lines, chunk)
        text = text:sub(limit + 1)
    end
    table.insert(lines, text)
    return lines
end

local function draw_loading(status)
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000)
    ui.text(100, 200, "LOADING...", 2, 0xFFFF)
    if status then ui.text(20, 250, status:sub(-40), 1, 0x7BEF) end
    ui.flush()
end

local function resolve(path)
    if not path or path:sub(1,4) == "http" then return path end
    local proto, host = browser.url:match("(https?://)([^/]+)")
    if path:sub(1,1) == "/" then return proto .. host .. path end
    return browser.url:match("(.*)/") .. "/" .. path
end

local function parse_html(html)
    browser.elements = {}
    -- Чистим мусор
    html = html:gsub("<script.-</script>", ""):gsub("<style.-</style>", ""):gsub("<!%-%-.-%-%->", "")
    
    local pos = 1
    while pos <= #html do
        local start_tag, end_tag, tag_body = html:find("<(%/?%w+.-)>", pos)
        
        -- Текст до тега
        local text_before = html:sub(pos, (start_tag or 0) - 1):gsub("%s+", " ")
        if #text_before > 1 then
            -- Применяем Word Wrap (примерно 40 символов для size 1)
            local lines = wrap_text(text_before, 40)
            for _, line in ipairs(lines) do
                table.insert(browser.elements, {type="text", val=line})
            end
        end

        if not start_tag then break end

        local tag_name = tag_body:match("^(%w+)"):lower()
        if tag_name:match("h[1-3]") then
            local h_end = html:find("</" .. tag_name .. ">", end_tag)
            if h_end then
                table.insert(browser.elements, {type="header", level=tag_name:sub(2,2), val=html:sub(end_tag + 1, h_end - 1)})
                end_tag = h_end + #tag_name + 3
            end
        elseif tag_name == "a" then
            local href = tag_body:match("href=\"([^\"]+)\"")
            local a_end = html:find("</a>", end_tag)
            if a_end then
                table.insert(browser.elements, {type="link", val=html:sub(end_tag+1, a_end-1), url=href})
                end_tag = a_end + 4
            end
        elseif tag_name == "img" then
            local src = tag_body:match("src=\"([^\"]+)\"")
            if src and (src:find(".jp") or src:find(".JP")) then
                table.insert(browser.elements, {type="img", src=src})
            end
        end
        pos = end_tag + 1
    end
end

function navigate(new_url)
    draw_loading(new_url)
    collectgarbage("collect") -- Важно для очистки памяти после предыдущей страницы
    
    local res = net.get(new_url)
    if res.ok then
        browser.url = new_url
        parse_html(res.body)
        
        for _, el in ipairs(browser.elements) do
            if el.type == "img" then
                draw_loading("Downloading image...")
                net.download(resolve(el.src), "/web/img.jpg", "flash")
                break
            end
        end
    else
        browser.elements = {{type="header", level="1", val="Error"}, {type="text", val=tostring(res.err or res.code)}}
    end
end

-- T9 логика
local t9 = { keys = {["2"]="abc",["3"]="def",["4"]="ghi",["5"]="jkl",["6"]="mno",["7"]="pqrs",["8"]="tuv",["9"]="wxyz",["0"]=". /:"}, last="", idx=1, time=0 }
function handle_t9(k)
    local now = hw.millis()
    if t9.last == k and (now - t9.time) < 800 then
        browser.url = browser.url:sub(1,-2)
        t9.idx = t9.idx % #t9.keys[k] + 1
    else t9.idx = 1 end
    browser.url = browser.url .. t9.keys[k]:sub(t9.idx, t9.idx)
    t9.last, t9.time = k, now
end

function loop()
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000)
    
    -- Панель адреса
    if ui.button(5, 5, 330, 40, browser.url:sub(-25), 0x18C3) then browser.show_kbd = not browser.show_kbd end
    if ui.button(340, 5, 65, 40, "GO", 0x07E0) then navigate(browser.url) end

    -- Список контента
    browser.scroll = ui.beginList(0, 50, SCR_W, 452, 35, browser.scroll)
    for i, el in ipairs(browser.elements) do
        if el.type == "header" then
            local s = STYLES["h"..el.level] or STYLES.h1
            ui.text(10, 0, el.val, s.size, s.color)
        elseif el.type == "text" then
            ui.text(10, 0, el.val, 1, 0xFFFF)
        elseif el.type == "link" then
            if ui.button(10, 0, 380, 30, "> "..el.val:sub(1,35), 0x001F) then
                table.insert(browser.history, browser.url)
                navigate(resolve(el.url))
            end
        elseif el.type == "img" then
            if fs.exists("/web/img.jpg") then ui.drawJPEG(10, 0, "/web/img.jpg") 
            else ui.text(10, 0, "[IMG]", 1, 0x07E0) end
        end
    end
    ui.endList()

    -- T9 клавиатура
    if browser.show_kbd then
        ui.rect(0, 220, SCR_W, 282, 0x0841)
        local keys = {"1","2","3","4","5","6","7","8","9","CLR","0","DEL"}
        for i, k in ipairs(keys) do
            local x, y = 10 + ((i-1)%3)*135, 230 + math.floor((i-1)/3)*65
            if ui.button(x, y, 120, 55, k, 0x3333) then
                if k == "DEL" then browser.url = browser.url:sub(1,-2)
                elseif k == "CLR" then browser.url = ""
                elseif t9.keys[k] then handle_t9(k) end
            end
        end
    end
    ui.flush()
end

-- Старт
fs.mkdir("/web")
navigate(browser.url)
while true do loop() end
