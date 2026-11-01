-- Arena: grass, walls (solid), crates (solid), bushes (hiding spots).
-- Layout is given in tile units (1 tile = 64px) for the LEFT half only;
-- it is mirrored to the right half automatically, so the map is fair. (The big
-- "kingdom" layout gives the top-left quarter and is mirrored on both axes.)
-- Walls and bushes are built from 2x2-tile art blocks: w and h must be even.
local Assets = require("src.assets")

local Arena = {}
local TILE = 64

Arena.cols, Arena.rows = 40, 24
Arena.width, Arena.height = Arena.cols * TILE, Arena.rows * TILE
Arena.spawn      = { x = 2.5 * TILE,  y = 12 * TILE }
Arena.enemySpawn = { x = 37.5 * TILE, y = 12 * TILE }

local walls, bushes, crates, solids = {}, {}, {}, {}

-- Layouts: objects on the left half (mirrored) and in the middle (must be symmetric:
-- x = (cols - w) / 2). "yard": the normal arena; "pitch": Yardball (src/world.lua) - no
-- wall in the middle (the ball starts there), nothing in front of the goals, cover on
-- the flanks, an open lane through the middle; "kingdom": King of the Yard - a big map
-- (cols x rows), objects for the top-left quarter (mirror4: mirrored on both axes, so
-- the four corners where the teams start are equal), an open middle; "hideout": Hide and
-- seek - as big as "kingdom" and mirrored the same way, full of bushes, hedge rows
-- (long bushes), sheds (walls) and crates that break up the long sight lines, the
-- picture frame in the open middle and one picture piece per quarter; "gardens": Flower
-- Gardens - as big as "kingdom" and mirrored the same way, a fenced garden in every
-- corner (the teams' spawn), cover on the way to the open flower field in the middle.
local LAYOUTS = {
    yard = {
        walls  = { {x=6, y=4, w=2, h=4}, {x=6, y=16, w=2, h=4}, {x=11, y=10, w=2, h=4} },
        bushes = { {x=9, y=1, w=4, h=2}, {x=3, y=17, w=2, h=4}, {x=13, y=19, w=4, h=4},
                   {x=3, y=3, w=2, h=2} },
        crates = { {x=4, y=8}, {x=4, y=15}, {x=8, y=12}, {x=15, y=7}, {x=15, y=16},
                   {x=9, y=20}, {x=16, y=11}, {x=16, y=12} },
        centerWalls  = { {x=18, y=10, w=4, h=4} },
        centerBushes = { {x=18, y=4, w=4, h=2}, {x=18, y=18, w=4, h=2} },
    },
    pitch = {
        walls  = { {x=7, y=3, w=2, h=4}, {x=7, y=17, w=2, h=4}, {x=13, y=8, w=2, h=2},
                   {x=13, y=14, w=2, h=2} },
        bushes = { {x=3, y=1, w=4, h=2}, {x=3, y=21, w=4, h=2}, {x=16, y=2, w=2, h=4},
                   {x=16, y=18, w=2, h=4} },
        crates = { {x=4, y=7}, {x=4, y=16}, {x=10, y=5}, {x=10, y=18} },
        centerWalls = {}, centerBushes = {},
        goals = true,
    },
    kingdom = {
        cols = 60, rows = 40, mirror4 = true,
        walls  = { {x=9, y=2, w=2, h=4}, {x=2, y=9, w=4, h=2}, {x=15, y=6, w=2, h=4},
                   {x=6, y=14, w=4, h=2}, {x=21, y=2, w=4, h=2}, {x=22, y=11, w=2, h=4},
                   {x=13, y=16, w=4, h=2} },
        bushes = { {x=12, y=0, w=4, h=2}, {x=0, y=13, w=2, h=4}, {x=10, y=9, w=4, h=4},
                   {x=18, y=13, w=2, h=4}, {x=26, y=6, w=2, h=4}, {x=25, y=17, w=2, h=2} },
        crates = { {x=6, y=6}, {x=12, y=6}, {x=18, y=3}, {x=4, y=17}, {x=19, y=9}, {x=26, y=13} },
        centerWalls = {}, centerBushes = {},
        -- three spots per team (tile centres in the top-left corner, mirrored to the
        -- others): team 1 top left, 2 bottom right, 3 top right, 4 bottom left
        spots = { {3.5, 3.5}, {5.5, 3.5}, {3.5, 5.5} },
    },
    hideout = {
        cols = 60, rows = 40, mirror4 = true,
        walls  = { {x=6, y=4, w=4, h=2}, {x=4, y=12, w=2, h=4}, {x=13, y=8, w=4, h=4},
                   {x=20, y=3, w=2, h=4}, {x=22, y=12, w=4, h=2}, {x=10, y=16, w=2, h=2},
                   {x=26, y=7, w=2, h=2} },
        bushes = { {x=1, y=1, w=4, h=2}, {x=9, y=1, w=2, h=2}, {x=15, y=2, w=4, h=2},
                   {x=24, y=1, w=2, h=4}, {x=1, y=7, w=2, h=4}, {x=8, y=8, w=2, h=4},
                   {x=17, y=13, w=4, h=2}, {x=1, y=16, w=4, h=2}, {x=7, y=13, w=2, h=2},
                   {x=13, y=17, w=6, h=2}, {x=26, y=10, w=2, h=2}, {x=20, y=8, w=2, h=2},
                   {x=24, y=16, w=2, h=2}, {x=10, y=11, w=2, h=2} },
        crates = { {x=11, y=5}, {x=19, y=10}, {x=3, y=5}, {x=16, y=15}, {x=23, y=6},
                   {x=6, y=17}, {x=27, y=14} },
        centerWalls = {}, centerBushes = {},
        -- the picture frame in the middle (w x h tiles, drawn on the ground, not solid)
        -- and the picture pieces (a tile centre in the top-left quarter, mirrored)
        frame = { w = 4, h = 3 },
        piece = { 6.5, 9.5 },
    },
    gardens = {
        cols = 60, rows = 40, mirror4 = true,
        walls  = { {x=12, y=3, w=2, h=4}, {x=3, y=11, w=4, h=2}, {x=17, y=9, w=4, h=2},
                   {x=10, y=14, w=2, h=4}, {x=22, y=3, w=2, h=4} },
        bushes = { {x=15, y=0, w=4, h=2}, {x=0, y=14, w=2, h=4}, {x=13, y=9, w=2, h=2},
                   {x=24, y=10, w=2, h=2}, {x=16, y=15, w=4, h=2}, {x=6, y=17, w=2, h=2} },
        crates = { {x=11, y=9}, {x=20, y=6}, {x=7, y=14}, {x=26, y=15}, {x=19, y=13}, {x=26, y=6} },
        centerWalls = {}, centerBushes = {},
        -- the garden in the top-left corner (tiles from the corner, mirrored to the
        -- others like the spots), fenced on its two open sides; the spots are inside
        garden = { w = 9, h = 7 },
        spots = { {3, 2.5}, {6, 2.5}, {3, 5} },
    },
}

-- Goals (pitch only): a mouth of GOAL_TILES tiles in the middle of the left and right
-- border, indexed by the team that defends it (World.TEAM_BLUE = 1 plays on the left).
-- { x = the border line, y1, y2, dir = which way is "into the goal" (-1 left, 1 right) }
local GOAL_TILES = 4
Arena.GOAL_DEPTH = 48 -- px: how far the net reaches into the field (drawn)
Arena.center = { x = Arena.width / 2, y = Arena.height / 2 }
Arena.goals = nil
Arena.layout = nil

local grassBatch -- (the floor; built for the current size, see buildGrass)

-- Left half -> both halves; mirror4: top-left quarter -> all four quarters
local function mirrored(list, out, mirror4)
    for _, o in ipairs(list) do
        local w, h = o.w or 1, o.h or 1
        local mx = Arena.cols - o.x - w
        out[#out + 1] = o
        out[#out + 1] = { x = mx, y = o.y, w = o.w, h = o.h }
        if mirror4 then
            local my = Arena.rows - o.y - h
            out[#out + 1] = { x = o.x, y = my, w = o.w, h = o.h }
            out[#out + 1] = { x = mx, y = my, w = o.w, h = o.h }
        end
    end
end

-- Switch to another layout ("yard", "pitch", "kingdom", "hideout" or "gardens"): size,
-- walls, bushes, crates, goals, spawns, the Hide and seek frame and pieces, the gardens
function Arena.setLayout(name)
    local L = LAYOUTS[name] or LAYOUTS.yard
    Arena.layout = LAYOUTS[name] and name or "yard"
    local cols, rows = L.cols or 40, L.rows or 24
    if cols ~= Arena.cols or rows ~= Arena.rows then grassBatch = nil end
    Arena.cols, Arena.rows = cols, rows
    Arena.width, Arena.height = cols * TILE, rows * TILE
    Arena.center = { x = Arena.width / 2, y = Arena.height / 2 }
    walls, bushes, crates, solids = {}, {}, {}, {}
    mirrored(L.walls, walls, L.mirror4)
    mirrored(L.bushes, bushes, L.mirror4)
    mirrored(L.crates, crates, L.mirror4)
    for _, o in ipairs(L.centerWalls)  do walls[#walls + 1] = o end
    for _, o in ipairs(L.centerBushes) do bushes[#bushes + 1] = o end
    Arena.walls, Arena.bushes = walls, bushes -- exposed for the minimap

    -- Solid rectangles in pixels (used for collision)
    for _, w in ipairs(walls) do
        solids[#solids + 1] = { x = w.x * TILE, y = w.y * TILE, w = w.w * TILE, h = w.h * TILE }
    end
    for _, c in ipairs(crates) do
        solids[#solids + 1] = { x = c.x * TILE, y = c.y * TILE, w = TILE, h = TILE }
    end

    -- Spawns: the yard/pitch ones (left and right middle); kingdom: Arena.teamSpawns[team]
    Arena.spawn      = { x = 2.5 * TILE,  y = rows / 2 * TILE }
    Arena.enemySpawn = { x = Arena.width - 2.5 * TILE, y = rows / 2 * TILE }
    Arena.teamSpawns = nil
    if L.spots then
        Arena.teamSpawns = {}
        local flips = { { false, false }, { true, true }, { true, false }, { false, true } }
        for team, f in ipairs(flips) do
            local list = {}
            for _, s in ipairs(L.spots) do
                local x, y = s[1] * TILE, s[2] * TILE
                if f[1] then x = Arena.width - x end
                if f[2] then y = Arena.height - y end
                list[#list + 1] = { x, y }
            end
            Arena.teamSpawns[team] = list
        end
        Arena.spawn = { x = Arena.teamSpawns[1][1][1], y = Arena.teamSpawns[1][1][2] }
    end

    -- Flower Gardens: Arena.gardens[team] = { x1, y1, x2, y2 (px), cx, cy (its middle),
    -- fence = the two open sides as one line { x, y, x, y, x, y } } (corners as the spots)
    Arena.gardens = nil
    if L.garden then
        Arena.gardens = {}
        local gw, gh = L.garden.w * TILE, L.garden.h * TILE
        local W, H = Arena.width, Arena.height
        for team, f in ipairs({ { false, false }, { true, true }, { true, false }, { false, true } }) do
            local x1, x2 = f[1] and W - gw or 0, f[1] and W or gw
            local y1, y2 = f[2] and H - gh or 0, f[2] and H or gh
            local fx, fy = f[1] and x1 or x2, f[2] and y1 or y2 -- (the inner corner)
            Arena.gardens[team] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, cx = (x1 + x2) / 2,
                cy = (y1 + y2) / 2, fence = { fx, f[2] and H or 0, fx, fy, f[1] and W or 0, fy } }
        end
    end

    -- Hide and seek: Arena.frame = { x, y, w, h } (px), Arena.pieceSpots = 4 x { x, y }
    Arena.frame, Arena.pieceSpots = nil, nil
    if L.frame then
        local fw, fh = L.frame.w * TILE, L.frame.h * TILE
        Arena.frame = { x = (Arena.width - fw) / 2, y = (Arena.height - fh) / 2, w = fw, h = fh }
        local px, py = L.piece[1] * TILE, L.piece[2] * TILE
        Arena.pieceSpots = { { px, py }, { Arena.width - px, py }, { px, Arena.height - py },
                             { Arena.width - px, Arena.height - py } }
    end

    Arena.goals = nil
    if L.goals then
        local y1 = (Arena.rows - GOAL_TILES) / 2 * TILE
        local y2 = y1 + GOAL_TILES * TILE
        Arena.goals = { { x = 0, y1 = y1, y2 = y2, dir = -1 },
                        { x = Arena.width, y1 = y1, y2 = y2, dir = 1 } }
    end
end
Arena.setLayout("yard")

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

-- True if nothing solid lies on the straight line between two points. (Only the solids
-- near the line are tested: bots ask this a lot, and without JIT - Android - testing
-- every solid at every step of the line was most of a simulation step on the big maps.)
local near = {} -- (reused: the solids near the current line)
function Arena.hasLineOfSight(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local steps = math.ceil(math.sqrt(dx * dx + dy * dy) / 8)
    local W, H = Arena.width, Arena.height
    if x1 < 0 or y1 < 0 or x2 < 0 or y2 < 0 or x1 > W or x2 > W or y1 > H or y2 > H then
        for i = 1, steps - 1 do -- (an end outside the arena: the plain way)
            local t = i / steps
            if Arena.hitsSolid(x1 + dx * t, y1 + dy * t, 3) then return false end
        end
        return true
    end
    local minX, maxX = math.min(x1, x2) - 3, math.max(x1, x2) + 3
    local minY, maxY = math.min(y1, y2) - 3, math.max(y1, y2) + 3
    local n = 0
    for _, s in ipairs(solids) do
        if s.x < maxX and s.x + s.w > minX and s.y < maxY and s.y + s.h > minY then
            n = n + 1
            near[n] = s
        end
    end
    if n == 0 then return true end
    for i = 1, steps - 1 do
        local t = i / steps
        local x, y = x1 + dx * t, y1 + dy * t
        for j = 1, n do
            local s = near[j]
            local cx = math.max(s.x, math.min(x, s.x + s.w))
            local cy = math.max(s.y, math.min(y, s.y + s.h))
            if (x - cx) ^ 2 + (y - cy) ^ 2 < 9 then return false end
        end
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

-- The free spot nearest to x, y where a circle of radius r fits (rings of 16 px
-- around it); x, y itself if it is free
function Arena.nearestOpen(x, y, r)
    if not Arena.hitsSolid(x, y, r) then return x, y end
    for d = 16, 640, 16 do
        local n = math.max(8, math.floor(d / 6))
        for i = 0, n - 1 do
            local a = i / n * math.pi * 2
            local px, py = x + math.cos(a) * d, y + math.sin(a) * d
            if not Arena.hitsSolid(px, py, r) then return px, py end
        end
    end
    return Arena.spawn.x, Arena.spawn.y
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

-- One SpriteBatch holds the whole grass floor (built once per size, drawn in one call)
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

    if Arena.goals then -- pitch markings: centre line + circle, a box in front of each goal
        local cx, cy = Arena.center.x, Arena.center.y
        love.graphics.setColor(1, 1, 1, 0.3)
        love.graphics.setLineWidth(6)
        love.graphics.line(cx, 0, cx, Arena.height)
        love.graphics.circle("line", cx, cy, 180)
        love.graphics.circle("fill", cx, cy, 10)
        for _, g in ipairs(Arena.goals) do
            local w = 3 * TILE
            local bx = g.dir < 0 and 0 or Arena.width - w
            love.graphics.rectangle("line", bx, g.y1 - 2 * TILE, w, g.y2 - g.y1 + 4 * TILE)
        end
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1)
    end

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
