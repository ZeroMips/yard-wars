-- The player's nick: a short name that says who you are in a LAN game (waiting room,
-- name tag above the rowdy, result screen) and who is hosting (join screen).
-- It lives in `nick.txt` on this device and only ever goes to the devices in the same
-- Wi-Fi that join or host a game with you (CHARTER.md: nothing leaves the local network).
-- Edit screen (state "nick" in main.lua): a text field + OK; the lobby shows it as a chip.
local utf8 = require("utf8")

local Nick = {}

Nick.MAX = 12          -- characters
Nick.name = "Player"   -- the saved nick (Nick.load)
Nick.editing = nil     -- the text while the edit screen is open
Nick.visible = true    -- friends in the same Wi-Fi may see this device in the lobby and
                       -- invite it (second line of nick.txt: "hidden" = off)

local FILE = "nick.txt"

local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end

-- Letters (also German umlauts), digits, space, - and _ ; at most MAX characters, no
-- leading/trailing/double spaces. Used for the own input and for names from the network.
function Nick.clean(s)
    if type(s) ~= "string" then return "" end
    local out, n = {}, 0
    for _, cp in utf8.codes(s) do
        local ok = (cp >= 48 and cp <= 57) or (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122)
            or cp == 32 or cp == 45 or cp == 95 or (cp >= 0xC0 and cp <= 0x24F)
        if ok then
            n = n + 1
            if n > Nick.MAX then break end
            out[n] = utf8.char(cp)
        end
    end
    return (table.concat(out):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- utf8.codes raises on broken input (a damaged packet): treat that as "no name"
local function safeClean(s)
    local ok, v = pcall(Nick.clean, s)
    return ok and v or ""
end
Nick.safe = safeClean

-- A name for somebody without one ("Player 3")
function Nick.fallback(id) return "Player " .. tostring(id) end

function Nick.load()
    local raw = love.filesystem.getInfo(FILE) and love.filesystem.read(FILE) or ""
    local first, second = raw:match("^([^\n]*)\n?([^\n]*)")
    local s = safeClean(first or "")
    Nick.visible = (second or ""):match("^%s*hidden") == nil
    if s == "" then
        s = "Player" .. love.math.random(10, 99)
        Nick.name = s
        Nick.save()
    end
    Nick.name = s
end

function Nick.save()
    love.filesystem.write(FILE, Nick.name .. "\n" .. (Nick.visible and "visible" or "hidden") .. "\n")
end

---------------------------------------------------------------------------- edit screen

local touchDevice = love.system.getOS() == "Android" or love.system.getOS() == "iOS"

local function layout()
    local ui = uiScale()
    local sw, sh = love.graphics.getWidth() / ui, love.graphics.getHeight() / ui
    local w = math.min(460, sw - 40)
    local x = (sw - w) / 2
    return { field = { x = x, y = 150, w = w, h = 64 }, ok = { x = x, y = 234, w = w, h = 64 },
             visible = { x = x, y = 330, w = w, h = 64 } }, sw, sh
end

function Nick.open()
    Nick.editing = Nick.name
    Nick.fresh = true -- the first typed letter replaces the old nick
    if not touchDevice then love.keyboard.setTextInput(true) end
end

-- Leaves the screen: keeps the new nick unless it came out empty
function Nick.close()
    local s = safeClean(Nick.editing or "")
    if s ~= "" then
        Nick.name = s
        Nick.save()
    end
    Nick.editing = nil
    if touchDevice then love.keyboard.setTextInput(false) end
end

function Nick.textinput(t)
    if not Nick.editing then return end
    if Nick.fresh then Nick.editing, Nick.fresh = "", false end
    Nick.editing = safeClean(Nick.editing .. t):sub(1, Nick.MAX * 4)
end

-- Returns "done" or nil
function Nick.keypressed(key)
    if not Nick.editing then return end
    if key ~= "return" and key ~= "kpenter" and key ~= "escape" then Nick.fresh = false end
    if key == "backspace" then
        local off = utf8.offset(Nick.editing, -1)
        Nick.editing = off and Nick.editing:sub(1, off - 1) or ""
    elseif key == "return" or key == "kpenter" or key == "escape" then
        return "done"
    end
end

-- Friends in the Wi-Fi can invite me: on / off (saved at once)
function Nick.toggleVisible()
    Nick.visible = not Nick.visible
    Nick.save()
end

-- Screen position -> "field", "ok", "visible" or nil
function Nick.hit(x, y)
    local ui = uiScale()
    x, y = x / ui, y / ui
    local rects = layout()
    for _, name in ipairs({ "field", "ok", "visible" }) do
        local r = rects[name]
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then return name end
    end
end

function Nick.draw(fonts)
    local rects, sw, sh = layout()
    love.graphics.push()
    love.graphics.scale(uiScale())
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    love.graphics.setFont(fonts.button)
    love.graphics.setColor(1, 0.8, 0.2)
    love.graphics.printf("Your nick", 0, 30, sw, "center")
    love.graphics.setFont(fonts.text)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.printf("Friends in your Wi-Fi see it in the game.", 0, 80, sw, "center")
    love.graphics.printf("Not your real name please - think of a nickname!", 0, 104, sw, "center")

    local f = rects.field
    love.graphics.setColor(0.1, 0.12, 0.15, 0.95)
    love.graphics.rectangle("fill", f.x, f.y, f.w, f.h, 10, 10)
    love.graphics.setColor(1, 0.6, 0.2)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", f.x, f.y, f.w, f.h, 10, 10)
    love.graphics.setFont(fonts.button)
    love.graphics.setColor(1, 1, 1)
    local cursor = (love.timer.getTime() % 1 < 0.5) and "_" or " "
    love.graphics.printf((Nick.editing or "") .. cursor, f.x + 12, f.y + 14, f.w - 24, "left")

    local r = rects.ok
    love.graphics.setColor(0.1, 0.12, 0.15, 0.9)
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 10, 10)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 10, 10)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("OK", r.x, r.y + 14, r.w, "center")

    -- Friends can invite me: switch
    local v = rects.visible
    love.graphics.setColor(0.1, 0.12, 0.15, 0.9)
    love.graphics.rectangle("fill", v.x, v.y, v.w, v.h, 10, 10)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.rectangle("line", v.x, v.y, v.w, v.h, 10, 10)
    love.graphics.setFont(fonts.text)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.printf("Friends in my Wi-Fi can invite me", v.x + 12, v.y + 8, v.w - 24, "left")
    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.printf(Nick.visible and "Only while I am in the lobby" or "They can't see me", v.x + 12,
        v.y + 34, v.w - 100, "left")
    love.graphics.setColor(Nick.visible and 0.3 or 0.45, Nick.visible and 0.75 or 0.45, Nick.visible and 0.3 or 0.5)
    love.graphics.rectangle("fill", v.x + v.w - 76, v.y + 16, 64, 32, 16, 16)
    love.graphics.setColor(1, 1, 1)
    love.graphics.circle("fill", v.x + v.w - (Nick.visible and 28 or 60), v.y + 32, 12)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

return Nick
