-- Простой клиент для e621.net (NSFW-сайт с артом)
-- Использует API: https://e621.net/posts.json?tags=...&limit=...
-- Требует подключения к WiFi (используйте recovery mode для настройки)
-- Изображения скачиваются на SD-карту в /e621/
-- Ограничения: простой парсер JSON, лимит 20 постов, базовый UI

local SCR_W, SCR_H = 410, 502  -- Размеры экрана
local tags = ""                -- Теги для поиска
local posts = {}               -- Список постов (URLs)
local scrollY = 0              -- Скролл списка
local contentH = 0             -- Высота контента списка
local downloading = false      -- Флаг скачивания
local statusMsg = "Enter tags and press Search"  -- Статус
local selectedPost = nil       -- Для просмотра полного изображения
local zoom = 1.0               -- Зум для просмотра (пока не реализовано)
local offsetX, offsetY = 0, 0  -- Офсет для зума/пана (пока не реализовано)

-- Простой парсер JSON для извлечения URL изображений (только file.url)
function parse_e621_json(json_str)
    local urls = {}
    for url in json_str:gmatch('"file":{"url":"(.-)"') do
        table.insert(urls, url)
    end
    return urls
end

-- Функция поиска и скачивания
function search_and_download()
    if tags == "" then
        statusMsg = "Enter tags!"
        return
    end
    statusMsg = "Searching..."
    local api_url = "https://e621.net/posts.json?tags=" .. tags .. "&limit=20"
    local res = net.get(api_url)
    if not res.ok or res.code ~= 200 then
        statusMsg = "Search failed: " .. (res.err or "unknown")
        return
    end
    local urls = parse_e621_json(res.body)
    if #urls == 0 then
        statusMsg = "No results found"
        return
    end
    posts = {}
    downloading = true
    statusMsg = "Downloading images..."
    sd.mkdir("/e621")  -- Создаем папку, если нет
    for i, url in ipairs(urls) do
        local filename = "/e621/img" .. i .. ".jpg"
        local dl_res = net.download(url, filename)
        if dl_res then
            table.insert(posts, filename)
        else
            statusMsg = "Download failed for some images"
        end
    end
    downloading = false
    statusMsg = "Done! " .. #posts .. " images loaded"
    contentH = #posts * 210  -- Примерная высота: 200px img + 10 margin
end

-- Отрисовка списка изображений
function draw_gallery()
    scrollY = ui.beginList(0, 80, SCR_W, SCR_H - 80, scrollY, contentH)
    local y = 0
    for i, path in ipairs(posts) do
        -- Миниатюра (предполагаем, что изображения масштабируются UI, но drawJPEG_SD рисует в оригинальном размере)
        -- Для миниатюр: рисуем в маленьком размере, но библиотека не масштабирует, так что показываем как есть или обрезаем
        ui.drawJPEG_SD(10, y + 10, path)  -- Рисуем изображение (может быть большим, скролл обработает)
        if ui.button(SCR_W - 100, y + 10, 90, 30, "View", 0x07E0) then
            selectedPost = path
        end
        y = y + 210  -- Расстояние между изображениями
    end
    ui.endList()
end

-- Просмотр полного изображения (простой, без зума)
function draw_viewer()
    ui.drawJPEG_SD(0, 0, selectedPost)  -- Рисует в полном размере, если больше экрана - обрежется клипом
    if ui.button(SCR_W - 100, SCR_H - 50, 90, 40, "Back", 0xF800) then
        selectedPost = nil
    end
end

-- Основная функция draw()
function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000)  -- Черный фон

    -- Шапка: ввод тегов и кнопки
    ui.text(10, 10, "e621 Client", 2, 0xFFFF)
    if ui.input(10, 40, SCR_W - 120, 30, tags, true) then
        -- Здесь можно обработать ввод, но в прошивке input возвращает true при клике (для фокуса)
        -- Реальный ввод текста требует внешней клавиатуры или T9 как в bootstrap, но для простоты предполагаем внешний ввод
    end
    if ui.button(SCR_W - 100, 40, 90, 30, "Search", 0x07E0) and not downloading then
        search_and_download()
    end
    ui.text(10, SCR_H - 30, statusMsg, 1, 0xFFFF)

    -- Галерея или вьювер
    if selectedPost then
        draw_viewer()
    else
        draw_gallery()
    end

    -- Очистка кэша UI периодически (чтобы не жрать PSRAM)
    if hw.millis() % 10000 == 0 then
        ui.unloadAll()
    end
end

-- Инициализация (если нужно)
if not sd.exists("/e621") then
    sd.mkdir("/e621")
end

-- Для ввода тегов: в реальности добавьте T9 или клавиатуру как в bootstrap, но для простоты опущено
-- Пример: tags = "your_tags_here" для теста
