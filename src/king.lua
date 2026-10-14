-- King of the Yard drawing (rules: src/world.lua): the heart beacons a knocked-out
-- rowdy leaves, the fog outside the clear circle and both on the minimap. The fog is a
-- soft grey cloud (CHARTER.md: no poison look), the beacon a heart (no tombstone).
local King = {}

local FOG_COLOR  = { 0.78, 0.8, 0.84 }
local FOG_ALPHA  = 0.55
local FOG_EDGE   = 90   -- px: the fog thickens over this width at the edge
local SEGMENTS   = 96
local BLINK_TIME = 4    -- s: a beacon blinks this long before it goes

local fogMesh

-- Points of a heart curve around cx, cy (s = scale; about 32 * s wide)
function King.heartPoints(cx, cy, s)
    local pts = {}
    for i = 0, 23 do
        local t = i / 24 * math.pi * 2
        local x = 16 * math.sin(t) ^ 3
        local y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
        pts[#pts + 1] = cx + x * s
        pts[#pts + 1] = cy + y * s
    end
    return pts
end

-- A filled heart with an outline (colour c, alpha a)
function King.drawHeart(cx, cy, s, c, a)
    local pts = King.heartPoints(cx, cy, s)
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
    love.graphics.polygon("fill", pts)
    love.graphics.setColor(1, 1, 1, 0.9 * (a or 1))
    love.graphics.setLineWidth(math.max(1.5, s * 1.5))
    love.graphics.polygon("line", pts)
    love.graphics.setLineWidth(1)
end

-- A beacon in the world: a ring in the team colour, a pulsing heart, a progress ring
-- while a team mate stands on it; it blinks in its last seconds. now = world time.
function King.drawBeacon(b, now, color)
    local left = (b.expires or now) - now
    local a = 1
    if left < BLINK_TIME and math.floor(now * 6) % 2 == 0 then a = 0.35 end
    local pulse = 1 + 0.12 * math.sin(now * 5)
    local x, y = b.x, b.y
    love.graphics.setColor(0, 0, 0, 0.25 * a)
    love.graphics.ellipse("fill", x, y + 10, 30, 12)
    love.graphics.setColor(color[1], color[2], color[3], 0.25 * a)
    love.graphics.circle("fill", x, y, 40)
    love.graphics.setColor(color[1], color[2], color[3], 0.9 * a)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", x, y, 40)
    love.graphics.setLineWidth(1)
    King.drawHeart(x, y - 4 - 3 * math.sin(now * 3), 1.15 * pulse, { 0.95, 0.25, 0.35 }, a)
    local k = math.min(1, (b.progress or 0) / 2) -- (World.REVIVE_TIME)
    if k > 0 then
        love.graphics.setColor(0.5, 1, 0.5, 1)
        love.graphics.setLineWidth(6)
        love.graphics.arc("line", "open", x, y, 48, -math.pi / 2, -math.pi / 2 + k * math.pi * 2)
        love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- The fog: grey outside the clear circle (a ring mesh out to far beyond the map),
-- thickening over FOG_EDGE at its edge, with a few slowly drifting cloud puffs on it.
-- t = love.timer time (for the drift).
function King.drawFog(zone, t)
    if not zone or not zone.r then return end
    if not fogMesh then
        fogMesh = love.graphics.newMesh(SEGMENTS * 12, "triangles", "stream")
    end
    local r, far = math.max(0, zone.r), math.max(0, zone.r) + 6000
    local c = FOG_COLOR
    local verts = {}
    local function v(radius, a, alpha)
        verts[#verts + 1] = { zone.x + math.cos(a) * radius, zone.y + math.sin(a) * radius,
            0, 0, c[1], c[2], c[3], alpha }
    end
    -- two rings of quads: edge (r -> r + FOG_EDGE, alpha 0 -> full) and the rest
    for i = 0, SEGMENTS - 1 do
        local a1, a2 = i / SEGMENTS * math.pi * 2, (i + 1) / SEGMENTS * math.pi * 2
        for _, ring in ipairs({ { r, r + FOG_EDGE, 0, FOG_ALPHA }, { r + FOG_EDGE, far, FOG_ALPHA, FOG_ALPHA } }) do
            local i1, o1, ia, oa = ring[1], ring[2], ring[3], ring[4]
            v(i1, a1, ia); v(o1, a1, oa); v(o1, a2, oa)
            v(i1, a1, ia); v(o1, a2, oa); v(i1, a2, ia)
        end
    end
    fogMesh:setVertices(verts)
    fogMesh:setDrawRange(1, #verts)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(fogMesh)
    if r <= 0 then return end
    -- cloud puffs along the edge
    local n = math.min(120, math.max(12, math.floor(r * math.pi * 2 / 110)))
    for i = 1, n do
        local a = i / n * math.pi * 2 + t * 0.03 + math.sin(i * 1.7) * 0.02
        local d = r + 30 + 14 * math.sin(t * 0.7 + i)
        local size = 34 + 10 * math.sin(i * 2.3 + t * 0.5)
        love.graphics.setColor(c[1] + 0.08, c[2] + 0.08, c[3] + 0.08, 0.35)
        love.graphics.circle("fill", zone.x + math.cos(a) * d, zone.y + math.sin(a) * d, size)
    end
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", zone.x, zone.y, r, 128)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

-- On the minimap (x0, y0 = its corner, s = its scale, w, h = its size): the clear
-- circle and the beacons. ui = HUD scale (the scissor works in screen pixels).
-- colorOf(team) = colour of a team.
function King.drawMinimap(world, x0, y0, s, w, h, ui, colorOf)
    local z = world.zone
    if z and z.r then
        love.graphics.setScissor(x0 * ui, y0 * ui, w * ui, h * ui)
        love.graphics.setColor(1, 1, 1, 0.85)
        love.graphics.setLineWidth(1.5)
        love.graphics.circle("line", x0 + z.x * s, y0 + z.y * s, math.max(0, z.r) * s, 64)
        love.graphics.setLineWidth(1)
        love.graphics.setScissor()
    end
    for _, b in ipairs(world.beacons or {}) do
        King.drawHeart(x0 + b.x * s, y0 + b.y * s, 0.28, colorOf(b.team), 1)
    end
end

return King
