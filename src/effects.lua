-- Small particle effects in world space: dust puffs, sparks, death bursts, rings.
-- "below" effects are drawn under the characters, "above" effects over them.
local Effects = {}
local list = {}

local function add(p) list[#list + 1] = p end

-- Remove all particles (new game)
function Effects.clear() list = {} end

-- Dust puff at a footstep
function Effects.puff(x, y)
    local l = 0.45
    add { kind = "puff", layer = "below", x = x + (math.random() - 0.5) * 4, y = y,
          vx = (math.random() - 0.5) * 20, vy = (math.random() - 0.5) * 20,
          life = l, max = l, size = 5 + math.random() * 3 }
end

-- Small fast sparks (bullet impacts)
function Effects.sparks(x, y, n, color, speed)
    speed = speed or 180
    for _ = 1, n do
        local a, v = math.random() * math.pi * 2, speed * (0.4 + math.random() * 0.6)
        local l = 0.2 + math.random() * 0.15
        add { kind = "spark", layer = "above", x = x, y = y,
              vx = math.cos(a) * v, vy = math.sin(a) * v,
              life = l, max = l, color = color or { 1, 0.9, 0.5 } }
    end
end

-- Bigger colored blobs (a rowdy is defeated)
function Effects.burst(x, y, color, n)
    for _ = 1, n do
        local a, v = math.random() * math.pi * 2, 80 + math.random() * 180
        local l = 0.5 + math.random() * 0.3
        add { kind = "blob", layer = "above", x = x, y = y,
              vx = math.cos(a) * v, vy = math.sin(a) * v,
              life = l, max = l, size = 4 + math.random() * 5, color = color }
    end
end

-- Healing: green "+" signs rising around (x, y)
function Effects.heal(x, y)
    for i = 1, 6 do
        local a = i / 6 * math.pi * 2 + math.random() * 0.5
        local l = 0.6 + math.random() * 0.3
        add { kind = "plus", layer = "above", x = x + math.cos(a) * 16, y = y + math.sin(a) * 12,
              vx = math.cos(a) * 15, vy = -55 - math.random() * 30,
              life = l, max = l, size = 3.5 + math.random() * 2 }
    end
end

-- A rowdy is knocked out: a cartoon "poof" - white smoke clouds and spinning stars
-- (CHARTER.md: no blood, no bursting bodies)
function Effects.poof(x, y)
    for i = 1, 9 do
        local a = i / 9 * math.pi * 2 + math.random() * 0.4
        local v = 40 + math.random() * 50
        local l = 0.55 + math.random() * 0.25
        add { kind = "cloud", layer = "above", x = x + math.cos(a) * 8, y = y + math.sin(a) * 8,
              vx = math.cos(a) * v, vy = math.sin(a) * v - 20,
              life = l, max = l, size = 10 + math.random() * 6 }
    end
    for i = 1, 5 do
        local a = -math.pi / 2 + (i - 3) * 0.5
        local l = 0.8 + math.random() * 0.2
        add { kind = "star", layer = "above", x = x, y = y - 10,
              vx = math.cos(a) * 110, vy = math.sin(a) * 110,
              life = l, max = l, size = 6 + math.random() * 3, spin = (math.random() - 0.5) * 10 }
    end
end

-- Expanding ring (knockout, respawn)
function Effects.ring(x, y, radius, color)
    add { kind = "ring", layer = "below", x = x, y = y, radius = radius,
          life = 0.4, max = 0.4, color = color or { 1, 1, 1 } }
end

function Effects.update(dt)
    for i = #list, 1, -1 do
        local p = list[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(list, i)
        elseif p.kind ~= "ring" then
            p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
            local drag = math.max(0, 1 - 4 * dt)
            p.vx, p.vy = p.vx * drag, p.vy * drag
        end
    end
end

local function draw(layer)
    for _, p in ipairs(list) do
        if p.layer == layer then
            local k = p.life / p.max -- 1 -> 0 over the lifetime
            if p.kind == "puff" then
                love.graphics.setColor(0.85, 0.82, 0.72, 0.4 * k)
                love.graphics.circle("fill", p.x, p.y, p.size * (2 - k))
            elseif p.kind == "ring" then
                local c = p.color
                love.graphics.setColor(c[1], c[2], c[3], k)
                love.graphics.setLineWidth(1 + 4 * k)
                love.graphics.circle("line", p.x, p.y, p.radius * (1 - k) + 4)
                love.graphics.setLineWidth(1)
            elseif p.kind == "spark" then
                local c = p.color
                love.graphics.setBlendMode("add")
                love.graphics.setColor(c[1], c[2], c[3], k)
                love.graphics.setLineWidth(3)
                love.graphics.line(p.x, p.y, p.x - p.vx * 0.03, p.y - p.vy * 0.03)
                love.graphics.setLineWidth(1)
                love.graphics.setBlendMode("alpha")
            elseif p.kind == "plus" then
                local s, w = p.size, p.size * 0.45
                love.graphics.setColor(0.1, 0.3, 0.1, k)
                love.graphics.rectangle("fill", p.x - w - 1.5, p.y - s - 1.5, 2 * w + 3, 2 * s + 3)
                love.graphics.rectangle("fill", p.x - s - 1.5, p.y - w - 1.5, 2 * s + 3, 2 * w + 3)
                love.graphics.setColor(0.4, 1, 0.4, k)
                love.graphics.rectangle("fill", p.x - w, p.y - s, 2 * w, 2 * s)
                love.graphics.rectangle("fill", p.x - s, p.y - w, 2 * s, 2 * w)
            elseif p.kind == "cloud" then -- white smoke ball with a soft grey edge
                local r = p.size * (1.4 - 0.6 * k)
                love.graphics.setColor(0.55, 0.55, 0.6, 0.6 * k)
                love.graphics.circle("fill", p.x, p.y + 2, r + 2)
                love.graphics.setColor(1, 1, 1, 0.9 * k)
                love.graphics.circle("fill", p.x, p.y, r)
            elseif p.kind == "star" then -- yellow cartoon star
                local pts = {}
                local rot = (p.spin or 0) * (1 - k)
                for j = 0, 9 do
                    local a = rot + j / 10 * math.pi * 2 - math.pi / 2
                    local d = (j % 2 == 0) and p.size or p.size * 0.45
                    pts[#pts + 1] = p.x + math.cos(a) * d
                    pts[#pts + 1] = p.y + math.sin(a) * d
                end
                love.graphics.setColor(1, 0.85, 0.2, k)
                for j = 1, 10 do -- as triangles from the centre (the outline isn't convex)
                    local n = j % 10 + 1
                    love.graphics.polygon("fill", p.x, p.y, pts[2 * j - 1], pts[2 * j], pts[2 * n - 1], pts[2 * n])
                end
                love.graphics.setColor(0.45, 0.3, 0.05, k)
                love.graphics.polygon("line", pts)
            elseif p.kind == "blob" then
                local c = p.color
                love.graphics.setColor(c[1], c[2], c[3], k)
                love.graphics.circle("fill", p.x, p.y, p.size * (0.3 + 0.7 * k))
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function Effects.drawBelow() draw("below") end
function Effects.drawAbove() draw("above") end

return Effects
