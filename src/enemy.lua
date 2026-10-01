-- Simple bot. States: patrol -> chase / strafe / retreat / flee -> search
local Arena   = require("src.arena")
local Rowdy = require("src.rowdy")

local Enemy = setmetatable({}, { __index = Rowdy })
Enemy.__index = Enemy
Enemy.isBot = true

local SIGHT_RANGE   = 700  -- how far the bot can see
local BUSH_REVEAL   = 130  -- bot only spots a player in a bush this close
local SHOOT_RANGE   = 420  -- bullets fly 480px, so shoot a bit earlier
local PREFERRED_MIN = 220  -- closer than this: back off
local PREFERRED_MAX = 340  -- farther than this: approach
local AIM_SPREAD    = 0.25 -- radians of random inaccuracy

-- stats: see src/rowdies.lua (Rowdies.bot)
function Enemy.new(x, y, look, stats)
    local self = setmetatable({}, Enemy)
    self:init(x, y, look, stats)
    self.state = "patrol"
    self.wx, self.wy = x, y
    self.wanderTimer = 0
    self.strafeDir, self.strafeTimer = 1, 0
    self.stuckTimer, self.unstickTimer, self.unstickDir = 0, 0, 1
    return self
end

function Enemy:respawn()
    Rowdy.respawn(self)
    self.state = "patrol"
    self.lastSeenX, self.lastSeenY = nil, nil
    self.wanderTimer = 0
end

-- world: see src/world.lua. The bot goes after the nearest opponent.
function Enemy:update(dt, world)
    self:tick(dt)
    if self.dead then return end

    local target = world:nearestOpponent(self)
    local dx, dy, dist = 0, 0, math.huge
    if target then
        dx, dy = target.x - self.x, target.y - self.y
        dist = math.max(0.001, math.sqrt(dx * dx + dy * dy))
    end
    local visible = target and not target.dead and dist <= SIGHT_RANGE
        and Arena.hasLineOfSight(self.x, self.y, target.x, target.y)
    if visible and dist > BUSH_REVEAL and Arena.inBush(target.x, target.y) then
        visible = false -- player is hiding in a bush
    end

    local mx, my = 0, 0
    if visible then
        self.lastSeenX, self.lastSeenY = target.x, target.y
        self.aim = math.atan2(dy, dx)
        local ux, uy = dx / dist, dy / dist

        if self.hp < self.maxHp * 0.3 then
            self.state = "flee"
            mx, my = -ux, -uy
        elseif dist > PREFERRED_MAX then
            self.state = "chase"
            mx, my = ux, uy
        elseif dist < PREFERRED_MIN then
            self.state = "retreat"
            mx, my = -ux, -uy
        else
            self.state = "strafe"
            self.strafeTimer = self.strafeTimer - dt
            if self.strafeTimer <= 0 then
                self.strafeDir = -self.strafeDir
                self.strafeTimer = 0.8 + math.random() * 1.2
            end
            mx, my = -uy * self.strafeDir, ux * self.strafeDir
        end

        if dist <= SHOOT_RANGE and self.cooldown <= 0 and self.ammo >= 1 then
            local exact = self.aim
            self.aim = exact + (math.random() - 0.5) * AIM_SPREAD
            self:shoot(world.bullets)
            self.aim = exact
        end

    elseif self.lastSeenX then
        -- lost sight: walk to where the player was last seen
        self.state = "search"
        local sx, sy = self.lastSeenX - self.x, self.lastSeenY - self.y
        local sd = math.sqrt(sx * sx + sy * sy)
        if sd < 40 then
            self.lastSeenX, self.lastSeenY = nil, nil
        else
            mx, my = sx / sd, sy / sd
        end

    else
        -- nothing known: patrol between random points
        self.state = "patrol"
        self.wanderTimer = self.wanderTimer - dt
        local wx, wy = self.wx - self.x, self.wy - self.y
        local wd = math.sqrt(wx * wx + wy * wy)
        if wd < 30 or self.wanderTimer <= 0 then
            if target and math.random() < 0.6 then -- roam towards the action
                self.wx, self.wy = Arena.randomOpenPoint(target.x, target.y, 500)
            else
                self.wx, self.wy = Arena.randomOpenPoint()
            end
            self.wanderTimer = 4
        else
            mx, my = wx / wd, wy / wd
        end
    end

    -- Face the walking direction when not aiming at the player
    if not visible and (mx ~= 0 or my ~= 0) then
        self.aim = math.atan2(my, mx)
    end

    -- Stuck on a wall? Slide sideways for a moment.
    if self.unstickTimer > 0 then
        self.unstickTimer = self.unstickTimer - dt
        mx, my = -my * self.unstickDir, mx * self.unstickDir
    end

    local ox, oy = self.x, self.y
    self:move(mx, my, dt)

    if mx ~= 0 or my ~= 0 then
        local moved = math.sqrt((self.x - ox) ^ 2 + (self.y - oy) ^ 2)
        if moved < self.speed * dt * 0.25 then
            self.stuckTimer = self.stuckTimer + dt
            if self.stuckTimer > 0.3 then
                self.stuckTimer = 0
                self.unstickTimer = 0.8
                self.unstickDir = (math.random(2) == 1) and 1 or -1
                self.wanderTimer = 0
            end
        else
            self.stuckTimer = 0
        end
    end
end

return Enemy
