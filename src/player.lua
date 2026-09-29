local Rowdy = require("src.rowdy")

local Player = setmetatable({}, { __index = Rowdy })
Player.__index = Player

function Player.new(x, y, image, stats)
    local self = setmetatable({}, Player)
    self:init(x, y, image, stats or {})
    self.showAmmo = true
    return self
end

-- input = { dx, dy, aim (angle or nil), fire, aiming } from src/controls.lua
function Player:update(dt, input, bullets)
    self:tick(dt)
    if self.dead then return end

    self:move(input.dx, input.dy, dt)
    if input.aim then self.aim = input.aim end

    -- A requested shot is remembered for a moment (with its direction), so it
    -- still fires if it arrives while reloading.
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
