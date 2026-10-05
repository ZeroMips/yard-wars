-- Drawing of the Yard Pass cosmetics that aren't rowdy art (src/cosmetics.lua): badges,
-- lobby pedestals, and the reward icons of the pass screen (coins, rowdies, skins,
-- trails, pedestals, badges, titles). Comic style like src/loot.lua: dark outlines,
-- flat colours, a highlight. Bullet trails are drawn in src/bullet.lua.
local Assets    = require("src.assets")
local Bullet    = require("src.bullet")
local Cosmetics = require("src.cosmetics")
local Loot      = require("src.loot")
local Rowdies   = require("src.rowdies")

local Decor = {}

local OUTLINE = { 0.05, 0.05, 0.1 }

-- Medal with an icon: centre x, y, radius r
function Decor.drawBadge(id, x, y, r)
    local b = Cosmetics.get(id, "badge")
    if not b then return end
    local c = b.color
    love.graphics.setColor(OUTLINE)
    love.graphics.circle("fill", x, y, r + 2.5)
    love.graphics.setColor(1, 0.8, 0.2) -- gold rim
    love.graphics.circle("fill", x, y, r)
    love.graphics.setColor(c)
    love.graphics.circle("fill", x, y, r * 0.78)
    love.graphics.setColor(1, 1, 1, 0.95)
    if b.icon == "flower" then
        for i = 0, 4 do
            local a = i / 5 * math.pi * 2 - math.pi / 2
            love.graphics.circle("fill", x + math.cos(a) * r * 0.33, y + math.sin(a) * r * 0.33, r * 0.22)
        end
        love.graphics.setColor(1, 0.85, 0.2)
        love.graphics.circle("fill", x, y, r * 0.2)
    elseif b.icon == "star" then
        local pts = {}
        for i = 0, 9 do
            local a = i / 10 * math.pi * 2 - math.pi / 2
            local d = (i % 2 == 0) and r * 0.6 or r * 0.26
            pts[#pts + 1] = x + math.cos(a) * d
            pts[#pts + 1] = y + math.sin(a) * d
        end
        for i = 1, 10 do -- star as triangles from the centre (polygon needs convex)
            local j = i % 10 + 1
            love.graphics.polygon("fill", x, y, pts[2 * i - 1], pts[2 * i], pts[2 * j - 1], pts[2 * j])
        end
    else -- shield
        love.graphics.polygon("fill", x - r * 0.42, y - r * 0.4, x + r * 0.42, y - r * 0.4,
            x + r * 0.38, y + r * 0.1, x, y + r * 0.5, x - r * 0.38, y + r * 0.1)
    end
    love.graphics.setColor(1, 1, 1, 0.35) -- shine
    love.graphics.ellipse("fill", x - r * 0.35, y - r * 0.45, r * 0.25, r * 0.13)
    love.graphics.setColor(1, 1, 1)
end

-- Lobby pedestal: centre cx, top ellipse at py, size factor k (1 = lobby size).
-- Returns false if the id isn't a pedestal (then the default one is drawn).
function Decor.drawPedestal(id, cx, py, k, t)
    local p = Cosmetics.get(id, "pedestal")
    if not p then return false end
    t = t or 0
    if p.style == "flowerpot" then
        -- terracotta pot rim with soil, flowers all around
        love.graphics.setColor(OUTLINE[1], OUTLINE[2], OUTLINE[3], 0.85)
        love.graphics.ellipse("fill", cx, py + 14 * k, 166 * k, 52 * k)
        love.graphics.setColor(0.62, 0.3, 0.17)
        love.graphics.ellipse("fill", cx, py + 10 * k, 160 * k, 46 * k)
        love.graphics.setColor(0.82, 0.45, 0.26)
        love.graphics.ellipse("fill", cx, py, 160 * k, 44 * k)
        love.graphics.setColor(0.33, 0.22, 0.14) -- soil
        love.graphics.ellipse("fill", cx, py, 138 * k, 34 * k)
        love.graphics.setColor(1, 1, 1, 0.18)
        love.graphics.ellipse("fill", cx - 70 * k, py - 26 * k, 50 * k, 7 * k)
        local colors = { { 0.95, 0.4, 0.55 }, { 1, 0.85, 0.25 }, { 0.65, 0.45, 0.95 }, { 1, 0.55, 0.3 } }
        for i = 0, 9 do
            local a = i / 10 * math.pi * 2 + 0.3
            local fx, fy = cx + math.cos(a) * 148 * k, py + math.sin(a) * 40 * k
            local sway = math.sin(t * 2 + i) * 3 * k
            love.graphics.setColor(0.2, 0.55, 0.2) -- leaf
            love.graphics.ellipse("fill", fx - 7 * k, fy - 4 * k, 8 * k, 4 * k)
            love.graphics.setColor(OUTLINE)
            love.graphics.circle("fill", fx + sway, fy - 10 * k, 11 * k)
            local c = colors[i % #colors + 1]
            love.graphics.setColor(c)
            for j = 0, 4 do
                local b = j / 5 * math.pi * 2
                love.graphics.circle("fill", fx + sway + math.cos(b) * 5 * k, fy - 10 * k + math.sin(b) * 5 * k, 5 * k)
            end
            love.graphics.setColor(1, 0.9, 0.3)
            love.graphics.circle("fill", fx + sway, fy - 10 * k, 3.5 * k)
        end
    end
    love.graphics.setColor(1, 1, 1)
    return true
end

-- A title on a small ribbon, centred at x, y; font given. Returns the width.
function Decor.drawTitle(id, font, x, y, alpha)
    local c = Cosmetics.get(id, "title")
    if not c then return 0 end
    local text = c.name
    local w, h = font:getWidth(text) + 28, font:getHeight() + 8
    love.graphics.setColor(OUTLINE[1], OUTLINE[2], OUTLINE[3], 0.8 * (alpha or 1))
    love.graphics.rectangle("fill", x - w / 2 - 2, y - h / 2 - 2, w + 4, h + 4, 6, 6)
    love.graphics.setColor(0.55, 0.18, 0.5, alpha or 1)
    love.graphics.rectangle("fill", x - w / 2, y - h / 2, w, h, 5, 5)
    love.graphics.setFont(font)
    love.graphics.setColor(1, 0.9, 0.55, alpha or 1)
    love.graphics.print(text, x - w / 2 + 14, y - h / 2 + 4)
    love.graphics.setColor(1, 1, 1)
    return w
end

local function rowdyByName(name)
    for _, def in ipairs(Rowdies) do
        if def.name == name then return def end
    end
end

-- The picture of a pass reward (src/seasons.lua) fitting a box of `size` around x, y
function Decor.drawReward(r, x, y, size, font, dim)
    local tint = dim and { 0.35, 0.35, 0.4 } or nil
    if r.coins then
        local n = math.min(3, math.ceil(r.coins / 15))
        for i = n, 1, -1 do
            Loot.drawCoin(x + (i - (n + 1) / 2) * size * 0.16, y - (i - 1) * size * 0.06, size * 0.24)
        end
        return
    end
    if r.rowdy then
        local def = rowdyByName(r.rowdy)
        if def then Assets.drawPortrait(def, x, y, size * 0.95, 0, tint) end
        return
    end
    local c = Cosmetics.get(r.cosmetic)
    if c.kind == "skin" then
        Assets.drawPortrait(rowdyByName(c.rowdy), x, y, size * 0.95, 0, tint, c.id)
    elseif c.kind == "badge" then
        Decor.drawBadge(c.id, x, y, size * 0.32)
    elseif c.kind == "pedestal" then
        Decor.drawPedestal(c.id, x, y + size * 0.1, size / 380, love.timer.getTime())
    elseif c.kind == "trail" then -- a bullet with its trail, flying to the right
        local b = { x = x + size * 0.22, y = y, vx = 600, vy = 0 }
        love.graphics.push()
        love.graphics.translate(x, y)
        love.graphics.scale(size / 45)
        love.graphics.translate(-x, -y)
        Bullet.drawTrail(b, c, 6)
        love.graphics.setColor(0.1, 0.1, 0.1)
        love.graphics.circle("fill", b.x, b.y, 8)
        love.graphics.setColor(c.color)
        love.graphics.circle("fill", b.x, b.y, 6)
        love.graphics.pop()
    elseif c.kind == "title" then -- a scroll
        love.graphics.setColor(OUTLINE)
        love.graphics.rectangle("fill", x - size * 0.4, y - size * 0.22, size * 0.8, size * 0.44, 6, 6)
        love.graphics.setColor(0.95, 0.86, 0.62)
        love.graphics.rectangle("fill", x - size * 0.37, y - size * 0.19, size * 0.74, size * 0.38, 4, 4)
        love.graphics.setColor(0.55, 0.18, 0.5)
        for i = -1, 1 do
            love.graphics.rectangle("fill", x - size * 0.25, y + i * size * 0.09 - 2, size * 0.5, 4, 2, 2)
        end
    end
    love.graphics.setColor(1, 1, 1)
end

return Decor
