-- e621 Simple Client (1 image version) + Debug + Progress
local SCR_W, SCR_H = 410, 502

local tags = ""                     -- вводимые теги
local currentImage = nil            -- путь к скачанному изображению
local downloading = false
local downloadProgress = 0
local downloadTotal = 0
local statusMsg = "Enter tags and press Search"
local debugMsg = ""                 -- отдельный красный текст для ошибок

-- Замена пробелов на + для API
local function escapeTags(t)
    return t:gsub("%s+", "+")
end

-- Простой парсер (берём только первый url)
local function parse_e621_json(json_str)
    local url = json_str:match('"file":{"url":"(.-)"')
    return url
end

-- Основная функция поиска и скачивания
function search_and_download()
    if tags == "" then
        debugMsg = "Ошибка: введите теги!"
        statusMsg = ""
        return
    end

    statusMsg = "Поиск..."
    debugMsg = ""
    local api_url = "https://e621.net/posts.json?tags=" .. escapeTags(tags) .. "&limit=1"
    local res = net.get(api_url)

    if not res.ok or res.code ~= 200 then
        debugMsg = "API Error: " .. (res.err or "code " .. (res.code or "?"))
        statusMsg = "Поиск не удался"
        return
    end

    local image_url = parse_e621_json(res.body)
    if not image_url then
        debugMsg = "Нет изображений по тегам"
        statusMsg = "Ничего не найдено"
        return
    end

    -- Скачиваем
    downloading = true
    downloadProgress = 0
    downloadTotal = 0
    statusMsg = "Загрузка..."
    debugMsg = ""

    sd.mkdir("/e621")

    local path = "/e621/img1.jpg"
    local success = net.download(image_url, path, function(loaded, total)
        downloadProgress = loaded
        downloadTotal = total or 0
    end)

    downloading = false

    if success then
        currentImage = path
        statusMsg = "Успешно загружено!"
        debugMsg = ""
    else
        debugMsg = "Ошибка загрузки изображения"
        statusMsg = "Не удалось скачать"
        currentImage = nil
    end
end

-- Отрисовка прогресс-бара
local function drawProgressBar()
    local x, y, w, h = 20, 90, SCR_W - 40, 24
    ui.rect(x, y, w, h, 0x2104)                    -- фон
    if downloadTotal > 0 then
        local perc = downloadProgress / downloadTotal
        local fill = math.floor(w * perc)
        ui.rect(x, y, fill, h, 0x07E0)             -- зелёный прогресс
        local percent = math.floor(perc * 100)
        ui.text(x + 10, y + 4, percent .. "%", 2, 0xFFFF)
    else
        ui.text(x + 10, y + 4, "Загрузка...", 2, 0xFFFF)
    end
end

function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000)  -- чёрный фон

    -- Заголовок
    ui.text(15, 12, "e621 Viewer", 3, 0xF81F)

    -- Поле ввода тегов
    if ui.input(15, 50, SCR_W - 140, 40, "Tags: " .. tags, true) then
        -- фокус (реальный ввод через T9 или внешнюю клавиатуру)
    end

    -- Кнопка Search
    if ui.button(SCR_W - 110, 50, 90, 40, "Search", 0x07E0) and not downloading then
        search_and_download()
    end

    -- Прогресс загрузки
    if downloading then
        drawProgressBar()
    end

    -- Отладка (красный текст)
    if debugMsg ~= "" then
        ui.text(15, SCR_H - 90, debugMsg, 2, 0xF800)  -- красный
    end

    -- Статус
    ui.text(15, SCR_H - 55, statusMsg, 2, 0xFFFF)

    -- Просмотр изображения
    if currentImage then
        ui.drawJPEG_SD(0, 120, currentImage)  -- рисуем изображение ниже шапки

        if ui.button(SCR_W - 100, SCR_H - 55, 85, 40, "Back", 0xF800) then
            currentImage = nil
            statusMsg = "Готов к новому поиску"
        end
    end

    -- Периодическая очистка кэша
    if hw.millis() % 15000 < 50 then
        ui.unloadAll()
    end
end

-- Создаём папку при старте
if not sd.exists("/e621") then
    sd.mkdir("/e621")
end
