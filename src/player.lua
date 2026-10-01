local Rowdy = require("src.rowdy")

local Player = setmetatable({}, { __index = Rowdy })
Player.__index = Player

function Player.new(x, y, image, stats)
    local self = setmetatable({}, Player)
    self:init(x, y, image, stats or {})
    self.showAmmo = true
    return self
end

-- input = { dx, dy, aim (angle or nil), fire, super, aiming } from src/controls.lua
function Player:update(dt, input, bullets)
    self:tick(dt)
    if self.dead then return end

    self:move(input.dx, input.dy, dt)
    if input.aim then self.aim = input.aim end

    -- A requested shot is remembered for a moment (with its direction), so it
    -- still fires if it arrives while reloading. Same for a super (it needs no ammo,
    -- only the attack cooldown).
    if input.super then self.superBuffer = { angle = self.aim, time = 0.25 } end
    local sb = self.superBuffer
    if sb then
        self.aim = sb.angle
        if self:shootSuper(bullets) then
            self.superBuffer = nil
        else
            sb.time = sb.time - dt
            if sb.time <= 0 or not self:superReady() then self.superBuffer = nil end
        end
    end

    if input.fire then self.fireBuffer = { angle = self.aim, time = 0.25 } end
    local fb = self.fireBuffer
    if fb then
        self.aim = fb.angle
        if self:shoot(bullets) then
            self.fireBuffer = nil
        else
            fb.time = fb.time - dt
            if fb.time <= 0 then self.fireBuffer = nil end
        end
    end
end

return Player
