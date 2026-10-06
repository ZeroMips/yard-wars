-- Input abstraction. Desktop: WASD + mouse (hold left button to fire; hold right
-- button or E to aim the super, release to fire it).
-- Touch (Android/iOS), twin-stick style:
--   left half  : floating move stick
--   right half : aim stick. Drag = aim beam, RELEASE = fire.
--                Drag back to the center before releasing = cancel.
--                Quick TAP = auto-aim at the nearest enemy in range and fire.
--                Bombs (src/rowdies.lua: lob) fly as far as the stick is pulled
--                (desktop: to the mouse pointer; a tap: to the target).
--   super button (left of the aim stick, glows when charged): same gestures as the
--                aim stick, but for the super attack
-- Both input modes return the same table, so the rest of the game doesn't care.
local Camera = require("src.camera")
local Bullet = require("src.bullet")

local Controls = {}

local osName = love.system.getOS()
Controls.touchMode = (osName == "Android" or osName == "iOS")
Controls.font = nil              -- HUD font (set by main.lua)
Controls.superCharge = 0         -- 0..1, shown on the super button (set by main.lua)
Controls.hasSuper = false        -- the current rowdy has a super (set by main.lua)

local DEADZONE = 0.25

local move = { id = nil, ox = 0, oy = 0, x = 0, y = 0 }
local aim  = { id = nil, ox = 0, oy = 0, x = 0, y = 0, maxMag = 0, super = false }
local superHeld = false -- desktop: right mouse button / E held last frame
local lastAim = 0
local pendingShot = nil -- filled when the aim stick is released

local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end
local function stickRadius() return 80 * uiScale() end

-- Super button: up and to the left of where the aim stick usually is (screen px)
local function superButton()
    local w, h = love.graphics.getDimensions()
    local r = stickRadius()
    return w * 0.84 - r * 1.9, h * 0.72 - r * 0.6, r * 0.55
end

-- Direction (-1..1) and strength (0..1) of a stick
local function stickVector(s)
    local dx, dy = s.x - s.ox, s.y - s.oy
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return 0, 0, 0 end
    local mag = math.min(1, len / stickRadius())
    return dx / len * mag, dy / len * mag, mag
end

-- How far a bomb flies for a stick pulled `mag` (0..1) far: the dead zone throws the
-- shortest distance, the rim the attack's full range
local function throwDist(player, super, mag)
    local attack = (super and player.super) or player
    local range = attack.range or player.range or Bullet.range
    local f = math.max(0, math.min(1, (mag - DEADZONE) / (1 - DEADZONE)))
    return Bullet.MIN_THROW + (range - Bullet.MIN_THROW) * f
end

-- Forget all active touches and queued shots (new game / back to menu)
function Controls.reset()
    move.id, aim.id, pendingShot = nil, nil, nil
    superHeld = false
end

-- ---- Touch callbacks (forwarded from main.lua) ----
function Controls.touchpressed(id, x, y)
    Controls.touchMode = true

    -- Super button (only when charged; otherwise it acts like the rest of the screen)
    local sx, sy, sr = superButton()
    local onSuper = Controls.hasSuper and Controls.superCharge >= 1
        and (x - sx) ^ 2 + (y - sy) ^ 2 <= (sr * 1.4) ^ 2

    local s
    if x < love.graphics.getWidth() / 2 and not onSuper then
        if move.id then return end
        s = move
    else
        if aim.id then return end
        s = aim
        aim.maxMag = 0
        aim.super = onSuper
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
            pendingShot = { tap = true, super = aim.super }        -- quick tap: auto-aim
        elseif mag >= DEADZONE then
            pendingShot = { angle = lastAim, super = aim.super,     -- released: fire
                            mag = mag }
        end                                                        -- in the center: cancel
        aim.id = nil
    end
end

-- Velocity of the auto-aim target: its movement over the last ~0.1 s (a window, not
-- frame to frame: frames can be faster than the 60 Hz simulation)
local track = { id = nil, samples = {}, vx = 0, vy = 0 }
local TRACK_WINDOW = 0.1
local MAX_TRACK_SPEED = 400 -- px/s; faster = a teleport (respawn), not walking

local function trackTarget(target)
    local now = love.timer.getTime()
    if not target or target.id ~= track.id then
        track.id, track.samples, track.vx, track.vy = target and target.id, {}, 0, 0
        if not target then return end
    end
    local samples = track.samples
    samples[#samples + 1] = { t = now, x = target.x, y = target.y }
    while #samples > 2 and now - samples[2].t >= TRACK_WINDOW do table.remove(samples, 1) end
    local old = samples[1]
    local dt = now - old.t
    if dt > 0 then
        local vx, vy = (target.x - old.x) / dt, (target.y - old.y) / dt
        if vx * vx + vy * vy > MAX_TRACK_SPEED * MAX_TRACK_SPEED then
            track.samples, vx, vy = { samples[#samples] }, 0, 0
        end
        track.vx, track.vy = vx, vy
    end
end

-- Angle to the target if it is within attack range, else nil (+ the distance to the aimed
-- spot, for bombs). Aims where a walking target will be when the shot arrives (fast
-- shots barely lead, slow ones more).
-- (Walls are ignored on purpose: a quick tap should always fire at someone.)
local function autoAimAngle(player, target, super)
    if not target then return nil end
    local attack = (super and player.super) or player
    local range = attack.range or player.range
    local speed = attack.bulletSpeed or player.bulletSpeed
    local dx, dy = target.x - player.x, target.y - player.y
    if math.sqrt(dx * dx + dy * dy) > range + 60 then return nil end
    local px, py = target.x, target.y
    for _ = 1, 3 do -- refine: flight time to the predicted spot
        local t = math.min(math.sqrt((px - player.x) ^ 2 + (py - player.y) ^ 2), range) / speed
        px, py = target.x + track.vx * t, target.y + track.vy * t
    end
    return math.atan2(py - player.y, px - player.x),
        math.sqrt((px - player.x) ^ 2 + (py - player.y) ^ 2)
end

-- ---- Read input for this frame ----
-- target: the enemy to auto-aim at on a tap (nil if none / not visible)
-- Returns { dx, dy, aim (angle or nil), aimDist (px a bomb flies, or nil), fire (bool),
--           super (bool: fire the super), aiming (show the beam), aimingSuper (show the
--           super's aim) }
function Controls.get(player, target)
    trackTarget(target)
    if Controls.touchMode then
        local dx, dy = 0, 0
        if move.id then dx, dy = stickVector(move) end

        -- Keep lastAim in sync with where the character really faces, so a new
        -- aim gesture never starts from a stale direction.
        if not aim.id and not pendingShot then lastAim = player.aim end

        local angle, fire, dist = nil, false, nil
        if aim.id then
            if aim.maxMag < DEADZONE then
                -- finger down but not dragged yet: preview the auto-aim direction
                angle, dist = autoAimAngle(player, target, aim.super)
                angle = angle or lastAim
            else
                angle = lastAim
                dist = throwDist(player, aim.super, select(3, stickVector(aim)))
            end
        elseif dx ~= 0 or dy ~= 0 then
            lastAim = math.atan2(dy, dx)            -- face walking direction
            angle = lastAim
        end

        local super = false
        if pendingShot then
            if pendingShot.super then super = true else fire = true end
            if pendingShot.tap then
                angle, dist = autoAimAngle(player, target, pendingShot.super)
                angle = angle or lastAim
            else
                angle = pendingShot.angle
                dist = throwDist(player, pendingShot.super, pendingShot.mag)
            end
            pendingShot = nil
        end
        if angle then lastAim = angle end
        return { dx = dx, dy = dy, aim = angle, aimDist = dist, fire = fire, super = super,
                 aiming = aim.id ~= nil and not aim.super,
                 aimingSuper = aim.id ~= nil and aim.super }
    end

    local dx, dy = 0, 0
    if love.keyboard.isDown("w") then dy = dy - 1 end
    if love.keyboard.isDown("s") then dy = dy + 1 end
    if love.keyboard.isDown("a") then dx = dx - 1 end
    if love.keyboard.isDown("d") then dx = dx + 1 end
    local mx, my = Camera.toWorld(love.mouse.getPosition())
    -- Super: hold right mouse button or E to aim, release to fire
    local held = love.mouse.isDown(2) or love.keyboard.isDown("e")
    local super = superHeld and not held
    superHeld = held
    return {
        dx = dx, dy = dy,
        aim = math.atan2(my - player.y, mx - player.x),
        aimDist = math.sqrt((mx - player.x) ^ 2 + (my - player.y) ^ 2),
        fire = love.mouse.isDown(1) and not held,
        super = super,
        aiming = not held,
        aimingSuper = held and Controls.hasSuper,
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
    if aim.super then
        drawStick(aim, w * 0.84, h * 0.72, { 1, 0.82, 0.1 })
    else
        drawStick(aim, w * 0.84, h * 0.72, { 1, 0.6, 0.2 })
    end

    -- Super button: dark disc, gold charge ring; full = glowing gold disc
    if Controls.hasSuper and not (aim.id and aim.super) then
        local sx, sy, sr = superButton()
        local charge = math.min(1, Controls.superCharge)
        love.graphics.setColor(0, 0, 0, 0.45)
        love.graphics.circle("fill", sx, sy, sr)
        love.graphics.setLineWidth(sr * 0.18)
        if charge >= 1 then
            local k = 0.5 + 0.5 * math.sin(love.timer.getTime() * 6)
            love.graphics.setColor(1, 0.82, 0.1, 0.55 + 0.35 * k)
            love.graphics.circle("fill", sx, sy, sr * (0.8 + 0.06 * k))
            love.graphics.setColor(1, 0.95, 0.6, 1)
            love.graphics.circle("line", sx, sy, sr)
        elseif charge > 0 then
            love.graphics.setColor(1, 0.82, 0.1, 0.9)
            love.graphics.arc("line", "open", sx, sy, sr * 0.9,
                -math.pi / 2, -math.pi / 2 + charge * math.pi * 2, 32)
        end
        love.graphics.setLineWidth(1)
        if Controls.font then -- label in HUD units, like the HUD
            local ui = uiScale()
            love.graphics.push()
            love.graphics.translate(sx, sy)
            love.graphics.scale(ui)
            love.graphics.setFont(Controls.font)
            love.graphics.setColor(1, 1, 1, charge >= 1 and 1 or 0.5)
            local fh = Controls.font:getHeight()
            love.graphics.printf("SUPER", -60, -fh / 2, 120, "center")
            love.graphics.pop()
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return Controls
