-- Drawing of loot boxes and coins (the logic is in src/world.lua), plus the coin icon
-- and coin counter used on the menu screens. Comic style like the medpacks: thick
-- dark outlines, flat colors, a highlight.
local World = require("src.world")

local Loot = {}

local OUTLINE = { 0.12, 0.08, 0.06, 1 }
local GOLD, GOLD_DARK = { 1, 0.8, 0.15 }, { 0.8, 0.5, 0.05 }
local BLINK = 3 -- seconds before a coin disappears when it starts blinking

-- A coin seen from the front (also the UI icon): centre x, y, radius r; squash 0..1
-- narrows it (spinning)
function Loot.drawCoin(x, y, r, squash)
    local sx = squash or 1
    love.graphics.setColor(OUTLINE)
    love.graphics.ellipse("fill", x, y, r * sx + 2.5, r + 2.5)
    love.graphics.setColor(GOLD_DARK)
    love.graphics.ellipse("fill", x, y, r * sx, r)
    love.graphics.setColor(GOLD)
    love.graphics.ellipse("fill", x, y - r * 0.08, r * 0.82 * sx, r * 0.82)
    love.graphics.setColor(GOLD_DARK)
    love.graphics.setLineWidth(math.max(1, r * 0.14))
    love.graphics.ellipse("line", x, y - r * 0.08, r * 0.5 * sx, r * 0.5)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 0.85, 0.85) -- shine
    love.graphics.ellipse("fill", x - r * 0.35 * sx, y - r * 0.4, r * 0.18 * sx, r * 0.12)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Coin icon + amount on a dark pill, left edge x, vertical centre y (HUD units).
-- Returns the width.
function Loot.drawCounter(amount, font, x, y, h)
    h = h or 40
    local text = tostring(amount)
    local w = h + font:getWidth(text) + h * 0.5
    love.graphics.setColor(0.05, 0.05, 0.1, 0.75)
    love.graphics.rectangle("fill", x, y - h / 2, w, h, h / 2, h / 2)
    Loot.drawCoin(x + h / 2, y, h * 0.32)
    love.graphics.setFont(font)
    love.graphics.setColor(1, 0.88, 0.35)
    love.graphics.print(text, x + h, y - font:getHeight() / 2)
    love.graphics.setColor(1, 1, 1, 1)
    return w
end

-- Padlock (for rowdies not bought yet), centre x, y, size factor k
function Loot.drawLock(x, y, k)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(k)
    love.graphics.setColor(0.05, 0.05, 0.1)
    love.graphics.setLineWidth(14)
    love.graphics.arc("line", "open", 0, -10, 20, math.pi, 2 * math.pi)
    love.graphics.rectangle("fill", -32, -14, 64, 52, 8, 8)
    love.graphics.setColor(0.85, 0.85, 0.9)
    love.graphics.setLineWidth(7)
    love.graphics.arc("line", "open", 0, -10, 20, math.pi, 2 * math.pi)
    love.graphics.setColor(1, 0.78, 0.15)
    love.graphics.rectangle("fill", -27, -9, 54, 42, 6, 6)
    love.graphics.setColor(0.05, 0.05, 0.1)
    love.graphics.circle("fill", 0, 6, 6)
    love.graphics.rectangle("fill", -2.5, 6, 5, 14)
    love.graphics.setLineWidth(1)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

-- A treasure chest: dark red wood, gold bands and lock. Pops in when it appears,
-- shakes and flashes when hit, HP bar once damaged.
function Loot.drawBox(box, time)
    local h = World.BOX_HALF
    local age = time - box.born
    local pop = 1
    if age < 0.35 then
        local k = age / 0.35
        pop = k + math.sin(k * math.pi) * 0.3
    end
    local since = box.hitAt and (time - box.hitAt) or 1
    local shake = since < 0.15 and math.sin(since * 120) * 3 * (1 - since / 0.15) or 0

    love.graphics.push()
    love.graphics.translate(box.x + shake, box.y)
    love.graphics.setColor(0, 0, 0, 0.3) -- shadow
    love.graphics.ellipse("fill", 2, h * 0.9, h * 1.1 * pop, h * 0.35 * pop)
    love.graphics.scale(pop)

    love.graphics.setColor(OUTLINE)
    love.graphics.rectangle("fill", -h - 4, -h - 4, 2 * h + 8, 2 * h + 8, 8, 8)
    love.graphics.setColor(0.55, 0.22, 0.12) -- body
    love.graphics.rectangle("fill", -h, -h, 2 * h, 2 * h, 5, 5)
    love.graphics.setColor(0.72, 0.32, 0.17) -- lid (top part, lighter)
    love.graphics.rectangle("fill", -h, -h, 2 * h, h * 0.8, 5, 5)
    love.graphics.setColor(1, 1, 1, 0.18) -- highlight on the lid
    love.graphics.rectangle("fill", -h + 4, -h + 3, 2 * h - 8, h * 0.25, 3, 3)
    love.graphics.setColor(OUTLINE) -- lid edge
    love.graphics.rectangle("fill", -h, -h * 0.25, 2 * h, 3)
    -- gold bands and corners
    love.graphics.setColor(GOLD)
    love.graphics.rectangle("fill", -h * 0.62, -h, h * 0.24, 2 * h)
    love.graphics.rectangle("fill", h * 0.38, -h, h * 0.24, 2 * h)
    love.graphics.setColor(GOLD_DARK)
    love.graphics.rectangle("fill", -h * 0.62, h * 0.6, h * 0.24, h * 0.4)
    love.graphics.rectangle("fill", h * 0.38, h * 0.6, h * 0.24, h * 0.4)
    -- lock
    love.graphics.setColor(OUTLINE)
    love.graphics.rectangle("fill", -h * 0.3, -h * 0.45, h * 0.6, h * 0.62, 3, 3)
    love.graphics.setColor(GOLD)
    love.graphics.rectangle("fill", -h * 0.22, -h * 0.37, h * 0.44, h * 0.46, 2, 2)
    love.graphics.setColor(OUTLINE)
    love.graphics.circle("fill", 0, -h * 0.18, h * 0.08)
    if since < 0.08 then -- white hit flash
        love.graphics.setColor(1, 1, 1, 0.6)
        love.graphics.rectangle("fill", -h, -h, 2 * h, 2 * h, 5, 5)
    end
    love.graphics.pop()

    if box.hp < World.BOX_HP then
        local w = 2 * h + 8
        local x, y = box.x - w / 2, box.y - h - 18
        love.graphics.setColor(OUTLINE)
        love.graphics.rectangle("fill", x - 2, y - 2, w + 4, 10, 3, 3)
        love.graphics.setColor(GOLD)
        love.graphics.rectangle("fill", x, y, w * math.max(0, box.hp) / World.BOX_HP, 6, 2, 2)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- A coin on the ground: flies out of the box in an arc, then spins and bobs;
-- blinks during its last seconds
function Loot.drawGroundCoin(c, time)
    local left = c.expires - time
    if left < BLINK and math.floor(left * 6) % 2 == 1 then return end
    local x, y, lift = c.x, c.y, 0
    local k = (time - c.born) / 0.35
    if k < 1 then
        x, y = c.ox + (c.x - c.ox) * k, c.oy + (c.y - c.oy) * k
        lift = math.sin(k * math.pi) * 28
    else
        lift = 3 + math.sin(time * 3 + c.x * 0.01) * 2
    end
    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.ellipse("fill", x, y + 8, 9, 3.5)
    Loot.drawCoin(x, y - lift, 9, 0.2 + 0.8 * math.abs(math.cos(time * 3 + c.id)))
end

return Loot
