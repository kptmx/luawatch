-- Настройки
local SCR_W, SCR_H = 410, 502
local IMG_DIR = "/sdcard/e621/"
local API_URL = "https://e621.net/posts.json?limit=5&tags=rating:s" -- rating:s для безопасности при тестах

-- Состояние
local posts = {}
local status_msg = "Initializing..."
local scroll_y = 0
local is_loading = false
local logs = {}

-- Функция логирования на экран
function log(txt)
    print(txt) -- В Serial
    table.insert(logs, 1, "> " .. tostring(txt))
    if #logs > 10 then table.remove(logs) end
    status_msg = txt
end

-- Создаем папку для кэша
fs.mkdir(IMG_DIR)

function fetch_posts()
    if is_loading then return end
    is_loading = true
    log("Fetching API...")
    
    -- e621 требует User-Agent (вшит в прошивку или передается через заголовки, если библиотека позволяет)
    -- В данном случае используем упрощенный net.get
    local res = net.get(API_URL)
    
    if res and res.ok and res.code == 200 then
        log("Parsing JSON...")
        -- Внимание: в этой прошивке нет встроенной библиотеки json. 
        -- Предположим, мы ищем ссылки через простейший поиск строк (pattern matching), 
        -- так как полноценный JSON парсер на Lua может съесть память.
        
        local body = res.body
        posts = {}
        local count = 0
        -- Ищем превьюшки в JSON: "preview":{"url":"..."}
        for url in body:gmatch('"preview"%s*:%s*{"url"%s*:%s*"(https://[^"]+)"') do
            count = count + 1
            local filename = IMG_DIR .. "p" .. count .. ".jpg"
            table.insert(posts, {url = url, path = filename, loaded = false})
            if count >= 5 then break end
        end
        log("Found " .. count .. " images")
        download_next(1)
    else
        is_loading = false
        log("API Error: " .. (res.code or "null"))
    end
end

function download_next(idx)
    if not posts[idx] then 
        is_loading = false
        log("All downloads done")
        return 
    end
    
    log("DL: " .. idx .. "/" .. #posts)
    -- Используем net.download(url, path, callback)
    local ok = net.download(posts[idx].url, posts[idx].path, function(cur, total)
        status_msg = "DL: " .. math.floor((cur/total)*100) .. "%"
    end)
    
    if ok then
        posts[idx].loaded = true
        ui.unload(posts[idx].path) -- Сброс кэша если был
    end
    download_next(idx + 1)
end

function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0) -- Фон
    
    -- Заголовок и Логи
    ui.text(10, 10, "e621 Client", 3, 0x07E0)
    for i, l in ipairs(logs) do
        ui.text(10, 40 + (i-1)*20, l, 1, 0x7BEF)
    end
    
    -- Кнопка обновления
    if ui.button(280, 10, 120, 40, "FETCH", 0x001F) then
        if net.status() == 3 then
            fetch_posts()
        else
            log("No WiFi!")
        end
    end

    -- Список изображений
    local list_h = 350
    scroll_y = ui.beginList(10, 140, 390, list_h, scroll_y, #posts * 220)
    
    for i, post in ipairs(posts) do
        local y_pos = (i-1) * 220
        ui.rect(0, y_pos, 380, 210, 0x2104) -- Рамка
        
        if post.loaded then
            -- Отрисовка скачанного JPEG
            if not ui.drawJPEG_SD(10, y_pos + 5, post.path) then
                ui.text(20, y_pos + 100, "Load Error", 2, 0xF800)
            end
        else
            ui.text(20, y_pos + 100, "Waiting...", 2, 0xFFFF)
        end
    end
    
    ui.endList()
    
    -- Инфо панель внизу
    ui.rect(0, SCR_H - 30, SCR_W, 30, 0x4208)
    ui.text(5, SCR_H - 25, "RAM: " .. math.floor(hw.getFreePsram()/1024) .. "KB | " .. status_msg, 1, 0xFFFF)
end
