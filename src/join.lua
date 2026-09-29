-- "Join LAN game" screen: address field + Connect / Back buttons.
-- Kept in the upper part of the screen, because the on-screen keyboard covers the rest.
-- Laid out in HUD units (720 along the short screen side), like the menu.
local Join = {}

Join.address = ""
Join.status = nil -- e.g. "Could not connect"

local SAVE_FILE = "last_host.txt"
local MAX_LEN = 64

local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end

local function layout()
    local ui = uiScale()
    local sw = love.graphics.getWidth() / ui
    local w = math.min(460, sw - 40)
    local x = (sw - w) / 2
    local bw = (w - 20) / 2
    return {
        field   = { x = x, y = 130, w = w, h = 64 },
        connect = { x = x, y = 214, w = bw, h = 64 },
        back    = { x = x + bw + 20, y = 214, w = bw, h = 64 },
    }, sw
end

function Join.open()
    local saved = love.filesystem.getInfo(SAVE_FILE) and love.filesystem.read(SAVE_FILE)
    Join.address = saved and saved:match("^%s*(.-)%s*$") or Join.address
    love.keyboard.setTextInput(true)
end

function Join.close()
    love.keyboard.setTextInput(false)
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

-- Screen position -> "field", "connect", "back" or nil
function Join.hit(x, y)
    local ui = uiScale()
    x, y = x / ui, y / ui
    for name, r in pairs(layout()) do
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then return name end
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

    if Join.status then
        love.graphics.setFont(fonts.text)
        love.graphics.setColor(1, 0.55, 0.3)
        love.graphics.printf(Join.status, 0, 300, sw, "center")
    end

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

return Join
