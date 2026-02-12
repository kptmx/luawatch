-- Минимальный тест тача
local last_x, last_y = -1, -1

function draw()
    -- Очищаем экран раз в 2 секунды
    if hw.millis() % 2000 < 50 then
        ui.rect(0, 0, 410, 502, 0x0000)
    end
    
    local touch = ui.getTouch()
    
    -- Основная информация
    ui.text(10, 20, "TOUCH TEST", 3, 0xFFFF)
    
    if touch.touching then
        ui.text(10, 70, "STATUS: TOUCHING", 2, 0x07E0)
        ui.text(10, 100, string.format("X: %d", touch.x), 2, 0x07E0)
        ui.text(10, 130, string.format("Y: %d", touch.y), 2, 0x07E0)
        
        -- Рисуем точку
        ui.rect(touch.x - 5, touch.y - 5, 10, 10, 0x07E0)
        
        last_x, last_y = touch.x, touch.y
    else
        ui.text(10, 70, "STATUS: RELEASED", 2, 0xF800)
        if last_x ~= -1 then
            ui.text(10, 100, string.format("LAST X: %d", last_x), 2, 0xF800)
            ui.text(10, 130, string.format("LAST Y: %d", last_y), 2, 0xF800)
            -- Рисуем последнюю точку красным
            ui.rect(last_x - 5, last_y - 5, 10, 10, 0xF800)
        end
    end
    
    -- Счетчик времени
    local seconds = math.floor(hw.millis() / 1000)
    ui.text(300, 20, string.format("%02d:%02d", seconds/60, seconds%60), 2, 0x7BEF)
end

print("Minimal touch test ready!")
