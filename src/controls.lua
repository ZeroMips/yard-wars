-- Input abstraction. Desktop: WASD + mouse (hold left button to fire).
-- Touch (Android/iOS), twin-stick style:
--   left half  : floating move stick
--   right half : aim stick. Drag = aim beam, RELEASE = fire.
--                Drag back to the center before releasing = cancel.
--                Quick TAP = auto-aim at the nearest enemy in range and fire.
--   top-left button: switch rowdy.
-- Both input modes return the same table, so the rest of the game doesn't care.
local Camera = require("src.camera")

local Controls = {}

local osName = love.system.getOS()
Controls.touchMode = (osName == "Android" or osName == "iOS")
Controls.switchRequested = false -- set when the on-screen switch button is tapped
Controls.switchLabel = ""        -- text of the button (set by main.lua)
Controls.font = nil              -- HUD font (set by main.lua)

local DEADZONE = 0.25
local SWITCH_BTN = { x = 10, y = 36, w = 170, h = 40 } -- in HUD units (720px high screen)

local move = { id = nil, ox = 0, oy = 0, x = 0, y = 0 }
local aim  = { id = nil, ox = 0, oy = 0, x = 0, y = 0, maxMag = 0 }
local lastAim = 0
local pendingShot = nil -- filled when the aim stick is released

local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end
local function stickRadius() return 80 * uiScale() end

-- Direction (-1..1) and strength (0..1) of a stick
local function stickVector(s)
    local dx, dy = s.x - s.ox, s.y - s.oy
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return 0, 0, 0 end
    local mag = math.min(1, len / stickRadius())
    return dx / len * mag, dy / len * mag, mag
end

-- Forget all active touches and queued shots (new game / back to menu)
function Controls.reset()
    move.id, aim.id, pendingShot = nil, nil, nil
    Controls.switchRequested = false
end

-- ---- Touch callbacks (forwarded from main.lua) ----
function Controls.touchpressed(id, x, y)
    Controls.touchMode = true

    local ui, b = uiScale(), SWITCH_BTN
    if x >= b.x * ui and x <= (b.x + b.w) * ui and y >= b.y * ui and y <= (b.y + b.h) * ui then
        Controls.switchRequested = true
        return
    end

    local s
    if x < love.graphics.getWidth() / 2 then
        if move.id then return end
        s = move
    else
        if aim.id then return end
        s = aim
        aim.maxMag = 0
    end
    s.id, s.ox, s.oy, s.x, s.y = id, x, y, x, y
end

function Controls.touchmoved(id, x, y)
    if move.id == id then move.x, move.y = x, y end
    if aim.id == id then
        aim.x, aim.y = x, y
        local vx, vy, mag = stickVector(aim)
        if mag > aim.maxMag then aim.maxMag = mag end
        if mag > DEADZONE then lastAim = math.atan2(vy, vx) end
    end
end

function Controls.touchreleased(id, x, y)
    if move.id == id then move.id = nil end
    if aim.id == id then
        if x then aim.x, aim.y = x, y end
        local vx, vy, mag = stickVector(aim)
        if mag > DEADZONE then lastAim = math.atan2(vy, vx) end

        if aim.maxMag < DEADZONE then
            pendingShot = { tap = true }            -- quick tap: auto-aim
        elseif mag >= DEADZONE then
            pendingShot = { angle = lastAim }       -- released while aiming: fire
        end                                         -- back in the center: cancelled
        aim.id = nil
    end
end

-- Angle to the target if it is within attack range, else nil.
-- (Walls are ignored on purpose: a quick tap should always fire at someone.)
local function autoAimAngle(player, target)
    if not target then return nil end
    local dx, dy = target.x - player.x, target.y - player.y
    if math.sqrt(dx * dx + dy * dy) > player.range + 60 then return nil end
    return math.atan2(dy, dx)
end

-- ---- Read input for this frame ----
-- target: the enemy to auto-aim at on a tap (nil if none / not visible)
-- Returns { dx, dy, aim (angle or nil), fire (bool), aiming (show the beam) }
function Controls.get(player, target)
    if Controls.touchMode then
        local dx, dy = 0, 0
        if move.id then dx, dy = stickVector(move) end

        -- Keep lastAim in sync with where the character really faces, so a new
        -- aim gesture never starts from a stale direction.
        if not aim.id and not pendingShot then lastAim = player.aim end

        local angle, fire = nil, false
        if aim.id then
            if aim.maxMag < DEADZONE then
                -- finger down but not dragged yet: preview the auto-aim direction
                angle = autoAimAngle(player, target) or lastAim
            else
                angle = lastAim
            end
        elseif dx ~= 0 or dy ~= 0 then
            lastAim = math.atan2(dy, dx)            -- face walking direction
            angle = lastAim
        end

        if pendingShot then
            fire = true
            if pendingShot.tap then
                angle = autoAimAngle(player, target) or lastAim
            else
                angle = pendingShot.angle
            end
            pendingShot = nil
        end
        if angle then lastAim = angle end
        return { dx = dx, dy = dy, aim = angle, fire = fire, aiming = aim.id ~= nil }
    end

    local dx, dy = 0, 0
    if love.keyboard.isDown("w") then dy = dy - 1 end
    if love.keyboard.isDown("s") then dy = dy + 1 end
    if love.keyboard.isDown("a") then dx = dx - 1 end
    if love.keyboard.isDown("d") then dx = dx + 1 end
    local mx, my = Camera.toWorld(love.mouse.getPosition())
    return {
        dx = dx, dy = dy,
        aim = math.atan2(my - player.y, mx - player.x),
        fire = love.mouse.isDown(1),
        aiming = true,
    }
end

-- ---- Draw sticks and the switch button (screen space, after Camera.detach) ----
function Controls.draw()
    if not Controls.touchMode then return end
    local w, h = love.graphics.getDimensions()
    local r = stickRadius()

    local function drawStick(s, hintX, hintY, color)
        local bx, by, kx, ky
        if s.id then
            bx, by = s.ox, s.oy
            local dx, dy, mag = stickVector(s)
            local len = math.sqrt(dx * dx + dy * dy)
            local nx, ny = 0, 0
            if len > 0 then nx, ny = dx / len, dy / len end
            kx, ky = bx + nx * mag * r, by + ny * mag * r
            love.graphics.setColor(color[1], color[2], color[3], 0.28)
        else
            bx, by, kx, ky = hintX, hintY, hintX, hintY
            love.graphics.setColor(color[1], color[2], color[3], 0.12)
        end
        love.graphics.circle("fill", bx, by, r)
        love.graphics.setColor(color[1], color[2], color[3], s.id and 0.8 or 0.3)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", bx, by, r)
        love.graphics.circle("fill", kx, ky, r * 0.4)
        love.graphics.setLineWidth(1)
    end

    drawStick(move, w * 0.16, h * 0.72, { 1, 1, 1 })
    drawStick(aim,  w * 0.84, h * 0.72, { 1, 0.6, 0.2 })

    -- Switch-rowdy button
    local b = SWITCH_BTN
    love.graphics.push()
    love.graphics.scale(uiScale())
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 8, 8)
    love.graphics.setColor(1, 1, 1, 0.9)
    if Controls.font then love.graphics.setFont(Controls.font) end
    love.graphics.printf(Controls.switchLabel, b.x, b.y + 11, b.w, "center")
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

return Controls
