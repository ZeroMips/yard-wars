-- Yard Pass screen: the season's tier track (scrolls sideways; tap a reached tier to
-- claim its reward), today's challenges with a swap button, the weekly challenge and a
-- season switcher (old seasons can still be finished). Data: src/seasons.lua, progress:
-- src/pass.lua. Mouse (wheel scrolls), touch (drag scrolls, tap claims) and keyboard
-- (left/right scroll, up/down season, Enter claims all, Esc back).
-- Laid out in HUD units (720 along the short screen side), like the menu.
local Pass    = require("src.pass")
local Seasons = require("src.seasons")
local Decor   = require("src.decor")
local Loot    = require("src.loot")
local Profile = require("src.profile")

local PassView = {}

PassView.scroll = 0      -- HUD units the track is scrolled to the left
PassView.dragged = false -- the current touch scrolled (main.lua ignores its release)
PassView.message = nil   -- e.g. "Robot unlocked!" (after a claim)
local messageTime = 0
local dragDist = 0
local DRAG_SLOP = 12
local particles = {}     -- claim bursts (HUD units)

local CARD_W, CARD_H, GAP = 132, 168, 12
local TRACK_Y = 104

local GOLD = { 1, 0.8, 0.2 }
local DONE_GREEN = { 0.35, 0.8, 0.4 }

local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end
local function inside(r, x, y) return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

local function layout()
    local ui = uiScale()
    local sw, sh = love.graphics.getWidth() / ui, love.graphics.getHeight() / ui
    local season = Pass.season()
    local L = { sw = sw, sh = sh, season = season, cards = {} }
    if not season then return L end
    local n = #season.tiers
    L.view = { x = 16, y = TRACK_Y, w = sw - 32, h = CARD_H + 16 }
    local content = (n + 1) * (CARD_W + GAP) - GAP + 16
    local maxScroll = math.max(0, content - L.view.w)
    PassView.scroll = math.max(0, math.min(maxScroll, PassView.scroll))
    for i = 1, n + 1 do -- n + 1: the bonus card
        L.cards[i] = { x = L.view.x + 8 + (i - 1) * (CARD_W + GAP) - PassView.scroll,
                       y = TRACK_Y + 8, w = CARD_W, h = CARD_H }
    end
    local seasons = Pass.seasons()
    if #seasons > 1 then -- season switcher at both ends of the tier line
        L.prev = { x = 20, y = 50, w = 48, h = 48 }
        L.next = { x = sw - 68, y = 50, w = 48, h = 48 }
    end
    L.narrow = sw < 900 -- title left, coins right (centred they would overlap)
    -- challenges
    local cw = math.min(sw - 48, 820)
    local cx = (sw - cw) / 2
    local y = TRACK_Y + CARD_H + 30
    L.dailyHead = y
    y = y + 26
    L.rows = {}
    local list = Pass.challenges()
    local rowH = 50
    for i, c in ipairs(list) do
        if c.weekly then
            y = y + 6
            L.weeklyHead = y
            y = y + 26
        end
        local r = { x = cx, y = y, w = cw, h = rowH, c = c }
        if not c.weekly and Pass.canReroll(c.index) then
            r.reroll = { x = cx + cw - 96, y = y + 8, w = 88, h = rowH - 16 }
        end
        L.rows[i] = r
        y = y + rowH + 8
    end
    local by = math.max(y + 10, sh - 84)
    local claimable = Pass.claimable(season)
    if claimable >= 2 then
        L.claimAll = { x = sw / 2 - 230, y = by, w = 220, h = 64 }
        L.back = { x = sw / 2 + 10, y = by, w = 220, h = 64 }
    else
        L.back = { x = sw / 2 - 110, y = by, w = 220, h = 64 }
    end
    return L
end

-- Scroll so the first reward to claim (or the next tier to reach) is in view
function PassView.reveal()
    local L = layout()
    local season = L.season
    if not season then return end
    local target = #season.tiers + 1
    local tier = Pass.level(season)
    for t = 1, #season.tiers do
        if Pass.tierState(season, t) == "ready" then target = t break end
    end
    if target > #season.tiers and tier < #season.tiers then target = tier + 1 end
    PassView.scroll = (target - 1) * (CARD_W + GAP) - (L.view.w - CARD_W) / 2
    layout() -- clamp
end

function PassView.open()
    PassView.message = nil
    particles = {}
    PassView.reveal()
end

function PassView.wheel(dx, dy)
    PassView.scroll = PassView.scroll - (dy + dx) * 70
    layout()
end

function PassView.touchStart()
    PassView.dragged, dragDist = false, 0
end

function PassView.drag(dx)
    dx = dx / uiScale()
    dragDist = dragDist + math.abs(dx)
    if dragDist > DRAG_SLOP then PassView.dragged = true end
    PassView.scroll = PassView.scroll - dx
    layout()
end

-- Screen position -> "tier" + n, "bonus", "reroll" + i, "claimAll", "back", "prev",
-- "next" or nil
function PassView.hit(x, y)
    local ui = uiScale()
    x, y = x / ui, y / ui
    local L = layout()
    if inside(L.back, x, y) then return "back" end
    if inside(L.claimAll, x, y) then return "claimAll" end
    if inside(L.prev, x, y) then return "prev" end
    if inside(L.next, x, y) then return "next" end
    if not L.season then return end
    if inside(L.view, x, y) then
        for i, r in ipairs(L.cards) do
            if inside(r, x, y) then
                if i > #L.season.tiers then return "bonus" end
                return "tier", i
            end
        end
    end
    for _, r in ipairs(L.rows) do
        if inside(r.reroll, x, y) then return "reroll", r.c.index end
    end
end

-- Keyboard: returns "claimAll", "back", "prev", "next" or nil (scrolls itself)
function PassView.keypressed(key)
    if key == "left" or key == "a" then PassView.scroll = PassView.scroll - (CARD_W + GAP); layout()
    elseif key == "right" or key == "d" then PassView.scroll = PassView.scroll + (CARD_W + GAP); layout()
    elseif key == "up" or key == "w" then return "prev"
    elseif key == "down" or key == "s" then return "next"
    elseif key == "return" or key == "kpenter" or key == "space" then return "claimAll"
    elseif key == "escape" or key == "p" then return "back" end
end

-- Switch season (dir -1 / 1); returns true if it changed
function PassView.switchSeason(dir)
    local list = Pass.seasons()
    local cur = Pass.season()
    for i, s in ipairs(list) do
        if s == cur and list[i + dir] then
            Pass.select(list[i + dir].id)
            PassView.open()
            return true
        end
    end
    return false
end

-- A short message over the track (e.g. "Reach tier 12 first")
function PassView.say(message)
    PassView.message, messageTime = message, 2.5
end

-- A claim happened: message + a burst of sparks at the card (or the screen centre)
function PassView.celebrate(message, tier)
    PassView.message, messageTime = message, 3
    local L = layout()
    local r = tier and L.cards[tier]
    local x, y = r and (r.x + r.w / 2) or L.sw / 2, r and (r.y + r.h / 2) or TRACK_Y + CARD_H / 2
    local colors = { GOLD, { 1, 1, 1 }, { 1, 0.5, 0.3 }, { 0.5, 0.9, 1 } }
    for i = 1, 28 do
        local a, v = math.random() * math.pi * 2, 120 + math.random() * 260
        particles[#particles + 1] = { x = x, y = y, vx = math.cos(a) * v, vy = math.sin(a) * v - 80,
            life = 0.7 + math.random() * 0.4, max = 1.1, size = 3 + math.random() * 4,
            color = colors[i % #colors + 1] }
    end
end

function PassView.update(dt)
    messageTime = messageTime - dt
    if messageTime <= 0 then PassView.message = nil end
    for i = #particles, 1, -1 do
        local p = particles[i]
        p.life = p.life - dt
        p.x, p.y, p.vy = p.x + p.vx * dt, p.y + p.vy * dt, p.vy + 420 * dt
        if p.life <= 0 then table.remove(particles, i) end
    end
end

---------------------------------------------------------------------------- drawing

local function panel(r, alpha)
    love.graphics.setColor(0.08, 0.1, 0.14, alpha or 0.92)
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 10, 10)
end

local function button(r, label, font, color, hover)
    love.graphics.setColor(0.05, 0.05, 0.1, 0.9)
    love.graphics.rectangle("fill", r.x - 2, r.y - 2, r.w + 4, r.h + 6, 12, 12)
    love.graphics.setColor(color[1] * 0.6, color[2] * 0.6, color[3] * 0.6)
    love.graphics.rectangle("fill", r.x, r.y + 4, r.w, r.h - 4, 10, 10)
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h - 4, 10, 10)
    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(label, r.x, r.y + (r.h - 4 - font:getHeight()) / 2, r.w, "center")
end

-- XP bar: x, y, w, h, fill 0..1
function PassView.drawBar(x, y, w, h, fill, color)
    love.graphics.setColor(0.05, 0.05, 0.1, 0.85)
    love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 4, h / 2 + 2, h / 2 + 2)
    love.graphics.setColor(0.25, 0.27, 0.32)
    love.graphics.rectangle("fill", x, y, w, h, h / 2, h / 2)
    if fill > 0 then
        local c = color or GOLD
        love.graphics.setColor(c)
        love.graphics.rectangle("fill", x, y, math.max(h, w * math.min(1, fill)), h, h / 2, h / 2)
        love.graphics.setColor(1, 1, 1, 0.25)
        love.graphics.rectangle("fill", x + 3, y + 2, math.max(0, w * math.min(1, fill) - 6), h * 0.3, 2, 2)
    end
end

local function drawCard(r, season, t, fonts, time)
    local bonus = t > #season.tiers
    local state = bonus and (Pass.bonusReady(season) > 0 and "ready" or "locked")
        or Pass.tierState(season, t)
    local reached = bonus and state == "ready" or (not bonus and Pass.level(season) >= t)
    panel(r)
    -- top strip with the tier number
    love.graphics.setColor(reached and GOLD or { 0.3, 0.32, 0.38 })
    love.graphics.rectangle("fill", r.x, r.y, r.w, 26, 10, 10)
    love.graphics.rectangle("fill", r.x, r.y + 14, r.w, 12)
    love.graphics.setFont(fonts.text)
    love.graphics.setColor(reached and { 0.15, 0.1, 0 } or { 1, 1, 1, 0.8 })
    love.graphics.printf(bonus and "BONUS" or ("TIER " .. t), r.x, r.y + 4, r.w, "center")

    local reward = bonus and { coins = Seasons.BONUS_COINS } or season.tiers[t]
    local dim = state == "locked"
    Decor.drawReward(reward, r.x + r.w / 2, r.y + 76, 84, fonts.text, dim)
    if dim then
        love.graphics.setColor(0.08, 0.1, 0.14, 0.45)
        love.graphics.rectangle("fill", r.x, r.y + 26, r.w, 100)
        Loot.drawLock(r.x + r.w - 22, r.y + 44, 0.3)
    end
    if state ~= "ready" then -- (a reward to claim shows a CLAIM button there)
        love.graphics.setFont(fonts.text)
        love.graphics.setColor(1, 1, 1, dim and 0.6 or 0.95)
        local text = bonus and (Seasons.BONUS_COINS .. " coins / " .. Seasons.BONUS_XP .. " XP")
            or Pass.rewardText(reward)
        love.graphics.printf(text, r.x + 6, r.y + 122, r.w - 12, "center")
    end

    if state == "claimed" then
        love.graphics.setColor(0.05, 0.05, 0.1, 0.35)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 10, 10)
        love.graphics.setColor(0.05, 0.05, 0.1)
        love.graphics.circle("fill", r.x + r.w - 20, r.y + 44, 15)
        love.graphics.setColor(DONE_GREEN)
        love.graphics.circle("fill", r.x + r.w - 20, r.y + 44, 12)
        love.graphics.setColor(1, 1, 1)
        love.graphics.setLineWidth(3)
        love.graphics.line(r.x + r.w - 26, r.y + 44, r.x + r.w - 21, r.y + 49, r.x + r.w - 13, r.y + 38)
        love.graphics.setLineWidth(1)
    elseif state == "ready" then -- pulsing outline + "CLAIM"
        local k = 0.5 + 0.5 * math.sin(time * 6)
        love.graphics.setColor(1, 0.85, 0.3, 0.6 + 0.4 * k)
        love.graphics.setLineWidth(3 + 2 * k)
        love.graphics.rectangle("line", r.x - 2, r.y - 2, r.w + 4, r.h + 4, 12, 12)
        love.graphics.setLineWidth(1)
        local pill = { x = r.x + 14, y = r.y + r.h - 40, w = r.w - 28, h = 28 }
        love.graphics.setColor(0.3, 0.75, 0.3)
        love.graphics.rectangle("fill", pill.x, pill.y, pill.w, pill.h, 13, 13)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(bonus and ("CLAIM x" .. Pass.bonusReady(season)) or "CLAIM",
            pill.x, pill.y + (pill.h - fonts.text:getHeight()) / 2, pill.w, "center")
    end
end

local function drawChallenge(r, fonts)
    local c = r.c
    panel(r, 0.85)
    local def = c.def
    local xp = c.weekly and Seasons.XP.weekly or Seasons.XP.daily
    love.graphics.setFont(fonts.text)
    love.graphics.setColor(c.done and DONE_GREEN or { 1, 1, 1 })
    local textW = r.w - 260
    love.graphics.printf(Seasons.describe(def), r.x + 14, r.y + 6, textW, "left")
    PassView.drawBar(r.x + 14, r.y + 32, textW - 70, 8, c.progress / def.n, c.done and DONE_GREEN or nil)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.print(c.progress .. " / " .. def.n, r.x + textW - 40, r.y + 26)
    love.graphics.setColor(GOLD)
    love.graphics.printf((c.done and "DONE  " or "") .. "+" .. xp .. " XP", r.x + textW, r.y + 15,
        r.reroll and 140 or 230, "right")
    if r.reroll then
        local b = r.reroll
        love.graphics.setColor(0.25, 0.45, 0.8)
        love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 8, 8)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Swap", b.x, b.y + (b.h - fonts.text:getHeight()) / 2, b.w, "center")
    end
end

-- fonts = { title, button, text }
function PassView.draw(fonts)
    local L = layout()
    local ui = uiScale()
    local time = love.timer.getTime()
    love.graphics.push()
    love.graphics.scale(ui)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, L.sw, L.sh)

    local season = L.season
    love.graphics.setFont(fonts.button)
    love.graphics.setColor(GOLD)
    love.graphics.printf("YARD PASS" .. (season and ("  -  " .. season.name:upper()) or ""),
        L.narrow and 24 or 0, 20, L.narrow and L.sw - 200 or L.sw, L.narrow and "left" or "center")
    Loot.drawCounter(Profile.coins, fonts.text, L.sw - 150, 38, 36)
    for _, name in ipairs({ "prev", "next" }) do
        local r = L[name]
        if r then
            love.graphics.setColor(1, 1, 1, 0.9)
            love.graphics.circle("fill", r.x + r.w / 2, r.y + r.h / 2, 22)
            love.graphics.setColor(0.1, 0.1, 0.15)
            local d = name == "next" and 1 or -1
            local cx, cy = r.x + r.w / 2, r.y + r.h / 2
            love.graphics.polygon("fill", cx + 9 * d, cy, cx - 6 * d, cy - 11, cx - 6 * d, cy + 11)
        end
    end

    if not season then
        love.graphics.setFont(fonts.text)
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.printf("No season has started yet.", 0, L.sh / 2 - 20, L.sw, "center")
    else
        local tier, into, need = Pass.level(season)
        local n = #season.tiers
        love.graphics.setFont(fonts.text)
        love.graphics.setColor(1, 1, 1)
        local label = (tier < n) and ("Tier " .. tier .. " of " .. n .. "   " .. into .. " / " .. need .. " XP")
            or ("All " .. n .. " tiers!   Next bonus: " .. into .. " / " .. need .. " XP")
        love.graphics.printf(label, 0, 62, L.sw, "center")
        PassView.drawBar(L.sw / 2 - 200, 86, 400, 10, into / need)

        local v = L.view
        love.graphics.setScissor(math.floor(v.x * ui), math.floor(v.y * ui), math.ceil(v.w * ui), math.ceil(v.h * ui))
        for i, r in ipairs(L.cards) do
            if r.x + r.w >= v.x and r.x <= v.x + v.w then drawCard(r, season, i, fonts, time) end
        end
        love.graphics.setScissor()

        love.graphics.setFont(fonts.text)
        local x0 = L.rows[1] and L.rows[1].x or 24
        love.graphics.setColor(1, 0.82, 0.3)
        love.graphics.print("DAILY CHALLENGES", x0, L.dailyHead)
        love.graphics.setColor(1, 1, 1, 0.55)
        local left = Seasons.REROLLS - Pass.rerolls
        love.graphics.print("new ones every day" .. (left > 0 and ("  -  " .. left .. " swap left") or ""),
            x0 + 200, L.dailyHead)
        if L.weeklyHead then
            love.graphics.setColor(1, 0.82, 0.3)
            love.graphics.print("WEEKLY CHALLENGE", x0, L.weeklyHead)
        end
        for _, r in ipairs(L.rows) do drawChallenge(r, fonts) end
    end

    if PassView.message then
        love.graphics.setFont(fonts.button)
        local w = fonts.button:getWidth(PassView.message) + 40
        love.graphics.setColor(0.05, 0.05, 0.1, 0.85)
        love.graphics.rectangle("fill", (L.sw - w) / 2, TRACK_Y + CARD_H / 2 - 24, w, 50, 12, 12)
        love.graphics.setColor(1, 0.88, 0.4)
        love.graphics.printf(PassView.message, 0, TRACK_Y + CARD_H / 2 - 12, L.sw, "center")
    end
    for _, p in ipairs(particles) do
        local c = p.color
        love.graphics.setColor(c[1], c[2], c[3], math.min(1, p.life / p.max * 1.5))
        love.graphics.circle("fill", p.x, p.y, p.size)
    end

    if L.claimAll then button(L.claimAll, "Claim all", fonts.button, { 0.3, 0.7, 0.3 }) end
    button(L.back, "Back", fonts.button, { 0.35, 0.37, 0.42 })

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

return PassView
