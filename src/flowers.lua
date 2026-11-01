-- Flower Gardens drawing (rules: src/world.lua): the gardens with their picket fences
-- (posts in the team colour; broken planks once a bulldozer came through), the flowers
-- (a few kinds made of shapes) on the ground and held up by a carrier, the flowers a team
-- delivered planted along the inside of its fence, the yellow toy bulldozer, the marks on
-- the minimap, the fence icon of the scoreboard and the mode icon (used by src/menu.lua).
local Arena = require("src.arena")

local Flowers = {}

local PICKET_GAP = 22  -- px between two pickets
local POST_EVERY = 4   -- every 4th picket is a post in the team colour
local PLANT_GAP  = 30  -- px between two flowers planted in a garden
local BLINK_TIME = 5   -- s: a bulldozer blinks this long before it rolls away
local DOZER_SCALE = 1.45 -- (drawn as a 76 x 68 px shape times this: a vehicle around the rowdy)
local WHITE = { 0.97, 0.96, 0.9 }
local WOOD  = { 0.6, 0.42, 0.25 }
local LEAF  = { 0.25, 0.62, 0.25 }
-- petals and middle of each kind: daisy, tulip, sunflower, cornflower
local KINDS = {
    { petals = { 1, 1, 1 },         middle = { 1, 0.85, 0.2 } },
    { petals = { 0.95, 0.25, 0.3 }, middle = { 1, 0.75, 0.3 } },
    { petals = { 1, 0.82, 0.15 },   middle = { 0.45, 0.28, 0.1 } },
    { petals = { 0.35, 0.55, 1 },   middle = { 1, 1, 1 } },
}

local heading = {} -- entity id -> the way its bulldozer faces (from how it moved)
local lastPos = {}

-- A flower seen from above, centred on x, y (s = size, about 14 * s px across)
function Flowers.drawBloom(kind, x, y, s, a, turn)
    local k = KINDS[kind] or KINDS[1]
    a, turn = a or 1, turn or 0
    love.graphics.setColor(LEAF[1], LEAF[2], LEAF[3], a)
    love.graphics.ellipse("fill", x - 7 * s, y + 6 * s, 6 * s, 3 * s)
    love.graphics.ellipse("fill", x + 7 * s, y + 5 * s, 6 * s, 3 * s)
    local p = k.petals
    for i = 0, 5 do
        local ang = turn + i / 6 * math.pi * 2
        love.graphics.setColor(0.15, 0.1, 0.1, 0.6 * a)
        love.graphics.circle("fill", x + math.cos(ang) * 5.5 * s, y + math.sin(ang) * 5.5 * s, 4.6 * s)
    end
    for i = 0, 5 do
        local ang = turn + i / 6 * math.pi * 2
        love.graphics.setColor(p[1], p[2], p[3], a)
        love.graphics.circle("fill", x + math.cos(ang) * 5.5 * s, y + math.sin(ang) * 5.5 * s, 4 * s)
    end
    local m = k.middle
    love.graphics.setColor(m[1], m[2], m[3], a)
    love.graphics.circle("fill", x, y, 3.5 * s)
end

-- A flower in the field: sways a little, a soft ring so it is easy to spot
function Flowers.drawFlower(f, now)
    local sway = math.sin(now * 2 + f.id) * 0.15
    love.graphics.setColor(0, 0, 0, 0.2)
    love.graphics.ellipse("fill", f.x, f.y + 10, 16, 6)
    love.graphics.setColor(1, 1, 1, 0.25 + 0.15 * math.sin(now * 3 + f.id))
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", f.x, f.y, 28)
    love.graphics.setLineWidth(1)
    Flowers.drawBloom(f.kind, f.x, f.y, 1.5, 1, sway)
    love.graphics.setColor(1, 1, 1, 1)
end

-- A carried flower: held up above the carrier's head
function Flowers.drawCarried(f, e, now)
    local bob = math.sin(now * 6) * 2
    Flowers.drawBloom(f.kind, e.x, e.y - e.radius - 30 + bob, 1.3, 1, math.sin(now * 3) * 0.2)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Points every `gap` px along the polyline pts (x, y, x, y, ...): { x, y, dx, dy }
local function along(pts, gap, offset)
    local list = {}
    local carry = offset or 0
    for i = 1, #pts - 3, 2 do
        local x1, y1, x2, y2 = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
        local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        local d = carry
        while d <= len do
            local k = d / len
            list[#list + 1] = { x1 + (x2 - x1) * k, y1 + (y2 - y1) * k, (x2 - x1) / len, (y2 - y1) / len }
            d = d + gap
        end
        carry = d - len
    end
    return list
end

-- The fence line moved `d` px into garden g (towards its middle)
local function inside(g, d)
    local f = g.fence
    local sx = g.cx < f[3] and -d or d
    local sy = g.cy < f[4] and -d or d
    return { f[1] + sx, f[2], f[3] + sx, f[4] + sy, f[5], f[6] + sy }
end

-- A garden: a light patch in the team colour, the flowers delivered planted along the
-- inside of the fence. color: the team's; planted: how many it delivered.
function Flowers.drawGarden(g, color, planted)
    love.graphics.setColor(color[1], color[2], color[3], 0.12)
    love.graphics.rectangle("fill", g.x1, g.y1, g.x2 - g.x1, g.y2 - g.y1)
    love.graphics.setColor(0.42, 0.3, 0.18, 0.55) -- the flower bed along the fence
    love.graphics.setLineWidth(26)
    love.graphics.line(inside(g, 22))
    love.graphics.setLineWidth(1)
    local spots = along(inside(g, 22), PLANT_GAP, PLANT_GAP / 2)
    for i = 1, math.min(planted or 0, #spots) do
        local s = spots[i]
        Flowers.drawBloom(i % 4 + 1, s[1], s[2], 0.9, 1, i)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- The picket fence of garden g: white pickets, two rails, posts in the team colour;
-- down = broken planks lying around (where a bulldozer came through)
function Flowers.drawFence(g, color, up)
    local pickets = along(g.fence, PICKET_GAP, 0)
    if not up then
        for i, p in ipairs(pickets) do
            local r = math.sin(i * 12.9898) * 43758.5453 % 1 -- (fixed "random" per plank)
            local ang = r * math.pi * 2
            local ox, oy = math.cos(ang * 3) * 10, math.sin(ang * 5) * 10
            love.graphics.push()
            love.graphics.translate(p[1] + ox, p[2] + oy)
            love.graphics.rotate(ang)
            love.graphics.setColor(0, 0, 0, 0.2)
            love.graphics.rectangle("fill", -9, -2, 18, 7, 2, 2)
            local c = (i % POST_EVERY == 0) and color or WHITE
            love.graphics.setColor(c[1] * 0.75, c[2] * 0.75, c[3] * 0.75, 0.85)
            love.graphics.rectangle("fill", -9, -4, 18 * (0.5 + r * 0.5), 6, 2, 2)
            love.graphics.pop()
        end
        love.graphics.setColor(1, 1, 1, 1)
        return
    end
    -- shadow, then the rails, then the pickets (standing: drawn a bit upwards)
    love.graphics.setColor(0, 0, 0, 0.22)
    love.graphics.setLineWidth(12)
    love.graphics.line(g.fence[1] + 4, g.fence[2] + 6, g.fence[3] + 4, g.fence[4] + 6, g.fence[5] + 4, g.fence[6] + 6)
    for _, h in ipairs({ 6, 14 }) do
        love.graphics.setLineWidth(5)
        love.graphics.setColor(WOOD)
        love.graphics.line(g.fence[1], g.fence[2] - h, g.fence[3], g.fence[4] - h, g.fence[5], g.fence[6] - h)
        love.graphics.setLineWidth(3)
        love.graphics.setColor(WHITE)
        love.graphics.line(g.fence[1], g.fence[2] - h, g.fence[3], g.fence[4] - h, g.fence[5], g.fence[6] - h)
    end
    love.graphics.setLineWidth(1)
    for i, p in ipairs(pickets) do
        local post = i % POST_EVERY == 1
        local c = post and color or WHITE
        local w, h = post and 6 or 4, post and 24 or 20
        local x, y = p[1], p[2]
        love.graphics.setColor(0.25, 0.18, 0.12, 1)
        love.graphics.polygon("fill", x - w - 1.5, y + 1.5, x + w + 1.5, y + 1.5, x + w + 1.5, y - h, x, y - h - w - 2, x - w - 1.5, y - h)
        love.graphics.setColor(c[1], c[2], c[3], 1)
        love.graphics.polygon("fill", x - w, y, x + w, y, x + w, y - h, x, y - h - w, x - w, y - h)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- The yellow toy bulldozer of a driver (drawn under its rowdy, who sits in it): tracks,
-- a body with a stripe in the team colour, the blade in front, little exhaust puffs.
-- It faces the way it moves; it blinks in its last seconds. now = world time.
function Flowers.drawDozer(e, color, now)
    local last = lastPos[e.id]
    if last then
        local dx, dy = e.x - last[1], e.y - last[2]
        if dx * dx + dy * dy > 0.5 then
            local target = math.atan2(dy, dx)
            local h = heading[e.id] or target
            local d = (target - h + math.pi) % (2 * math.pi) - math.pi
            heading[e.id] = h + d * 0.3
        end
    end
    lastPos[e.id] = { e.x, e.y }
    local h = heading[e.id] or e.aim or 0
    local left = e.driving and e.driving.expires and (e.driving.expires - now) or 99
    local a = 1
    if left < BLINK_TIME and math.floor(now * 6) % 2 == 0 then a = 0.45 end
    love.graphics.push()
    love.graphics.translate(e.x, e.y)
    love.graphics.rotate(h)
    love.graphics.scale(DOZER_SCALE)
    love.graphics.setColor(0, 0, 0, 0.25 * a)
    love.graphics.rectangle("fill", -36, -26, 76, 58, 10, 10)
    -- tracks (the treads roll)
    for _, side in ipairs({ -1, 1 }) do
        local ty = side < 0 and -30 or 18
        love.graphics.setColor(0.18, 0.18, 0.2, a)
        love.graphics.rectangle("fill", -34, ty, 64, 12, 6, 6)
        love.graphics.setColor(0.4, 0.4, 0.42, a)
        local roll = (now * 40) % 10
        for x = -30 + roll, 24, 10 do love.graphics.rectangle("fill", x, ty + 2, 3, 8) end
    end
    -- body + team stripe + cabin frame
    love.graphics.setColor(0.35, 0.25, 0.05, a)
    love.graphics.rectangle("fill", -31, -21, 58, 42, 8, 8)
    love.graphics.setColor(1, 0.8, 0.1, a)
    love.graphics.rectangle("fill", -29, -19, 54, 38, 7, 7)
    love.graphics.setColor(color[1], color[2], color[3], a)
    love.graphics.rectangle("fill", -29, -4, 54, 8)
    love.graphics.setColor(1, 0.92, 0.5, a)
    love.graphics.rectangle("fill", -25, -16, 20, 6, 3, 3)
    -- the blade with its arms
    love.graphics.setColor(0.35, 0.35, 0.38, a)
    love.graphics.rectangle("fill", 25, -14, 10, 4)
    love.graphics.rectangle("fill", 25, 10, 10, 4)
    love.graphics.setColor(0.2, 0.2, 0.22, a)
    love.graphics.polygon("fill", 34, -34, 44, -30, 44, 30, 34, 34)
    love.graphics.setColor(0.75, 0.77, 0.8, a)
    love.graphics.polygon("fill", 35, -32, 42, -29, 42, 29, 35, 32)
    -- exhaust pipe + puffs
    love.graphics.setColor(0.25, 0.25, 0.28, a)
    love.graphics.circle("fill", -22, -14, 4)
    for i = 0, 2 do
        local k = (now * 1.5 + i / 3) % 1
        love.graphics.setColor(0.85, 0.85, 0.85, (1 - k) * 0.6 * a)
        love.graphics.circle("fill", -24 - k * 26, -16 - k * 8, 4 + k * 6)
    end
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

-- On the minimap (x0, y0 = its corner, s = its scale): the gardens (filled while the
-- fence stands), the flowers and the bulldozers. colorOf(team) = colour of a team.
function Flowers.drawMinimap(world, x0, y0, s, colorOf)
    local fg = world.flowerGame
    if not fg then return end
    for t, g in ipairs(Arena.gardens or {}) do
        local c = colorOf(t)
        local x, y, w, h = x0 + g.x1 * s, y0 + g.y1 * s, (g.x2 - g.x1) * s, (g.y2 - g.y1) * s
        love.graphics.setColor(c[1], c[2], c[3], fg.fences[t] and 0.55 or 0.15)
        love.graphics.rectangle("fill", x, y, w, h)
        if fg.fences[t] then
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.setLineWidth(1.5)
            local f = g.fence
            love.graphics.line(x0 + f[1] * s, y0 + f[2] * s, x0 + f[3] * s, y0 + f[4] * s, x0 + f[5] * s, y0 + f[6] * s)
            love.graphics.setLineWidth(1)
        end
    end
    for _, f in ipairs(fg.flowers or {}) do
        if not f.carrier then
            love.graphics.setColor(0, 0, 0, 0.6)
            love.graphics.circle("fill", x0 + f.x * s, y0 + f.y * s, 3)
            love.graphics.setColor(1, 0.55, 0.75, 1)
            love.graphics.circle("fill", x0 + f.x * s, y0 + f.y * s, 2.2)
        end
    end
    for _, e in ipairs(world.entities) do
        if e.driving and not e.dead then
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.rectangle("fill", x0 + e.x * s - 5, y0 + e.y * s - 4, 10, 8, 2, 2)
            love.graphics.setColor(1, 0.8, 0.1, 1)
            love.graphics.rectangle("fill", x0 + e.x * s - 4, y0 + e.y * s - 3, 8, 6, 2, 2)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- A small fence (scoreboard): three pickets; down = fallen over, grey
function Flowers.drawFenceIcon(cx, cy, s, up)
    for i = -1, 1 do
        local x = cx + i * 6 * s
        if up then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.polygon("fill", x - 2 * s, cy + 6 * s, x + 2 * s, cy + 6 * s, x + 2 * s, cy - 4 * s,
                x, cy - 7 * s, x - 2 * s, cy - 4 * s)
        else
            love.graphics.setColor(0.6, 0.6, 0.6, 0.9)
            love.graphics.push()
            love.graphics.translate(x, cy + 4 * s)
            love.graphics.rotate(0.5 + i * 0.6)
            love.graphics.rectangle("fill", -5 * s, -1.5 * s, 10 * s, 3 * s)
            love.graphics.pop()
        end
    end
    if up then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", cx - 9 * s, cy - 1 * s, 18 * s, 2 * s)
        love.graphics.rectangle("fill", cx - 9 * s, cy + 3 * s, 18 * s, 2 * s)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Mode icon (lobby mode card): a flower over a bit of picket fence
function Flowers.drawIcon(cx, cy, s)
    love.graphics.setColor(1, 1, 1, 0.95)
    for i = -2, 2 do
        local x = cx + i * s * 0.32
        love.graphics.polygon("fill", x - s * 0.1, cy + s * 0.75, x + s * 0.1, cy + s * 0.75, x + s * 0.1, cy + s * 0.3,
            x, cy + s * 0.18, x - s * 0.1, cy + s * 0.3)
    end
    love.graphics.rectangle("fill", cx - s * 0.75, cy + s * 0.45, s * 1.5, s * 0.08)
    Flowers.drawBloom(2, cx, cy - s * 0.2, s * 0.06, 1, 0.3)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Forget the bulldozers' headings (a new game)
function Flowers.reset()
    heading, lastPos = {}, {}
end

return Flowers
