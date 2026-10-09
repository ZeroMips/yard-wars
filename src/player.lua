local Rowdy = require("src.rowdy")

local Player = setmetatable({}, { __index = Rowdy })
Player.__index = Player

function Player.new(x, y, image, stats)
    local self = setmetatable({}, Player)
    self:init(x, y, image, stats or {})
    self.showAmmo = true
    return self
end

-- input = { dx, dy, aim (angle or nil), aimDist (px, how far a bomb flies; nil = its
-- full range), fire, hold (attack held down: a beam), super, aiming } from
-- src/controls.lua
function Player:update(dt, input, bullets)
    self:tick(dt)
    if self.dead then return end
    if input.aim then self.aim = input.aim end
    self.aimDist = tonumber(input.aimDist)
    if not self:canMove() then -- frozen, pulled, leaping: shots asked for now are lost
        self.fireBuffer, self.superBuffer = nil, nil
        if not self.push then self:move(0, 0, dt) end
        return
    end

    if self:walks() then self:move(input.dx, input.dy, dt) end

    -- A requested shot is remembered for a moment (with its direction), so it
    -- still fires if it arrives while reloading. Same for a super (it needs no ammo,
    -- only the attack cooldown).
    if input.super then self.superBuffer = { angle = self.aim, dist = self.aimDist, time = 0.25 } end
    local sb = self.superBuffer
    if sb then
        self.aim, self.aimDist = sb.angle, sb.dist
        if self:shootSuper(bullets) then
            self.superBuffer = nil
        else
            sb.time = sb.time - dt
            if sb.time <= 0 or not self:superReady() then self.superBuffer = nil end
        end
    end

    if self.attack.kind == "beam" then -- held: the beam stays on (src/rowdy.lua)
        if input.hold then self:shoot(bullets, true) elseif input.fire then self:shoot(bullets) end
        return
    end

    if input.fire then self.fireBuffer = { angle = self.aim, dist = self.aimDist, time = 0.25 } end
    local fb = self.fireBuffer
    if fb then
        self.aim, self.aimDist = fb.angle, fb.dist
        if self:shoot(bullets) then
            self.fireBuffer = nil
        else
            fb.time = fb.time - dt
            if fb.time <= 0 then self.fireBuffer = nil end
        end
    end
end

return Player
