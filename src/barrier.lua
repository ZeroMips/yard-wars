-- Drawing of the Officer's barriers (the rules are in src/world.lua): traffic cones at
-- the points of the fence with striped tape between them, a stripe in the team colour
-- (own team: it lets you through). Pops up, blinks in its last second.
local World = require("src.world")

local Barrier = {}

-- w: { points, born, expires, team }; time: world time; color: team colour of the fence
function Barrier.draw(w, time, color)
    local left = w.expires - time
    if left <= 0 then return end
    local age = time - (w.born or (w.expires - 6))
    local pop = math.min(1, math.max(0.2, age / 0.2))
    local alpha = left < 1 and (0.5 + 0.5 * math.abs(math.sin(left * 12))) or 1
    local p = w.points
    local h = World.BARRIER_HALF * pop
    -- tape: dark outline, then yellow with black stripes, a thin line in the team colour
    for i = 1, #p - 3, 2 do
        local x1, y1, x2, y2 = p[i], p[i + 1], p[i + 2], p[i + 3]
        love.graphics.setLineWidth(h * 2 + 4)
        love.graphics.setColor(0.1, 0.1, 0.1, 0.9 * alpha)
        love.graphics.line(x1, y1, x2, y2)
        love.graphics.setLineWidth(h * 2)
        love.graphics.setColor(1, 0.85, 0.15, alpha)
        love.graphics.line(x1, y1, x2, y2)
        love.graphics.setColor(0.1, 0.1, 0.1, alpha)
        local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        for k = 8, len - 8, 18 do -- stripes
            local a, b = k / len, math.min(1, (k + 8) / len)
            love.graphics.line(x1 + (x2 - x1) * a, y1 + (y2 - y1) * a, x1 + (x2 - x1) * b, y1 + (y2 - y1) * b)
        end
        love.graphics.setLineWidth(3)
        love.graphics.setColor(color[1], color[2], color[3], alpha)
        love.graphics.line(x1, y1, x2, y2)
    end
    love.graphics.setLineWidth(1)
    -- traffic cones at the points
    for i = 1, #p - 1, 2 do
        local x, y, r = p[i], p[i + 1], 11 * pop
        love.graphics.setColor(0, 0, 0, 0.3 * alpha)
        love.graphics.circle("fill", x + 2, y + 4, r + 2)
        love.graphics.setColor(0.15, 0.08, 0.05, alpha)
        love.graphics.circle("fill", x, y, r + 2)
        love.graphics.setColor(1, 0.45, 0.1, alpha)
        love.graphics.circle("fill", x, y, r)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.circle("fill", x, y, r * 0.6)
        love.graphics.setColor(1, 0.45, 0.1, alpha)
        love.graphics.circle("fill", x, y, r * 0.3)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return Barrier
