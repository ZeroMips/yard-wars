-- Yardball drawing (the rules are in src/world.lua): the ball (a cartoon ball with a
-- shadow that spins while it rolls), the goals (posts + net in the team colours), the
-- kick preview while carrying, and a small ball icon for the HUD and the menu.
local Arena = require("src.arena")
local World = require("src.world")

local Ball = {}

local R = World.BALL_RADIUS
local spin, lastX, lastY = 0, nil, nil -- turns with the distance the ball moved

-- A cartoon ball: white with dark patches, outlined; turn = angle of the pattern
function Ball.drawIcon(cx, cy, r, turn, alpha)
    alpha = alpha or 1
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.circle("fill", cx, cy, r)
    love.graphics.setColor(0.12, 0.12, 0.15, alpha)
    local function patch(px, py, s, a)
        local pts = {}
        for i = 0, 4 do
            local t = a + i / 5 * math.pi * 2
            pts[#pts + 1] = px + math.cos(t) * s
            pts[#pts + 1] = py + math.sin(t) * s
        end
        love.graphics.polygon("fill", pts)
    end
    turn = turn or 0
    patch(cx, cy, r * 0.32, turn - math.pi / 2)
    for i = 0, 4 do
        local a = turn + i / 5 * math.pi * 2
        patch(cx + math.cos(a) * r * 0.68, cy + math.sin(a) * r * 0.68, r * 0.2, a)
    end
    love.graphics.setLineWidth(math.max(1.5, r * 0.14))
    love.graphics.circle("line", cx, cy, r)
    love.graphics.setLineWidth(1)
end

-- The ball in the world. kickoff: seconds until it can be taken (it pulses meanwhile)
function Ball.draw(ball, kickoff)
    if lastX then
        local moved = math.sqrt((ball.x - lastX) ^ 2 + (ball.y - lastY) ^ 2)
        if moved < 200 then spin = spin + moved / R * 0.5 end
    end
    lastX, lastY = ball.x, ball.y
    local t = love.timer.getTime()
    if (kickoff or 0) > 0 then -- a ring around it until it can be taken
        love.graphics.setColor(1, 1, 1, 0.5 + 0.3 * math.sin(t * 10))
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", ball.x, ball.y, R + 10 + 4 * math.sin(t * 6))
        love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.ellipse("fill", ball.x + 3, ball.y + 6, R, R * 0.75)
    Ball.drawIcon(ball.x, ball.y, R, spin)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Goal posts and nets. colors[team] = colour of the team defending that goal
function Ball.drawGoals(colors)
    local D = Arena.GOAL_DEPTH
    for team, g in ipairs(Arena.goals or {}) do
        local c = colors[team] or { 1, 1, 1 }
        local x0 = g.dir < 0 and 0 or Arena.width - D -- the net reaches into the field
        love.graphics.setColor(c[1], c[2], c[3], 0.25)
        love.graphics.rectangle("fill", x0, g.y1, D, g.y2 - g.y1)
        love.graphics.setColor(1, 1, 1, 0.45) -- the net
        love.graphics.setLineWidth(1.5)
        for y = g.y1 + 16, g.y2 - 1, 16 do love.graphics.line(x0, y, x0 + D, y) end
        for x = x0 + 12, x0 + D - 1, 12 do love.graphics.line(x, g.y1, x, g.y2) end
        love.graphics.setLineWidth(5) -- the frame: back bar + the two sides
        love.graphics.setColor(c[1], c[2], c[3], 1)
        local back = g.dir < 0 and 2 or Arena.width - 2
        love.graphics.line(back, g.y1, back, g.y2)
        local front = g.dir < 0 and D or Arena.width - D
        love.graphics.line(back, g.y1, front, g.y1)
        love.graphics.line(back, g.y2, front, g.y2)
        -- the posts at the front (white, round)
        for _, y in ipairs({ g.y1, g.y2 }) do
            love.graphics.setColor(0, 0, 0, 0.35)
            love.graphics.circle("fill", front + 2, y + 4, 9)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.circle("fill", front, y, 8)
            love.graphics.setColor(c[1], c[2], c[3], 1)
            love.graphics.setLineWidth(2.5)
            love.graphics.circle("line", front, y, 8)
        end
        love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- While carrying: a dotted line from the ball to where the kick rolls (aimDist from the
-- body centre, KICK_MIN..KICK_MAX; it stops at the first wall - the ball bounces there)
function Ball.drawKickAim(p, aimDist)
    if p.dead then return end
    local bx, by = World.carrySpot(p)
    local d = math.max(World.KICK_MIN, math.min(World.KICK_MAX, aimDist or World.KICK_MAX))
    local roll = math.max(20, d - (p.radius + R + 2))
    local len = Arena.raycast(bx, by, p.aim, roll, R)
    local c, s = math.cos(p.aim), math.sin(p.aim)
    love.graphics.setColor(1, 1, 1, 0.8)
    for k = 18, len - 6, 18 do
        love.graphics.circle("fill", bx + c * k, by + s * k, 3)
    end
    local lx, ly = bx + c * len, by + s * len
    love.graphics.setColor(1, 1, 1, 0.18)
    love.graphics.circle("fill", lx, ly, R + 6)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", lx, ly, R + 6)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Forget the last position (a new game)
function Ball.reset() lastX, lastY = nil, nil end

return Ball
