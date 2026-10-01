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

-- Expanding ring (death, respawn)
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
