-- End-of-round screen, drawn over the frozen game: big title (Victory / Defeat /
-- Draw / Game over), a subtitle, the scoreboard and a row of buttons.
-- info = { title, color, subtitle, lines = { {text, highlight, badge} }, note,
--          reward (coins line, gold, with a coin icon), xp (Yard Pass, see below),
--          buttons = { {id, label} } }
-- lines: badge = a badge id (src/cosmetics.lua) drawn in front of the line.
-- xp: what Pass.onRoundOver returned + shownAt (love.timer time the screen opened):
-- the XP parts, a bar filling from the old to the new XP, "TIER 7!" for a new tier
-- and the completed challenges.
-- Laid out in HUD units (720 along the short screen side), like the menu.
local Loot = require("src.loot")
local Pass = require("src.pass")
local Decor = require("src.decor")
local PassView = require("src.passview")

local Result = {}

Result.selected = 1 -- button chosen with the keyboard (left/right)

local BTN_W, BTN_H, GAP = 200, 60, 16
local FILL_TIME = 1.5 -- seconds the XP bar takes to fill

local function xpHeight(info)
    if not info.xp then return 0 end
    return 76 + 24 * math.min(3, #info.xp.completed)
end

local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end

local function buttonRects(info)
    local ui = uiScale()
    local sw = love.graphics.getWidth() / ui
    local n = #info.buttons
    local w = math.min(BTN_W, (sw - 40 - (n - 1) * GAP) / n)
    local x0 = (sw - (n * w + (n - 1) * GAP)) / 2
    local y = 150 + 28 * math.min(#info.lines, 8) + 50 + (info.reward and 40 or 0) + xpHeight(info)
    local rects = {}
    for i = 1, n do rects[i] = { x = x0 + (i - 1) * (w + GAP), y = y, w = w, h = BTN_H } end
    return rects, sw
end

-- Screen position -> button id or nil
function Result.hit(info, x, y)
    local ui = uiScale()
    x, y = x / ui, y / ui
    for i, r in ipairs(buttonRects(info)) do
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
            return info.buttons[i][1]
        end
    end
end

-- Returns a button id when chosen with the keyboard
function Result.keypressed(info, key)
    local n = #info.buttons
    if key == "left" or key == "a" then
        Result.selected = (Result.selected - 2) % n + 1
    elseif key == "right" or key == "d" then
        Result.selected = Result.selected % n + 1
    elseif key == "return" or key == "kpenter" or key == "space" then
        local b = info.buttons[math.min(Result.selected, n)]
        return b and b[1]
    end
end

function Result.draw(info, fonts)
    local rects, sw = buttonRects(info)
    local ui = uiScale()
    local sh = love.graphics.getHeight() / ui
    love.graphics.push()
    love.graphics.scale(ui)

    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    love.graphics.setFont(fonts.title)
    local c = info.color or { 1, 1, 1 }
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.printf(info.title, 3, 33, sw, "center")
    love.graphics.setColor(c[1], c[2], c[3])
    love.graphics.printf(info.title, 0, 30, sw, "center")

    love.graphics.setFont(fonts.text)
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.printf(info.subtitle or "", 0, 108, sw, "center")

    for i, line in ipairs(info.lines) do
        if i > 8 then break end
        local ly = 150 + (i - 1) * 28
        if line[3] then
            Decor.drawBadge(line[3], (sw - fonts.text:getWidth(line[1])) / 2 - 16,
                ly + fonts.text:getHeight() / 2, 9)
        end
        love.graphics.setFont(fonts.text)
        if line[2] then love.graphics.setColor(1, 0.8, 0.3) else love.graphics.setColor(1, 1, 1, 0.8) end
        love.graphics.printf(line[1], 0, ly, sw, "center")
    end

    if info.reward then
        local font = fonts.button
        local y = 150 + 28 * math.min(#info.lines, 8) + 14
        local w = 36 + font:getWidth(info.reward)
        local x = (sw - w) / 2
        Loot.drawCoin(x + 13, y + font:getHeight() / 2, 13)
        love.graphics.setFont(font)
        love.graphics.setColor(1, 0.85, 0.3)
        love.graphics.print(info.reward, x + 36, y)
    end

    if info.xp then Result.drawXp(info.xp, fonts, sw,
        150 + 28 * math.min(#info.lines, 8) + 14 + (info.reward and 40 or 0) + 4) end

    for i, r in ipairs(rects) do
        love.graphics.setColor(0.1, 0.12, 0.15, 0.92)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 10, 10)
        if i == Result.selected then love.graphics.setColor(1, 0.6, 0.2) else love.graphics.setColor(1, 1, 1, 0.5) end
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 10, 10)
        love.graphics.setLineWidth(1)
        love.graphics.setFont(fonts.button)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(info.buttons[i][2], r.x, r.y + 14, r.w, "center")
    end

    if info.note then
        love.graphics.setFont(fonts.text)
        love.graphics.setColor(1, 1, 1, 0.6)
        local last = rects[#rects]
        love.graphics.printf(info.note, 0, (last and last.y + last.h or 400) + 20, sw, "center")
    end

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

-- The Yard Pass part: "+215 XP  (Victory 100, Knockouts x3 30)", a filling bar, new tiers
-- and completed challenges; top at y
function Result.drawXp(xp, fonts, sw, y)
    local parts = {}
    for _, p in ipairs(xp.parts) do
        if not p.key:match("^challenge") then
            parts[#parts + 1] = p.label .. (p.count > 1 and (" x" .. p.count) or "") .. " " .. p.xp
        end
    end
    love.graphics.setFont(fonts.text)
    love.graphics.setColor(0.75, 0.6, 1)
    local text = "+" .. xp.total .. " XP" .. (#parts > 0 and ("   (" .. table.concat(parts, ", ") .. ")") or "")
    love.graphics.printf(text, 20, y, sw - 40, "center")

    -- the bar fills from the old XP to the new one (and starts over at each new tier)
    local k = math.min(1, (love.timer.getTime() - (xp.shownAt or 0)) / FILL_TIME)
    k = 1 - (1 - k) ^ 2
    local shown = math.floor(xp.before + (xp.after - xp.before) * k)
    local season = xp.season
    local tier, into, need = Pass.level(season, shown)
    local w = math.min(360, sw - 220)
    local bx, by = (sw - w) / 2, y + 34
    PassView.drawBar(bx, by, w, 12, into / need, { 0.75, 0.55, 1 })
    love.graphics.setFont(fonts.text)
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.print(into .. " / " .. need, bx + w + 10, by - 5)
    if k >= 1 and xp.tiersUp > 0 then -- a new tier: "TIER 7!" pulses in front of the bar
        local pulse = 1 + 0.08 * math.sin(love.timer.getTime() * 6)
        local font = fonts.button
        love.graphics.push()
        love.graphics.translate(bx - 14, by + 6)
        love.graphics.scale(pulse)
        love.graphics.setFont(font)
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.printf("TIER " .. tier .. "!", -202, -font:getHeight() / 2 + 2, 200, "right")
        love.graphics.setColor(1, 0.85, 0.25)
        love.graphics.printf("TIER " .. tier .. "!", -200, -font:getHeight() / 2, 200, "right")
        love.graphics.pop()
    else
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.printf("Tier " .. tier, bx - 110, by - 5, 100, "right")
    end
    love.graphics.setFont(fonts.text)
    for i, c in ipairs(xp.completed) do
        if i > 3 then break end
        love.graphics.setColor(0.45, 0.95, 0.5)
        love.graphics.printf("Challenge complete: " .. c.text .. "  +" .. c.xp .. " XP", 20,
            by + 22 + (i - 1) * 24, sw - 40, "center")
    end
end

return Result
