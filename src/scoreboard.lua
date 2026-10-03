-- In-game scoreboard at the top of the screen, plus short banners in the middle
-- ("30 seconds left!", "Last life!", "Wave 3").
-- Drawn in HUD units (720 along the short screen side, already scaled by the caller).
--
-- info (built by main.lua, plain data):
--   versus: { kind = "versus", left = side, right = side, target, timeLeft }
--           side = { name, score, color }  (left = you / your team)
--   waves : { kind = "waves", wave, bots, lives, maxLives }
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
    if info.kind == "versus" then
        local sideW, midW = 100, W - 2 * 100 - 16
        scoreBox(info.left, x, y, sideW, info.target, fonts)
        scoreBox(info.right, x + W - sideW, y, sideW, info.target, fonts)
        -- timer: turns red in the last 30 s and pulses in the last 10 s
        local mx = x + sideW + 8
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
