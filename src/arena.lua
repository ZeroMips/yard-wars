-- Arena: grass, walls (solid), crates (solid), bushes (hiding spots).
-- Layout is given in tile units (1 tile = 64px) for the LEFT half only;
-- it is mirrored to the right half automatically, so the map is fair.
-- Walls and bushes are built from 2x2-tile art blocks: w and h must be even.
local Assets = require("src.assets")

local Arena = {}
local TILE = 64

Arena.cols, Arena.rows = 40, 24
Arena.width, Arena.height = Arena.cols * TILE, Arena.rows * TILE
Arena.spawn      = { x = 2.5 * TILE,  y = 12 * TILE }
Arena.enemySpawn = { x = 37.5 * TILE, y = 12 * TILE }

local walls, bushes, crates = {}, {}, {}

-- Objects on the left half (mirrored) ...
local leftWalls  = { {x=6, y=4, w=2, h=4}, {x=6, y=16, w=2, h=4}, {x=11, y=10, w=2, h=4} }
local leftBushes = { {x=9, y=1, w=4, h=2}, {x=3, y=17, w=2, h=4}, {x=13, y=19, w=4, h=4},
                     {x=3, y=3, w=2, h=2} }
local leftCrates = { {x=4, y=8}, {x=4, y=15}, {x=8, y=12}, {x=15, y=7}, {x=15, y=16},
                     {x=9, y=20}, {x=16, y=11}, {x=16, y=12} }
-- ... and objects in the middle (must be symmetric: x = (cols - w) / 2)
local centerWalls  = { {x=18, y=10, w=4, h=4} }
local centerBushes = { {x=18, y=4, w=4, h=2}, {x=18, y=18, w=4, h=2} }

local function mirrored(list, out)
    for _, o in ipairs(list) do
        out[#out + 1] = o
        out[#out + 1] = { x = Arena.cols - o.x - (o.w or 1), y = o.y, w = o.w, h = o.h }
    end
end
mirrored(leftWalls, walls);   mirrored(leftBushes, bushes);   mirrored(leftCrates, crates)
for _, o in ipairs(centerWalls)  do walls[#walls + 1] = o end
for _, o in ipairs(centerBushes) do bushes[#bushes + 1] = o end

Arena.walls, Arena.bushes = walls, bushes -- exposed for the minimap

-- Solid rectangles in pixels (used for collision)
local solids = {}
for _, w in ipairs(walls) do
    solids[#solids + 1] = { x = w.x * TILE, y = w.y * TILE, w = w.w * TILE, h = w.h * TILE }
end
for _, c in ipairs(crates) do
    solids[#solids + 1] = { x = c.x * TILE, y = c.y * TILE, w = TILE, h = TILE }
end

-- Push a circle out of all solids and keep it inside the arena.
function Arena.resolveCircle(x, y, r)
    for _, s in ipairs(solids) do
        local cx = math.max(s.x, math.min(x, s.x + s.w))
        local cy = math.max(s.y, math.min(y, s.y + s.h))
        local dx, dy = x - cx, y - cy
        local d2 = dx * dx + dy * dy
        if d2 < r * r then
            if d2 > 0 then
                local d = math.sqrt(d2)
                x = x + dx / d * (r - d)
                y = y + dy / d * (r - d)
            else -- center is inside the rectangle: leave via the nearest side
                local left, right = x - s.x, s.x + s.w - x
                local up, down = y - s.y, s.y + s.h - y
                local m = math.min(left, right, up, down)
                if m == left then x = s.x - r
                elseif m == right then x = s.x + s.w + r
                elseif m == up then y = s.y - r
                else y = s.y + s.h + r end
            end
        end
    end
    x = math.max(r, math.min(Arena.width - r, x))
    y = math.max(r, math.min(Arena.height - r, y))
    return x, y
end

-- True if a circle touches a solid or leaves the arena (used for bullets).
function Arena.hitsSolid(x, y, r)
    if x < 0 or y < 0 or x > Arena.width or y > Arena.height then return true end
    for _, s in ipairs(solids) do
        local cx = math.max(s.x, math.min(x, s.x + s.w))
        local cy = math.max(s.y, math.min(y, s.y + s.h))
        local dx, dy = x - cx, y - cy
        if dx * dx + dy * dy < r * r then return true end
    end
    return false
end

function Arena.inBush(x, y)
    for _, b in ipairs(bushes) do
        if x >= b.x * TILE and x <= (b.x + b.w) * TILE
            and y >= b.y * TILE and y <= (b.y + b.h) * TILE then
            return true
        end
    end
    return false
end

-- True if nothing solid lies on the straight line between two points.
function Arena.hasLineOfSight(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local steps = math.ceil(math.sqrt(dx * dx + dy * dy) / 8)
    for i = 1, steps - 1 do
        local t = i / steps
        if Arena.hitsSolid(x1 + dx * t, y1 + dy * t, 3) then return false end
    end
    return true
end

-- Distance a projectile of the given radius can travel from (x, y) in direction
-- `angle` before hitting a solid, capped at maxDist.
function Arena.raycast(x, y, angle, maxDist, radius)
    local dx, dy = math.cos(angle), math.sin(angle)
    local d = 0
    while d < maxDist do
        local nd = math.min(d + 8, maxDist)
        if Arena.hitsSolid(x + dx * nd, y + dy * nd, radius) then
            local lo, hi = d, nd            -- refine the hit distance
            for _ = 1, 4 do
                local mid = (lo + hi) / 2
                if Arena.hitsSolid(x + dx * mid, y + dy * mid, radius) then hi = mid else lo = mid end
            end
            return lo
        end
        d = nd
    end
    return maxDist
end

-- A random free spot. With cx, cy, radius: near that point (clamped to the arena).
function Arena.randomOpenPoint(cx, cy, radius)
    for _ = 1, 30 do
        local x, y
        if cx then
            x = cx + (math.random() * 2 - 1) * radius
            y = cy + (math.random() * 2 - 1) * radius
        else
            x = 64 + math.random() * (Arena.width - 128)
            y = 64 + math.random() * (Arena.height - 128)
        end
        x = math.max(64, math.min(Arena.width - 64, x))
        y = math.max(64, math.min(Arena.height - 64, y))
        if not Arena.hitsSolid(x, y, 24) then return x, y end
    end
    return Arena.spawn.x, Arena.spawn.y
end

-- One SpriteBatch holds the whole grass floor (built once, drawn in one call)
local grassBatch
local function buildGrass()
    grassBatch = love.graphics.newSpriteBatch(Assets.tiles, Arena.cols * Arena.rows)
    for gx = 0, Arena.cols - 1 do
        for gy = 0, Arena.rows - 1 do
            grassBatch:add(Assets.quads.grass, gx * TILE, gy * TILE)
        end
    end
end

-- Ground, walls and crates: drawn below the characters.
function Arena.drawBelow()
    if not grassBatch then buildGrass() end
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(grassBatch)

    for _, w in ipairs(walls) do
        for bx = 0, w.w / 2 - 1 do
            for by = 0, w.h / 2 - 1 do
                love.graphics.draw(Assets.tiles, Assets.quads.wall,
                    (w.x + bx * 2) * TILE, (w.y + by * 2) * TILE)
            end
        end
    end
    for _, c in ipairs(crates) do
        love.graphics.draw(Assets.tiles, Assets.quads.crate, c.x * TILE, c.y * TILE)
    end

    -- Arena border
    love.graphics.setColor(0.05, 0.15, 0.08, 1)
    love.graphics.setLineWidth(8)
    love.graphics.rectangle("line", -4, -4, Arena.width + 8, Arena.height + 8)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1)
end

-- Bushes: drawn above the characters. Semi-transparent while the given
-- character stands inside one, so you can still see yourself.
function Arena.drawBushes(hero)
    local hidden = hero and Arena.inBush(hero.x, hero.y)
    love.graphics.setColor(1, 1, 1, hidden and 0.55 or 1)
    for _, b in ipairs(bushes) do
        for bx = 0, b.w / 2 - 1 do
            for by = 0, b.h / 2 - 1 do
                love.graphics.draw(Assets.tiles, Assets.quads.bush,
                    (b.x + bx * 2) * TILE, (b.y + by * 2) * TILE)
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return Arena
