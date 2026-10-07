-- Start screen in the style of a mobile game lobby: the chosen rowdy big in the
-- middle (arrows to switch, ROWDIES opens the card overview), the chosen mode on a
-- card at the bottom right (tap: list of all modes) and a big PLAY button.
-- Works with mouse, touch and keyboard (left/right rowdy, up/down mode, Enter play).
-- A rowdy that isn't bought yet (src/profile.lua) is shown dark with its price, and
-- PLAY turns into an UNLOCK button (a pass rowdy: YARD PASS + its tier, opens the pass); the coins are shown next to the logo.
-- YARD PASS (season, tier, XP bar, a still red dot while a reward waits) opens the pass
-- screen (src/passview.lua), STYLE the cosmetics (src/wardrobe.lua); the rowdy is shown
-- with its skin, the pedestal, badge and title that are put on.
-- Laid out in HUD units (720 along the short screen side), like the in-game HUD;
-- landscape and portrait have their own layout.
local Assets   = require("src.assets")
local Rowdies = require("src.rowdies")
local Loot     = require("src.loot")
local Profile  = require("src.profile")
local Pass     = require("src.pass")
local Decor    = require("src.decor")
local Seasons  = require("src.seasons")
local PassView = require("src.passview")

local Menu = {}

Menu.entries = {}       -- modes to choose from (set by main.lua): { id, name, description,
                        --   icon = "duel"|"team"|"waves"|"join", lan = bool, ... }
Menu.mode = 1           -- index into Menu.entries
Menu.rowdy = 1        -- index into Rowdies
Menu.modesOpen = false  -- the mode list is shown over the lobby
Menu.hover = nil        -- what the mouse is over (highlighted)
Menu.message = nil      -- shown under the title (e.g. "Connection lost")
Menu.notice = nil       -- shown under the rowdy's stats (e.g. "Gunner unlocked!")

-- Build shown in the corner: build.txt + version.txt (commit + date) are written by
-- tools/build.sh and when the game is copied to a device, so it's easy to see which code
-- a phone runs (a mounted update's files win).
local function readTrimmed(name)
    return love.filesystem.getInfo(name) and (love.filesystem.read(name):gsub("%s+$", ""))
end
Menu.version = (readTrimmed("build.txt") and "build " .. readTrimmed("build.txt") .. "  " or "")
    .. (readTrimmed("version.txt") or "dev")
Menu.status = nil -- update check ("up to date", ...), shown after the version

local SAVE_FILE = "lobby.txt" -- last rowdy + mode: "<rowdy index> <mode id>"

local MODE_COLORS = {
    duel  = { 0.95, 0.5, 0.15 },
    team  = { 0.25, 0.55, 0.95 },
    waves = { 0.65, 0.3, 0.85 },
    join  = { 0.2, 0.7, 0.45 },
}
local PLAY_COLOR     = { 1, 0.78, 0.1 }
local ROWDIES_COLOR = { 0.2, 0.5, 0.9 }
local UNLOCK_COLOR   = { 0.3, 0.75, 0.3 }
local LOCKED_COLOR   = { 0.42, 0.44, 0.5 }
local LOCKED_TINT    = { 0.12, 0.12, 0.18 }
local PASS_COLOR     = { 0.55, 0.3, 0.75 }
local STYLE_COLOR    = { 0.85, 0.4, 0.55 }

local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end

-- Blue tint over the arena behind the lobby, darker towards the bottom (unit square,
-- scaled to the screen when drawn)
local tint = love.graphics.newMesh({
    { 0, 0, 0, 0, 0.04, 0.1, 0.3, 0.45 }, { 1, 0, 0, 0, 0.04, 0.1, 0.3, 0.45 },
    { 1, 1, 0, 0, 0.03, 0.06, 0.2, 0.8 }, { 0, 1, 0, 0, 0.03, 0.06, 0.2, 0.8 },
}, "fan", "static")

-- Call after Profile.load(): a saved rowdy that isn't unlocked gives way to the starter
function Menu.load()
    local s = love.filesystem.getInfo(SAVE_FILE) and love.filesystem.read(SAVE_FILE) or ""
    local b, id = s:match("^(%d+)%s+(%S+)")
    if Rowdies[tonumber(b)] then Menu.rowdy = tonumber(b) end
    if not Profile.isUnlocked(Rowdies[Menu.rowdy]) then
        for i, def in ipairs(Rowdies) do
            if def.name == Profile.STARTER then Menu.rowdy = i end
        end
    end
    for i, e in ipairs(Menu.entries) do
        if e.id == id then Menu.mode = i end
    end
end

-- The rowdy shown in the lobby isn't bought yet (PLAY becomes UNLOCK)
function Menu.locked()
    return not Profile.isUnlocked(Rowdies[Menu.rowdy])
end

function Menu.save()
    love.filesystem.write(SAVE_FILE, Menu.rowdy .. " " .. Menu.entries[Menu.mode].id)
end

function Menu.entry() return Menu.entries[Menu.mode] end

-- ---- Layout (HUD units) ----

local function lobbyLayout()
    local ui = uiScale()
    local sw, sh = love.graphics.getWidth() / ui, love.graphics.getHeight() / ui
    local L = { sw = sw, sh = sh, portrait = sw < sh * 1.2 }
    local m = 24
    if not L.portrait then
        L.play = { x = sw - m - 210, y = sh - m - 110, w = 210, h = 110 }
        L.mode = { x = L.play.x - 16 - 370, y = L.play.y, w = 370, h = 110 }
        L.rowdies = { x = m, y = sh / 2 - 45, w = 170, h = 90 }
        L.pass = { x = m, y = L.rowdies.y - 16 - 110, w = 210, h = 110 }
        L.style = { x = m, y = L.rowdies.y + L.rowdies.h + 16, w = 170, h = 70 }
        L.cx, L.cy, L.k = math.min(sw * 0.45, L.mode.x - 40), sh * 0.46, 1
    else
        L.play = { x = m, y = sh - m - 110, w = sw - 2 * m, h = 110 }
        L.rowdies = { x = m, y = L.play.y - 16 - 110, w = 170, h = 110 }
        L.mode = { x = m + 170 + 16, y = L.rowdies.y, w = sw - 2 * m - 170 - 16, h = 110 }
        L.style = { x = m, y = L.rowdies.y - 16 - 110, w = 170, h = 110 }
        L.pass = { x = m + 170 + 16, y = L.style.y, w = sw - 2 * m - 170 - 16, h = 110 }
        -- the stage gets the room above the buttons (shrinks on almost square windows)
        local room = L.pass.y - 60
        L.k = math.min(1.25, room / 560)
        L.cx, L.cy = sw / 2, 60 + room * 0.5
    end
    L.version = { x = 0, y = sh - 30, w = 320, h = 30 } -- tapped 7 times: test mode
    local k = L.k
    L.prev = { x = L.cx - 230 * k - 36, y = L.cy - 36, w = 72, h = 72 }
    L.next = { x = L.cx + 230 * k - 36, y = L.cy - 36, w = 72, h = 72 }
    return L
end

-- Mode list: solo modes and LAN modes, two columns (landscape) or one (portrait)
local function modesLayout()
    local ui = uiScale()
    local sw, sh = love.graphics.getWidth() / ui, love.graphics.getHeight() / ui
    local cards, heads = {}, {}
    local groups = { {}, {} }
    for i, e in ipairs(Menu.entries) do table.insert(groups[e.lan and 2 or 1], i) end
    local twoCols = sw >= 2 * 360 + 100
    local W = twoCols and math.min(420, (sw - 100) / 2) or math.min(460, sw - 48)
    local H, GAP = twoCols and 84 or 80, 12
    local x1 = twoCols and (sw / 2 - W - 20) or (sw - W) / 2
    local x2 = twoCols and (sw / 2 + 20) or x1
    local y = 110
    for g, list in ipairs(groups) do
        local x = (g == 1) and x1 or x2
        if twoCols then y = 110 end
        heads[g] = { x = x, y = y }
        y = y + 34
        for _, i in ipairs(list) do
            cards[i] = { x = x, y = y, w = W, h = H }
            y = y + H + GAP
        end
        y = y + 16
    end
    local closeY = twoCols and (110 + 34 + 4 * (H + GAP) + 10) or y
    return { cards = cards, heads = heads, sw = sw, sh = sh,
             close = { x = (sw - 200) / 2, y = math.min(closeY, sh - 90), w = 200, h = 64 } }
end

local function inside(r, x, y) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

-- Screen position -> "play", "prev", "next", "rowdies", "pass", "style", "mode", "version"
-- (the build line, see Profile.testMode), "pick" + index (mode
-- list), "close" (mode list: the OK button), "outside" (mode list: elsewhere) or nil
function Menu.hit(x, y)
    local ui = uiScale()
    x, y = x / ui, y / ui
    if Menu.modesOpen then
        local L = modesLayout()
        for i, r in pairs(L.cards) do
            if inside(r, x, y) then return "pick", i end
        end
        return inside(L.close, x, y) and "close" or "outside"
    end
    local L = lobbyLayout()
    for _, name in ipairs({ "play", "mode", "rowdies", "pass", "style", "prev", "next", "version" }) do
        if inside(L[name], x, y) and (name ~= "pass" or Pass.season()) then return name end
    end
end

-- Keyboard: returns "play", "rowdies", "pass", "style", "close", "quit" or nil (switching
-- is done here)
function Menu.keypressed(key)
    local n = #Menu.entries
    if Menu.modesOpen then
        if key == "up" or key == "w" then Menu.mode = (Menu.mode - 2) % n + 1
        elseif key == "down" or key == "s" then Menu.mode = Menu.mode % n + 1
        elseif key == "return" or key == "kpenter" or key == "space" or key == "escape" then
            return "close"
        end
        return nil
    end
    if key == "left" or key == "a" then Menu.rowdy = (Menu.rowdy - 2) % #Rowdies + 1
    elseif key == "right" or key == "d" then Menu.rowdy = Menu.rowdy % #Rowdies + 1
    elseif key == "up" or key == "w" then Menu.mode = (Menu.mode - 2) % n + 1
    elseif key == "down" or key == "s" then Menu.mode = Menu.mode % n + 1
    elseif key == "return" or key == "kpenter" or key == "space" then return "play"
    elseif key == "b" or key == "tab" then return "rowdies"
    elseif key == "p" and Pass.season() then return "pass"
    elseif key == "y" then return "style"
    elseif key == "escape" then return "quit" end
end

-- ---- Drawing helpers ----

-- Text with a dark outline (reads on any background)
local function outlined(text, font, x, y, w, align, color, thick)
    love.graphics.setFont(font)
    local t = thick or 2
    love.graphics.setColor(0.05, 0.05, 0.1, (color[4] or 1))
    for dx = -t, t, t do
        for dy = -t, t + 1, t do
            if dx ~= 0 or dy ~= 0 then love.graphics.printf(text, x + dx, y + dy, w, align) end
        end
    end
    love.graphics.setColor(color)
    love.graphics.printf(text, x, y, w, align)
end

local function darker(c, f) return { c[1] * f, c[2] * f, c[3] * f, c[4] or 1 } end

-- Chunky button: darker bottom edge, highlight on top, dark outline
local function block(r, color, hover)
    local c = hover and { math.min(1, color[1] * 1.12), math.min(1, color[2] * 1.12),
        math.min(1, color[3] * 1.12) } or color
    love.graphics.setColor(0.05, 0.05, 0.1, 0.9)
    love.graphics.rectangle("fill", r.x - 3, r.y - 3, r.w + 6, r.h + 9, 14, 14)
    love.graphics.setColor(darker(c, 0.6))
    love.graphics.rectangle("fill", r.x, r.y + 6, r.w, r.h - 6 + 0, 12, 12)
    love.graphics.setColor(c)
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h - 4, 12, 12)
    love.graphics.setColor(1, 1, 1, 0.22)
    love.graphics.rectangle("fill", r.x + 6, r.y + 4, r.w - 12, (r.h - 4) * 0.35, 8, 8)
end

-- Small mode icons, drawn from shapes (centre cx, cy; size s)
local function drawIcon(kind, cx, cy, s)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.setLineWidth(math.max(2, s * 0.12))
    if kind == "duel" then -- crossed swords
        for _, d in ipairs({ 1, -1 }) do
            love.graphics.line(cx - s * 0.6 * d, cy + s * 0.6, cx + s * 0.6 * d, cy - s * 0.6)
            love.graphics.line(cx - s * 0.55 * d, cy + s * 0.2, cx - s * 0.2 * d, cy + s * 0.55)
        end
    elseif kind == "team" then -- three heads
        for i, ox in ipairs({ -0.55, 0.55, 0 }) do
            local y = cy + (i == 3 and -s * 0.1 or s * 0.05)
            love.graphics.circle("fill", cx + ox * s, y - s * 0.3, s * 0.2)
            love.graphics.arc("fill", cx + ox * s, y + s * 0.35, s * 0.33, math.pi, math.pi * 2)
        end
    elseif kind == "waves" then -- three wavy lines
        for row = -1, 1 do
            local pts = {}
            for i = 0, 12 do
                local t = i / 12
                pts[#pts + 1] = cx - s * 0.7 + t * s * 1.4
                pts[#pts + 1] = cy + row * s * 0.42 + math.sin(t * math.pi * 3) * s * 0.12
            end
            love.graphics.line(pts)
        end
    else -- join: wifi arcs
        love.graphics.circle("fill", cx, cy + s * 0.5, s * 0.12)
        for i = 1, 3 do
            love.graphics.arc("line", "open", cx, cy + s * 0.5, s * 0.35 * i,
                -math.pi * 0.75, -math.pi * 0.25)
        end
    end
    love.graphics.setLineWidth(1)
end

local function drawArrow(r, dir, hover)
    local cx, cy = r.x + r.w / 2, r.y + r.h / 2
    love.graphics.setColor(0.05, 0.05, 0.1, 0.85)
    love.graphics.circle("fill", cx, cy + 3, 34)
    love.graphics.setColor(hover and { 1, 0.85, 0.3 } or { 1, 1, 1, 0.9 })
    love.graphics.circle("fill", cx, cy, 30)
    love.graphics.setColor(0.1, 0.1, 0.15)
    love.graphics.polygon("fill", cx + 12 * dir, cy, cx - 8 * dir, cy - 15, cx - 8 * dir, cy + 15)
end

local function attackText(st)
    local n = st.pellets or 1
    return (n > 1) and (n .. " x " .. st.damage) or tostring(st.damage)
end

-- Chips under the pedestal: HP, attack, super
local function drawStats(def, cx, y, font)
    local st = def.stats
    local chips = { { "HP", tostring(st.hp), { 0.3, 0.8, 0.35 } },
                    { "ATTACK", attackText(st), { 0.95, 0.45, 0.25 } } }
    if st.super then chips[#chips + 1] = { "SUPER", st.super.name, { 1, 0.78, 0.1 } } end
    love.graphics.setFont(font)
    local widths, total = {}, 0
    for i, c in ipairs(chips) do
        widths[i] = font:getWidth(c[1] .. "  " .. c[2]) + 28
        total = total + widths[i] + (i > 1 and 10 or 0)
    end
    local x = cx - total / 2
    for i, c in ipairs(chips) do
        love.graphics.setColor(0.05, 0.05, 0.1, 0.75)
        love.graphics.rectangle("fill", x, y, widths[i], 32, 16, 16)
        love.graphics.setColor(c[3])
        love.graphics.print(c[1], x + 14, y + 7)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(c[2], x + 14 + font:getWidth(c[1] .. "  "), y + 7)
        x = x + widths[i] + 10
    end
end

-- The chosen rowdy on a lit pedestal, name and role above, stats below
local function drawStage(L, fonts, t)
    local def = Rowdies[Menu.rowdy]
    local locked = not Profile.isUnlocked(def)
    local cx, cy, k = L.cx, L.cy, L.k
    -- spotlight
    for i = 8, 1, -1 do
        love.graphics.setColor(1, 0.9, 0.55, 0.035)
        love.graphics.circle("fill", cx, cy, (110 + i * 22) * k)
    end
    -- pedestal (the default one or a Yard Pass pedestal)
    local py = cy + 120 * k
    if not Decor.drawPedestal(Pass.equippedId("pedestal"), cx, py, k, t) then
        love.graphics.setColor(0.05, 0.05, 0.1, 0.85)
        love.graphics.ellipse("fill", cx, py + 10 * k, 160 * k, 46 * k)
        love.graphics.setColor(0.2, 0.25, 0.35, 1)
        love.graphics.ellipse("fill", cx, py, 156 * k, 42 * k)
        love.graphics.setColor(1, 0.8, 0.3, 0.7)
        love.graphics.setLineWidth(4)
        love.graphics.ellipse("line", cx, py, 156 * k, 42 * k)
        love.graphics.setLineWidth(1)
    end
    -- the rowdy: gentle idle bob and sway
    local bob = math.sin(t * 2.2) * 6 * k
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.ellipse("fill", cx, py, (70 - bob * 0.6) * k, 18 * k)
    -- side view standing on the pedestal (breathing: grows and shrinks a little)
    local tint = locked and LOCKED_TINT or nil
    local skin = Pass.skinFor(def)
    if not Assets.drawStanding(def, cx, py + 6 * k, (290 + bob * 0.5) * k,
        math.sin(t * 1.3) * 0.02, tint, skin) then
        Assets.drawPortrait(def, cx, cy - 20 * k + bob, 260 * k, math.sin(t * 1.3) * 0.05, tint, skin)
    end
    if locked then Loot.drawLock(cx, cy - 20 * k, 1.4 * k) end
    -- name + role
    outlined(def.name:upper(), fonts.title, cx - 300, cy - 250 * k - 20, 600, "center", { 1, 1, 1 }, 3)
    local badge = Pass.equippedId("badge")
    if badge then
        Decor.drawBadge(badge, cx - fonts.title:getWidth(def.name:upper()) / 2 - 30, cy - 250 * k + 10, 18)
    end
    outlined(def.role or "", fonts.text, cx - 300, cy - 250 * k + 46, 600, "center", { 1, 0.82, 0.3 })
    drawStats(def, cx, py + 62 * k, fonts.text)
    -- the title, or a notice in its place (e.g. "Gunner unlocked!")
    if Menu.notice then
        outlined(Menu.notice, fonts.text, cx - 320, py + 62 * k + 44, 640, "center", { 1, 0.85, 0.35 }, 1)
    elseif Pass.equippedId("title") then
        Decor.drawTitle(Pass.equippedId("title"), fonts.text, cx, py + 62 * k + 56)
    end
end

local function drawModeCard(r, e, fonts, hover, showHint)
    local col = MODE_COLORS[e.icon] or MODE_COLORS.duel
    block(r, col, hover)
    drawIcon(e.icon, r.x + 46, r.y + r.h / 2 - 4, math.min(26, r.h * 0.26))
    local tx, tw = r.x + 84, r.w - 96
    if showHint then
        outlined(e.lan and "LAN GAME" or "MODE", fonts.text, tx, r.y + 10, tw, "left", { 1, 1, 1, 0.85 }, 1)
    end
    outlined(e.name, fonts.button, tx, r.y + (showHint and 30 or 8), tw, "left", { 1, 1, 1 })
    love.graphics.setFont(fonts.text)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.printf(e.description, tx, r.y + (showHint and 64 or 42), tw, "left")
    if showHint then -- "tap to change" marker
        love.graphics.setColor(1, 1, 1, 0.9)
        local ax, ay = r.x + r.w - 22, r.y + 22
        love.graphics.polygon("fill", ax - 7, ay - 8, ax + 5, ay, ax - 7, ay + 8)
    end
end

local function drawModes(fonts)
    local L = modesLayout()
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, L.sw, L.sh)
    outlined("CHOOSE A MODE", fonts.button, 0, 40, L.sw, "center", { 1, 0.82, 0.2 })
    for g, h in ipairs(L.heads) do
        outlined(g == 1 and "PLAY" or "LAN - WITH FRIENDS IN YOUR WI-FI", fonts.text,
            h.x, h.y, 420, "left", { 1, 1, 1, 0.8 }, 1)
    end
    for i, r in pairs(L.cards) do
        drawModeCard(r, Menu.entries[i], fonts, Menu.hover == "pick" .. i, false)
        if i == Menu.mode then
            love.graphics.setColor(1, 1, 1)
            love.graphics.setLineWidth(4)
            love.graphics.rectangle("line", r.x - 6, r.y - 6, r.w + 12, r.h + 15, 16, 16)
            love.graphics.setLineWidth(1)
        end
    end
    block(L.close, { 0.35, 0.37, 0.42 }, Menu.hover == "close")
    outlined("OK", fonts.button, L.close.x, L.close.y + 14, L.close.w, "center", { 1, 1, 1 })
end

-- fonts = { title, button, text }
function Menu.draw(fonts, touchMode)
    local L = lobbyLayout()
    local t = love.timer.getTime()
    love.graphics.push()
    love.graphics.scale(uiScale())

    -- Dim the arena in the background and tint it blue, darker towards the bottom
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", 0, 0, L.sw, L.sh)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(tint, 0, 0, 0, L.sw, L.sh)

    outlined("YARD WARS", fonts.button, 24, 18, 400, "left", { 1, 0.8, 0.2 })
    Loot.drawCounter(Profile.coins, fonts.text, 24 + fonts.button:getWidth("YARD WARS") + 24, 34, 36)
    if Menu.message then
        outlined(Menu.message, fonts.text, 24, 54, L.sw - 48, "left", { 1, 0.55, 0.3 }, 1)
    end

    drawStage(L, fonts, t)
    drawArrow(L.prev, -1, Menu.hover == "prev")
    drawArrow(L.next, 1, Menu.hover == "next")

    -- ROWDIES: a small grid of cards as icon
    block(L.rowdies, ROWDIES_COLOR, Menu.hover == "rowdies")
    local b = L.rowdies
    love.graphics.setColor(1, 1, 1, 0.95)
    for i = 0, 2 do
        love.graphics.rectangle("fill", b.x + b.w / 2 - 33 + i * 23, b.y + 14, 20, 26, 3, 3)
    end
    outlined("ROWDIES", fonts.button, b.x, b.y + b.h - 44, b.w, "center", { 1, 1, 1 })

    -- YARD PASS: season, tier, XP bar; red dot while something can be claimed
    local season = Pass.season()
    if season then
        local r = L.pass
        block(r, PASS_COLOR, Menu.hover == "pass")
        local tier, into, need = Pass.level(season)
        outlined("YARD PASS", fonts.button, r.x + 14, r.y + 8, r.w - 28, "left", { 1, 1, 1 })
        outlined(season.name, fonts.text, r.x + 14, r.y + 40, r.w - 28, "left", { 1, 0.85, 0.5 }, 1)
        outlined("Tier " .. tier, fonts.text, r.x + 14, r.y + 40, r.w - 28, "right", { 1, 1, 1 }, 1)
        PassView.drawBar(r.x + 14, r.y + 72, r.w - 28, 12, into / need)
        if Pass.claimable() > 0 then -- a calm dot, no pulsing (CHARTER.md: no nagging)
            love.graphics.setColor(0.05, 0.05, 0.1)
            love.graphics.circle("fill", r.x + r.w - 4, r.y + 4, 15)
            love.graphics.setColor(1, 0.25, 0.2)
            love.graphics.circle("fill", r.x + r.w - 4, r.y + 4, 12)
            love.graphics.setColor(1, 1, 1)
            love.graphics.setFont(fonts.text)
            love.graphics.printf("!", r.x + r.w - 24, r.y + 4 - fonts.text:getHeight() / 2, 40, "center")
        end
    end

    -- STYLE: a little hanger
    local st = L.style
    block(st, STYLE_COLOR, Menu.hover == "style")
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.setLineWidth(4)
    local hx, hy = st.x + st.w / 2, st.y + 14
    love.graphics.arc("line", "open", hx, hy + 4, 6, math.pi, math.pi * 2.6)
    love.graphics.line(hx, hy + 10, hx - 26, hy + 26, hx + 26, hy + 26, hx, hy + 10)
    love.graphics.setLineWidth(1)
    outlined("STYLE", fonts.button, st.x, st.y + st.h - 40, st.w, "center", { 1, 1, 1 })

    drawModeCard(L.mode, Menu.entry(), fonts, Menu.hover == "mode", true)

    -- PLAY: pulses gently
    local p = L.play
    local s = 1 + 0.03 * math.sin(t * 4)
    love.graphics.push()
    love.graphics.translate(p.x + p.w / 2, p.y + p.h / 2)
    love.graphics.scale(s)
    love.graphics.translate(-(p.x + p.w / 2), -(p.y + p.h / 2))
    if Menu.locked() and Rowdies[Menu.rowdy].pass then -- YARD PASS + tier (opens the pass)
        local _, tier = Seasons.rowdyTier(Rowdies[Menu.rowdy].name)
        block(p, PASS_COLOR, Menu.hover == "play")
        outlined("YARD PASS", fonts.button, p.x, p.y + 14, p.w, "center", { 1, 1, 1 })
        outlined("Tier " .. tier, fonts.button, p.x, p.y + 54, p.w, "center", { 1, 0.88, 0.35 })
    elseif Menu.locked() then -- UNLOCK + price instead (grey while there are too few coins)
        local def = Rowdies[Menu.rowdy]
        local afford = Profile.canAfford(def)
        block(p, afford and UNLOCK_COLOR or LOCKED_COLOR, Menu.hover == "play")
        outlined("UNLOCK", fonts.button, p.x, p.y + 14, p.w, "center", { 1, 1, 1 })
        local price = tostring(def.price)
        local w = 34 + fonts.button:getWidth(price)
        local x = p.x + (p.w - w) / 2
        Loot.drawCoin(x + 13, p.y + 70, 12)
        outlined(price, fonts.button, x + 34, p.y + 54, 200, "left",
            afford and { 1, 1, 1 } or { 1, 0.75, 0.7 })
    else
        block(p, PLAY_COLOR, Menu.hover == "play")
        outlined(Menu.entry().join and "JOIN" or "PLAY", fonts.title, p.x, p.y + p.h / 2 - 36,
            p.w, "center", { 1, 1, 1 }, 3)
    end
    love.graphics.pop()

    love.graphics.setFont(fonts.text)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.print(Menu.version .. (Menu.status and "  -  " .. Menu.status or ""), 8, L.sh - 24)
    if Profile.testMode then
        local w = fonts.text:getWidth("TEST MODE") + 16
        local x = 16 + fonts.text:getWidth(Menu.version .. (Menu.status and "  -  " .. Menu.status or ""))
        love.graphics.setColor(0.85, 0.15, 0.15, 0.9)
        love.graphics.rectangle("fill", x, L.sh - 27, w, 24, 6, 6)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("TEST MODE", x + 8, L.sh - 24)
    end
    if not touchMode and not L.portrait then
        love.graphics.setColor(1, 1, 1, 0.45)
        love.graphics.printf("Left/Right rowdy  -  Up/Down mode  -  Enter play  -  P pass  -  Esc quit",
            0, 24, L.sw - 24, "right")
    end

    if Menu.modesOpen then drawModes(fonts) end

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

-- Mouse hover (for the highlight)
function Menu.mousemoved(x, y)
    local what, i = Menu.hit(x, y)
    Menu.hover = what and (what .. (i or "")) or nil
end

return Menu
