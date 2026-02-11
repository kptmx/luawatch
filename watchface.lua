-- Текстовая читалка с полной загрузкой в PSRAM
TextReader = {
    -- Данные
    text = nil,          -- весь текст в памяти
    lines = {},          -- массив строк
    totalLines = 0,
    
    -- UI состояния
    currentFile = nil,
    fileBrowserActive = false,
    files = {},
    browserScroll = 0,
    selectedFS = "sd",
    
    -- Параметры отображения
    lineHeight = 26,     -- высота строки при шрифте 2
    visibleLines = 14,   -- сколько строк помещается (375/26 ≈ 14)
    topLine = 0,         -- первая видимая строка
    targetTopLine = 0,   -- целевая позиция для доводчика
    
    -- Скролл
    scrollY = 0,
    velocity = 0,
    isDragging = false,
    
    -- Загрузка файла
    loadFile = function(self, path, fsType)
        self.currentFile = path
        self.currentFS = fsType or "sd"
        self.topLine = 0
        self.targetTopLine = 0
        self.lines = {}
        
        -- Читаем весь файл
        local content = nil
        if self.currentFS == "sd" then
            content = sd.readBytes(self.currentFile)
        else
            content = fs.readBytes(self.currentFile)
        end
        
        if content and #content > 0 then
            self.text = content
            
            -- Разбиваем на строки (лениво, только когда понадобятся)
            self:_ensureLinesLoaded(0, self.visibleLines * 3)
            
            -- Подсчитываем общее количество строк
            self.totalLines = 0
            for _ in content:gmatch("\n") do
                self.totalLines = self.totalLines + 1
            end
            self.totalLines = self.totalLines + 1 -- последняя строка без \n
        end
        
        -- Очищаем старый кэш
        self:_cleanupCache()
    end,
    
    -- Ленивая загрузка строк (только нужный диапазон)
    _ensureLinesLoaded = function(self, startIdx, count)
        local endIdx = startIdx + count - 1
        
        for i = startIdx, endIdx do
            if i >= 0 and i < self.totalLines and not self.lines[tostring(i)] then
                -- Извлекаем конкретную строку из текста
                local line = self:_extractLine(i)
                if line then
                    self.lines[tostring(i)] = line
                end
            end
        end
    end,
    
    -- Извлечение одной строки по индексу
    _extractLine = function(self, idx)
        if not self.text then return "" end
        
        local startPos = 1
        local currentIdx = 0
        local line = ""
        
        for i = 1, #self.text do
            if currentIdx == idx then
                -- Начали нужную строку
                local lineStart = i
                local lineEnd = i
                
                while lineEnd <= #self.text and self.text:sub(lineEnd, lineEnd) ~= "\n" do
                    lineEnd = lineEnd + 1
                end
                
                line = self.text:sub(lineStart, lineEnd - 1)
                break
            end
            
            if self.text:sub(i, i) == "\n" then
                currentIdx = currentIdx + 1
            end
        end
        
        -- Очищаем от управляющих символов
        line = line:gsub("\r", "")
        
        -- Обрезаем слишком длинные строки
        if #line > 50 then
            line = line:sub(1, 47) .. "..."
        end
        
        return line
    end,
    
    -- Очистка кэша за пределами видимой области
    _cleanupCache = function(self)
        local keepStart = math.max(0, self.topLine - self.visibleLines * 2)
        local keepEnd = self.topLine + self.visibleLines * 3
        
        for k, _ in pairs(self.lines) do
            local idx = tonumber(k)
            if idx < keepStart or idx > keepEnd then
                self.lines[k] = nil
            end
        end
    end,
    
    -- Рендеринг видимых строк
    renderText = function(self)
        -- Загружаем видимые строки + буферные
        self:_ensureLinesLoaded(self.topLine, self.visibleLines + 4)
        
        -- Рендерим строки
        for i = 0, self.visibleLines - 1 do
            local lineIdx = self.topLine + i
            if lineIdx < self.totalLines then
                local line = self.lines[tostring(lineIdx)] or ""
                local y = 70 + i * self.lineHeight
                
                -- Подсветка текущей позиции (опционально)
                if lineIdx == self.topLine then
                    ui.fillRect(5, y - 18, 400, self.lineHeight, 0x2104)
                end
                
                -- Номер строки (опционально)
                -- ui.text(10, y, string.format("%d", lineIdx + 1), 1, 0x7BEF)
                -- Текст
                ui.text(25, y, line, 2, 0xFFFF)
            end
        end
        
        -- Прогресс-бар
        if self.totalLines > 0 then
            local progress = self.topLine / (self.totalLines - self.visibleLines)
            if progress < 0 then progress = 0 end
            if progress > 1 then progress = 1 end
            
            -- Полоса прокрутки
            ui.fillRect(395, 70, 3, 375, 0x4208)
            local thumbY = 70 + progress * (375 - 30)
            ui.fillRoundRect(390, thumbY, 12, 30, 6, 0x7BEF)
        end
    end,
    
    -- Файловый браузер
    drawFileBrowser = function(self)
        ui.rect(0, 0, 410, 502, 0)
        ui.text(80, 20, "File Browser", 3, 2016)
        
        -- Переключатель SD/Flash
        if ui.button(20, 60, 100, 35, "SD", self.selectedFS == "sd" and 1040 or 8452) then
            self.selectedFS = "sd"
            self:refreshFileList()
        end
        if ui.button(130, 60, 100, 35, "FLASH", self.selectedFS == "flash" and 1040 or 8452) then
            self.selectedFS = "flash"
            self:refreshFileList()
        end
        
        -- Список файлов
        local scroll = ui.beginList(5, 105, 400, 350, self.browserScroll, 800)
        
        local y = 10
        for i, file in ipairs(self.files) do
            local icon = file:match("%.txt$") and "📄 " or "📁 "
            
            if ui.button(10, y, 380, 35, icon .. file, 2113) then
                if file:match("%.txt$") then
                    self:loadFile(file, self.selectedFS)
                    self.fileBrowserActive = false
                    self.scrollY = 0
                    self.topLine = 0
                end
            end
            y = y + 40
        end
        
        ui.endList()
        self.browserScroll = scroll
        
        -- Кнопка назад в браузере
        if ui.button(300, 460, 90, 35, "CANCEL", 63488) then
            self.fileBrowserActive = false
        end
    end,
    
    -- Обновление списка файлов
    refreshFileList = function(self)
        self.files = {}
        local list = {}
        
        if self.selectedFS == "sd" then
            list = sd.list("/")
        else
            list = fs.list("/")
        end
        
        if list and type(list) == "table" then
            local txtFiles = {}
            for i, name in ipairs(list) do
                if name:match("%.txt$") then
                    table.insert(txtFiles, name)
                end
            end
            table.sort(txtFiles)
            self.files = txtFiles
        end
    end,
    
    -- Основной рендер
    render = function(self)
        if self.fileBrowserActive then
            self:drawFileBrowser()
            return
        end
        
        if not self.currentFile then
            self.fileBrowserActive = true
            self:refreshFileList()
            self:drawFileBrowser()
            return
        end
        
        -- Очистка
        ui.rect(0, 0, 410, 502, 0)
        
        -- Заголовок
        ui.text(10, 20, self.currentFile:match("([^/]+)$"), 2, 2016)
        
        -- Информация о прогрессе
        local percent = 0
        if self.totalLines > 0 then
            percent = math.floor((self.topLine / (self.totalLines - self.visibleLines)) * 100)
        end
        ui.text(300, 20, percent .. "%", 2, 65535)
        
        -- Область текста
        ui.pushClip(5, 65, 400, 375)
        
        -- Применяем скролл оффсет
        self.topLine = math.floor(self.scrollY / self.lineHeight)
        
        -- Ограничиваем
        local maxTop = math.max(0, self.totalLines - self.visibleLines)
        if self.topLine > maxTop then
            self.topLine = maxTop
            self.scrollY = self.topLine * self.lineHeight
        end
        if self.topLine < 0 then
            self.topLine = 0
            self.scrollY = 0
        end
        
        -- Рендерим текст
        self:renderText()
        
        ui.popClip()
        
        -- Кнопка "Список файлов"
        if ui.button(300, 450, 90, 35, "FILES", 1040) then
            self.fileBrowserActive = true
            self:refreshFileList()
            self.browserScroll = 0
        end
        
        -- Обработка тача для скролла
        local touch = ui.getTouch()
        
        if touch.touching then
            -- Проверяем, тач в области текста
            if touch.x > 5 and touch.x < 405 and touch.y > 65 and touch.y < 440 then
                if not self.isDragging then
                    self.isDragging = true
                    self.dragStartY = touch.y
                    self.dragStartScroll = self.scrollY
                    self.velocity = 0
                else
                    -- Считаем скорость для инерции
                    local delta = self.dragStartY - touch.y
                    self.scrollY = self.dragStartScroll + delta
                    self.velocity = self.velocity * 0.8 + delta * 0.2
                    
                    -- Ограничиваем
                    if self.scrollY < 0 then 
                        self.scrollY = self.scrollY * 0.5
                        self.velocity = 0
                    end
                    local maxScroll = (self.totalLines - self.visibleLines) * self.lineHeight
                    if self.scrollY > maxScroll then
                        self.scrollY = maxScroll + (self.scrollY - maxScroll) * 0.5
                        self.velocity = 0
                    end
                end
            end
        else
            -- Доводчик с инерцией
            if self.isDragging then
                self.isDragging = false
                self.targetTopLine = self.topLine
            else
                -- Инерция
                if math.abs(self.velocity) > 0.5 then
                    self.scrollY = self.scrollY - self.velocity
                    self.velocity = self.velocity * 0.92
                    
                    -- Ограничиваем
                    if self.scrollY < 0 then
                        self.scrollY = 0
                        self.velocity = 0
                    end
                    local maxScroll = (self.totalLines - self.visibleLines) * self.lineHeight
                    if self.scrollY > maxScroll then
                        self.scrollY = maxScroll
                        self.velocity = 0
                    end
                else
                    self.velocity = 0
                end
            end
            
            -- Очищаем кэш когда не скроллим
            if math.abs(self.velocity) < 0.1 then
                self:_cleanupCache()
            end
        end
    end
}

-- Глобальная читалка
reader = nil

function draw()
    if not reader then
        reader = TextReader:new()
    end
    
    reader:render()
end

function openFile(path, useSD)
    reader = TextReader:new()
    reader:loadFile(path, useSD and "sd" or "flash")
    reader.fileBrowserActive = false
end
