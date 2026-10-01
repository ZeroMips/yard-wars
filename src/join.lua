-- "Join LAN game" screen: address field + Connect / Back buttons, and below them the
-- games found in the local network (Join.games, from Net.newFinder) as buttons.
-- The field is in the upper part of the screen: the on-screen keyboard (opened only
-- when the field is tapped) covers the rest.
-- Laid out in HUD units (720 along the short screen side), like the menu.
local Join = {}

Join.address = ""
Join.status = nil -- e.g. "Could not connect"
Join.games = {}   -- { address, mode, waves, players }
Join.searching = nil -- e.g. "192.168.6.x"; "no network" / "not available" when it can't
Join.stats = nil     -- discovery counters (small, under the list)

local SAVE_FILE = "last_host.txt"
local MAX_LEN = 64

local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end

local GAMES_Y, GAME_H, GAME_GAP = 370, 60, 10

local function layout()
    local ui = uiScale()
    local sw, sh = love.graphics.getWidth() / ui, love.graphics.getHeight() / ui
    local w = math.min(460, sw - 40)
    local x = (sw - w) / 2
    local bw = (w - 20) / 2
    local rects = {
        field   = { x = x, y = 130, w = w, h = 64 },
        connect = { x = x, y = 214, w = bw, h = 64 },
        back    = { x = x + bw + 20, y = 214, w = bw, h = 64 },
        games   = {},
    }
    for i = 1, #Join.games do
        local y = GAMES_Y + (i - 1) * (GAME_H + GAME_GAP)
        if y + GAME_H > sh - 10 then break end -- no room for more
        rects.games[i] = { x = x, y = y, w = w, h = GAME_H }
    end
    return rects, sw
end

-- Phones: the on-screen keyboard only comes up when the field is tapped (it would
-- hide the list of found games). Desktop: text input stays on.
local touchDevice = love.system.getOS() == "Android" or love.system.getOS() == "iOS"

function Join.open()
    local saved = love.filesystem.getInfo(SAVE_FILE) and love.filesystem.read(SAVE_FILE)
    Join.address = saved and saved:match("^%s*(.-)%s*$") or Join.address
    if not touchDevice then love.keyboard.setTextInput(true) end
end

function Join.close()
    if touchDevice then love.keyboard.setTextInput(false) end
end

-- One line describing a found game
function Join.describe(g)
    return string.format("%s  -  %s  -  %d player%s", g.waves and "Waves (co-op)" or "Duel",
        g.address, g.players, g.players == 1 and "" or "s")
end

-- Remember the address for next time
function Join.save()
    love.filesystem.write(SAVE_FILE, Join.address)
end

function Join.textinput(t)
    t = t:gsub("[^%w%.%-:]", "")
    Join.address = (Join.address .. t):sub(1, MAX_LEN)
end

-- Returns "connect", "back" or nil
function Join.keypressed(key)
    if key == "backspace" then
        Join.address = Join.address:sub(1, -2)
    elseif key == "return" or key == "kpenter" then
        return "connect"
    elseif key == "escape" then
        return "back"
    end
end

-- Screen position -> "field", "connect", "back", "game" + index, or nil
function Join.hit(x, y)
    local ui = uiScale()
    x, y = x / ui, y / ui
    local function inside(r) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end
    local rects = layout()
    for _, name in ipairs({ "field", "connect", "back" }) do
        if inside(rects[name]) then return name end
    end
    for i, r in ipairs(rects.games) do
        if inside(r) then return "game", i end
    end
end

function Join.draw(fonts)
    local rects, sw = layout()
    local sh = love.graphics.getHeight() / uiScale()
    love.graphics.push()
    love.graphics.scale(uiScale())

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    love.graphics.setFont(fonts.button)
    love.graphics.setColor(1, 0.8, 0.2)
    love.graphics.printf("Join LAN game", 0, 30, sw, "center")
    love.graphics.setFont(fonts.text)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.printf("Address of the host (shown on its screen)", 0, 80, sw, "center")

    local f = rects.field
    love.graphics.setColor(0.1, 0.12, 0.15, 0.95)
    love.graphics.rectangle("fill", f.x, f.y, f.w, f.h, 10, 10)
    love.graphics.setColor(1, 0.6, 0.2)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", f.x, f.y, f.w, f.h, 10, 10)
    love.graphics.setFont(fonts.button)
    love.graphics.setColor(1, 1, 1)
    local cursor = (love.timer.getTime() % 1 < 0.5) and "_" or " "
    love.graphics.printf(Join.address .. cursor, f.x + 12, f.y + 14, f.w - 24, "left")

    for _, name in ipairs({ "connect", "back" }) do
        local r = rects[name]
        love.graphics.setColor(0.1, 0.12, 0.15, 0.9)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 10, 10)
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 10, 10)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(name == "connect" and "Connect" or "Back", r.x, r.y + 14, r.w, "center")
    end
    love.graphics.setLineWidth(1)

    love.graphics.setFont(fonts.text)
    if Join.status then
        love.graphics.setColor(1, 0.55, 0.3)
        love.graphics.printf(Join.status, 0, 296, sw, "center")
    end

    -- Games found in the network
    love.graphics.setColor(1, 1, 1, 0.8)
    local dots = string.rep(".", math.floor(love.timer.getTime() * 2) % 4)
    local where = Join.searching and (" (" .. Join.searching .. ")") or ""
    love.graphics.printf(#Join.games == 0 and ("Searching for games in your Wi-Fi" .. where .. " " .. dots)
        or "Games in your Wi-Fi - tap to join:", 0, GAMES_Y - 32, sw, "center")
    for i, r in ipairs(rects.games) do
        love.graphics.setColor(0.1, 0.12, 0.15, 0.9)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 10, 10)
        love.graphics.setColor(0.4, 0.85, 0.4)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 10, 10)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(Join.describe(Join.games[i]), r.x + 10, r.y + 20, r.w - 20, "center")
    end
    if Join.stats then -- below the list
        love.graphics.setColor(1, 1, 1, 0.4)
        love.graphics.printf(Join.stats, 0, GAMES_Y + #rects.games * (GAME_H + GAME_GAP), sw, "center")
    end

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

return Join
