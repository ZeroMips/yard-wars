-- Drawing of medpacks (the logic is in src/world.lua): a white box with a red cross
-- and a thick dark outline (comic style), bobbing a little. It pops in when dropped
-- and blinks during its last seconds.
local Medpack = {}

local W, H = 30, 24  -- box size (world px)
local BLINK = 3      -- seconds before expiry when it starts blinking

-- m = { x, y, born, expires }, time = current world time
function Medpack.draw(m, time)
    local left = m.expires - time
    if left < BLINK and math.floor(left * 6) % 2 == 1 then return end

    local age = time - m.born
    local pop = 1
    if age < 0.3 then -- overshooting pop-in
        local k = age / 0.3
        pop = k + math.sin(k * math.pi) * 0.35
    end
    local bob = math.sin(time * 3 + m.x * 0.01) * 2

    love.graphics.push()
    love.graphics.translate(m.x, m.y)

    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.ellipse("fill", 0, H * 0.55, W * 0.55 * pop, H * 0.25 * pop)

    love.graphics.translate(0, bob - 4)
    love.graphics.scale(pop)
    love.graphics.setColor(0.12, 0.1, 0.12, 1) -- outline
    love.graphics.rectangle("fill", -W / 2 - 3, -H / 2 - 3, W + 6, H + 6, 7, 7)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", -W / 2, -H / 2, W, H, 5, 5)
    love.graphics.setColor(0.85, 0.85, 0.88, 1) -- shaded bottom
    love.graphics.rectangle("fill", -W / 2, H / 2 - 6, W, 6, 5, 5)
    love.graphics.setColor(0.9, 0.15, 0.15, 1) -- red cross
    love.graphics.rectangle("fill", -3.5, -H / 2 + 4, 7, H - 8, 1, 1)
    love.graphics.rectangle("fill", -W / 2 + 7, -3.5, W - 14, 7, 1, 1)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

return Medpack
