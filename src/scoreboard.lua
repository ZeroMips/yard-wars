-- In-game scoreboard at the top of the screen, plus short banners in the middle
-- ("30 seconds left!", "Last life!", "Wave 3").
-- Drawn in HUD units (720 along the short screen side, already scaled by the caller).
--
-- info (built by main.lua, plain data):
--   versus: { kind = "versus", left = side, right = side, target, timeLeft, goals }
--           side = { name, score, color }  (left = you / your team)
--           goals = true (Yardball): a ball instead of the timer (no time limit)
--   waves : { kind = "waves", wave, bots, lives, maxLives }
--   boss  : { kind = "boss", name, hp, maxHp }  (one wide health bar)
--   king  : { kind = "king", teams = { { name, color, up = rowdies up }, ... },
--             fogIn = seconds until the fog starts closing (nil: it is), closed = bool }
--   hide  : { kind = "hide", hiding = seconds of the hide phase left (nil: seeking),
--             timeLeft, left = hiders not found, hiders = all hiders, placed, pieces,
--             seeker = bool (this player seeks) }
--   flowers: { kind = "flowers", teams = { { name, color, delivered, count (towards the
--             bulldozer), fence = up?, out = bool }, ... } (own first), timeLeft,
--             need = flowers per bulldozer }
local Ball = require("src.ball")
local Flowers = require("src.flowers")

local Scoreboard = {}

Scoreboard.WIDTH  = 300 -- panel size (HUD units), for the caller's layout
Scoreboard.HEIGHT = 58

local BOX_H = 44
local BANNER_TIME = 2.2
local banner -- { text, color, time = seconds left }

local function box(x, y, w, h, color, alpha)
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 4, 8, 8)
    love.graphics.setColor(color[1], color[2], color[3], alpha or 0.85)
    love.graphics.rectangle("fill", x, y, w, h, 6, 6)
end

-- Text centred in a box, with a dark shadow so it reads on any color
local function label(text, font, x, y, w)
    love.graphics.setFont(font)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf(text, x + 1, y + 2, w, "center")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(text, x, y, w, "center")
end

local function heart(cx, cy, s, full)
    local pts = {}
    for i = 0, 23 do -- classic heart curve
        local t = i / 24 * math.pi * 2
        local x = 16 * math.sin(t) ^ 3
        local y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
        pts[#pts + 1] = cx + x * s
        pts[#pts + 1] = cy + y * s
    end
    if full then
        love.graphics.setColor(0.95, 0.2, 0.25, 1)
        love.graphics.polygon("fill", pts)
    end
    love.graphics.setColor(full and { 1, 0.85, 0.85, 1 } or { 1, 1, 1, 0.35 })
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", pts)
    love.graphics.setLineWidth(1)
end

local function formatTime(t)
    t = math.max(0, math.ceil(t or 0))
    return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

-- One score box: name small on top, the score big; a bar below shows the way to the target
local function scoreBox(side, x, y, w, target, fonts)
    box(x, y, w, BOX_H, side.color)
    label(side.name, fonts.small, x, y + 2, w)
    label(tostring(side.score), fonts.big, x, y + 13, w)
    local k = math.min(1, side.score / target)
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", x, y + BOX_H + 4, w, 5, 2, 2)
    love.graphics.setColor(side.color[1], side.color[2], side.color[3], 1)
    love.graphics.rectangle("fill", x, y + BOX_H + 4, w * k, 5, 2, 2)
end

-- fonts = { small, big }; cx = centre of the panel, y = its top. time: for pulsing.
function Scoreboard.draw(info, fonts, cx, y, time)
    local W = Scoreboard.WIDTH
    local x = cx - W / 2
    if info.kind == "boss" then
        box(x, y, W, BOX_H, { 0.15, 0.15, 0.2 })
        label("BOSS: " .. info.name, fonts.small, x, y + 2, W)
        local bx, by, bw, bh = x + 10, y + 19, W - 20, 18
        local k = math.max(0, math.min(1, info.hp / info.maxHp))
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", bx, by, bw, bh, 6, 6)
        love.graphics.setColor(0.85, 0.25, 0.25, 1)
        if k > 0 then love.graphics.rectangle("fill", bx, by, bw * k, bh, 6, 6) end
        love.graphics.setColor(1, 1, 1, 0.25)
        if k > 0 then love.graphics.rectangle("fill", bx, by, bw * k, bh * 0.4, 6, 6) end
        label(math.ceil(info.hp) .. " / " .. math.ceil(info.maxHp), fonts.small, bx, by + 2, bw)
        label("no time limit - you pop back in", fonts.small, x - 20, y + BOX_H + 3, W + 40)
    elseif info.kind == "versus" then
        local sideW, midW = 100, W - 2 * 100 - 16
        scoreBox(info.left, x, y, sideW, info.target, fonts)
        scoreBox(info.right, x + W - sideW, y, sideW, info.target, fonts)
        local mx = x + sideW + 8
        if info.goals then -- Yardball: no timer
            box(mx, y, midW, BOX_H, { 0.15, 0.15, 0.2 })
            Ball.drawIcon(mx + midW / 2, y + BOX_H / 2, 15, time * 0.5)
            label("first to " .. info.target .. " goals", fonts.small, mx - 20, y + BOX_H + 3, midW + 40)
            love.graphics.setColor(1, 1, 1, 1)
            return
        end
        -- timer: turns red in the last 30 s and pulses in the last 10 s
        local t = info.timeLeft or 0
        local urgent = t <= 30
        box(mx, y, midW, BOX_H, urgent and { 0.75, 0.12, 0.12 } or { 0.15, 0.15, 0.2 })
        love.graphics.push()
        if t <= 10 and t > 0 then
            local s = 1 + 0.12 * math.max(0, math.sin(time * math.pi * 2))
            love.graphics.translate(mx + midW / 2, y + BOX_H / 2)
            love.graphics.scale(s)
            love.graphics.translate(-(mx + midW / 2), -(y + BOX_H / 2))
        end
        label(formatTime(t), fonts.big, mx, y + 7, midW)
        love.graphics.pop()
        label("first to " .. info.target, fonts.small, mx - 10, y + BOX_H + 3, midW + 20)
    elseif info.kind == "king" then
        -- the teams (own first): how many of them are up, grey once out
        local n = #info.teams
        local fogW = 84
        local tw = (W - fogW - 8 - (n - 1) * 4) / n
        for i, team in ipairs(info.teams) do
            local tx = x + (i - 1) * (tw + 4)
            local out = team.up == 0
            box(tx, y, tw, BOX_H, out and { 0.3, 0.3, 0.32 } or team.color, out and 0.6 or 0.85)
            local name = team.name -- ("YELLOW" may not fit: "YEL")
            if fonts.small:getWidth(name) > tw - 4 then name = name:sub(1, 3) end
            label(name, fonts.small, tx, y + 2, tw)
            label(out and "-" or tostring(team.up), fonts.big, tx, y + 13, tw)
        end
        -- the fog: time until it closes in, then a pulsing cloud
        local fx = x + W - fogW
        local closing = not info.fogIn
        box(fx, y, fogW, BOX_H, closing and { 0.45, 0.47, 0.55 } or { 0.15, 0.15, 0.2 })
        label("FOG", fonts.small, fx, y + 2, fogW)
        if closing then
            local k = 0.5 + 0.5 * math.sin(time * 3)
            love.graphics.setColor(0.9, 0.92, 0.95, 0.7 + 0.3 * k)
            for i, c in ipairs({ { -14, 4, 9 }, { 0, -1, 12 }, { 14, 4, 9 }, { 0, 7, 10 } }) do
                love.graphics.circle("fill", fx + fogW / 2 + c[1], y + 26 + c[2], c[3])
            end
        else
            label(formatTime(info.fogIn), fonts.big, fx, y + 13, fogW)
        end
        label(closing and (info.closed and "the fog is everywhere!" or "fog closing in - last team standing")
            or "last team standing wins", fonts.small, x - 20, y + BOX_H + 3, W + 40)
    elseif info.kind == "hide" then
        -- hiders (a head each, grey once found) | the clock | the picture pieces
        local sideW = 92
        local mx, midW = x + sideW + 8, W - 2 * sideW - 16
        box(x, y, sideW, BOX_H, { 0.25, 0.55, 0.25 })
        label("HIDERS", fonts.small, x, y + 2, sideW)
        local n = math.max(1, info.hiders)
        local gap = math.min(16, (sideW - 12) / n)
        for i = 1, n do
            local hx = x + sideW / 2 + (i - (n + 1) / 2) * gap
            love.graphics.setColor(i <= info.left and { 1, 1, 1, 1 } or { 0.2, 0.2, 0.2, 0.6 })
            love.graphics.circle("fill", hx, y + 25, 5)
            love.graphics.arc("fill", hx, y + 39, 7, math.pi, math.pi * 2)
        end
        local t = info.hiding or info.timeLeft or 0
        local urgent = not info.hiding and t <= 30
        box(mx, y, midW, BOX_H, info.hiding and { 0.55, 0.42, 0.1 } or urgent and { 0.75, 0.12, 0.12 }
            or { 0.15, 0.15, 0.2 })
        label(info.hiding and "HIDE!" or "TIME", fonts.small, mx, y + 2, midW)
        label(info.hiding and tostring(math.max(0, math.ceil(t))) or formatTime(t), fonts.big, mx, y + 13, midW)
        local px = x + W - sideW
        box(px, y, sideW, BOX_H, { 0.55, 0.33, 0.15 })
        label("PICTURE", fonts.small, px, y + 2, sideW)
        for i = 1, info.pieces do -- a little square per piece, gold once placed
            local sx = px + sideW / 2 + (i - (info.pieces + 1) / 2) * 18 - 7
            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.rectangle("fill", sx - 1, y + 21, 16, 14, 3, 3)
            love.graphics.setColor(i <= info.placed and { 1, 0.82, 0.2, 1 } or { 1, 1, 1, 0.2 })
            love.graphics.rectangle("fill", sx, y + 22, 14, 12, 2, 2)
        end
        local text
        if info.hiding then text = info.seeker and "you seek - counting" or "hide! the seeker counts"
        elseif info.seeker then text = "find them all before the time is up"
        else text = "stay hidden - pieces take time off" end
        label(text, fonts.small, x - 20, y + BOX_H + 3, W + 40)
    elseif info.kind == "flowers" then
        -- the teams (own first): flowers delivered, the fence, the way to the next
        -- bulldozer as a bar below; then the clock
        local n = #info.teams
        local clockW = 70
        local tw = (W - clockW - 8 - (n - 1) * 4) / n
        for i, team in ipairs(info.teams) do
            local tx = x + (i - 1) * (tw + 4)
            box(tx, y, tw, BOX_H, team.out and { 0.3, 0.3, 0.32 } or team.color, team.out and 0.6 or 0.85)
            local name = team.name
            if fonts.small:getWidth(name) > tw - 4 then name = name:sub(1, 3) end
            label(name, fonts.small, tx, y + 2, tw)
            label(tostring(team.delivered), fonts.big, tx - 9, y + 13, tw)
            Flowers.drawFenceIcon(tx + tw - 12, y + 30, 0.85, team.fence)
            local k = math.min(1, team.count / info.need)
            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.rectangle("fill", tx, y + BOX_H + 4, tw, 5, 2, 2)
            love.graphics.setColor(1, 0.82, 0.2, 1)
            if k > 0 then love.graphics.rectangle("fill", tx, y + BOX_H + 4, tw * k, 5, 2, 2) end
        end
        local cx2 = x + W - clockW
        local t = info.timeLeft or 0
        local urgent = t <= 30
        box(cx2, y, clockW, BOX_H, urgent and { 0.75, 0.12, 0.12 } or { 0.15, 0.15, 0.2 })
        label("TIME", fonts.small, cx2, y + 2, clockW)
        label(formatTime(t), fonts.big, cx2, y + 13, clockW)
        label("flowers home - " .. info.need .. " = a bulldozer", fonts.small, x - 20, y + BOX_H + 10, W + 40)
    else -- waves
        local sideW = 86
        box(x, y, sideW, BOX_H, { 0.15, 0.15, 0.2 })
        label("WAVE", fonts.small, x, y + 2, sideW)
        label(tostring(info.wave), fonts.big, x, y + 13, sideW)
        local bx = x + W - sideW
        box(bx, y, sideW, BOX_H, { 0.75, 0.2, 0.2 })
        label("BOTS", fonts.small, bx, y + 2, sideW)
        label(tostring(info.bots), fonts.big, bx, y + 13, sideW)
        -- lives as hearts; the last one beats
        local mx, midW = x + sideW + 8, W - 2 * sideW - 16
        box(mx, y, midW, BOX_H, { 0.15, 0.15, 0.2 })
        local n = info.maxLives
        local gap = midW / n
        for i = 1, n do
            local full = i <= info.lives
            local s = 0.75
            if full and info.lives == 1 then s = s * (1 + 0.15 * math.max(0, math.sin(time * 7))) end
            heart(mx + gap * (i - 0.5), y + BOX_H / 2 + 1, s, full)
        end
        label(info.lives == 1 and "last life!" or (info.lives .. " lives"), fonts.small,
            mx - 10, y + BOX_H + 3, midW + 20)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- A short message in the middle of the screen
function Scoreboard.flash(text, color)
    banner = { text = text, color = color or { 1, 1, 1 }, time = BANNER_TIME }
end

function Scoreboard.clear() banner = nil end

function Scoreboard.update(dt)
    if banner then
        banner.time = banner.time - dt
        if banner.time <= 0 then banner = nil end
    end
end

-- font: big font for the banner; sw = screen width, y = its vertical centre
function Scoreboard.drawBanner(font, sw, y)
    if not banner then return end
    local age = BANNER_TIME - banner.time
    local alpha = math.min(1, banner.time / 0.4)            -- fade out
    local s = 1 + 0.4 * math.max(0, 1 - age / 0.15)          -- pop in
    local c = banner.color
    love.graphics.push()
    love.graphics.translate(sw / 2, y)
    love.graphics.scale(s)
    love.graphics.setFont(font)
    local h = font:getHeight()
    love.graphics.setColor(0, 0, 0, 0.6 * alpha)
    love.graphics.printf(banner.text, -sw / 2 + 2, -h / 2 + 3, sw, "center")
    love.graphics.setColor(c[1], c[2], c[3], alpha)
    love.graphics.printf(banner.text, -sw / 2, -h / 2, sw, "center")
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

return Scoreboard
