-- Start screen: title + one button per game mode.
-- Works with mouse, touch and keyboard (up/down + enter).
-- Laid out in HUD units (720 along the short screen side), like the in-game HUD.
local Menu = {}

Menu.selected = 1

local BTN_W, BTN_H, BTN_GAP = 420, 90, 20

local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end

-- Button rectangles (HUD units) + screen size in HUD units
local function layout(count)
    local ui = uiScale()
    local sw, sh = love.graphics.getWidth() / ui, love.graphics.getHeight() / ui
    local w = math.min(BTN_W, sw - 40)
    local total = count * BTN_H + (count - 1) * BTN_GAP
    local y0 = math.max(200, sh / 2 - total / 2 + 40)
    local rects = {}
    for i = 1, count do
        rects[i] = { x = (sw - w) / 2, y = y0 + (i - 1) * (BTN_H + BTN_GAP), w = w, h = BTN_H }
    end
    return rects, sw, sh
end

-- Index of the mode button at screen position (x, y), or nil
function Menu.hit(modes, x, y)
    local ui = uiScale()
    x, y = x / ui, y / ui
    for i, r in ipairs(layout(#modes)) do
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then return i end
    end
    return nil
end

-- Returns the index of the mode to start, or nil
function Menu.keypressed(modes, key)
    if key == "up" or key == "w" then
        Menu.selected = (Menu.selected - 2) % #modes + 1
    elseif key == "down" or key == "s" then
        Menu.selected = Menu.selected % #modes + 1
    elseif key == "return" or key == "kpenter" or key == "space" then
        return Menu.selected
    end
    return nil
end

-- fonts = { title, button, text }
function Menu.draw(modes, fonts, touchMode)
    local rects, sw, sh = layout(#modes)
    love.graphics.push()
    love.graphics.scale(uiScale())

    -- Dim the arena in the background
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    local top = rects[1].y
    love.graphics.setFont(fonts.title)
    love.graphics.setColor(1, 0.8, 0.2)
    love.graphics.printf("YARD WARS", 0, top - 150, sw, "center")
    love.graphics.setFont(fonts.text)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.printf("Choose a mode", 0, top - 45, sw, "center")

    for i, r in ipairs(rects) do
        local selected = (i == Menu.selected)
        love.graphics.setColor(0.1, 0.12, 0.15, 0.9)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 12, 12)
        if selected then love.graphics.setColor(1, 0.6, 0.2) else love.graphics.setColor(1, 1, 1, 0.35) end
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 12, 12)
        love.graphics.setLineWidth(1)

        love.graphics.setFont(fonts.button)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(modes[i].name, r.x, r.y + 14, r.w, "center")
        love.graphics.setFont(fonts.text)
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.printf(modes[i].description, r.x + 10, r.y + 54, r.w - 20, "center")
    end

    local last = rects[#rects]
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.printf(touchMode and "Tap a mode to start  -  In game, Back returns here"
        or "Click or Enter to start  -  In game, Esc returns here",
        0, last.y + last.h + 30, sw, "center")

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

return Menu
