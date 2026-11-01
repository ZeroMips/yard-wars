-- Simple bot. States: patrol -> chase / strafe / retreat / flee -> search
local Arena   = require("src.arena")
local Rowdy = require("src.rowdy")

local Enemy = setmetatable({}, { __index = Rowdy })
Enemy.__index = Enemy
Enemy.isBot = true

local SIGHT_RANGE   = 700  -- how far the bot can see
local BUSH_REVEAL   = 130  -- bot only spots a player in a bush this close
local SHOOT_RANGE   = 0.88 -- shoots within this share of its range (bot: 480 -> 422)
local PREFERRED_MIN = 220  -- closer than this: back off
local PREFERRED_MAX = 340  -- farther than this: approach (both nearer for short ranges)
local AIM_SPREAD    = 0.25 -- radians of random inaccuracy
-- Bots spread out instead of moving as one clump (the target choice: World:botTarget)
local SPREAD        = 130  -- px: walks away from team mates closer than this
local FLANK         = 0.8  -- radians: chases on a path turned up to this far (new per life)
local SEARCH_OFFSET = 120  -- px: searches around the last seen spot, not right on it
local PATROL_TOWARDS = 0.35 -- share of patrol points near the target (else anywhere)
local PATROL_AREA   = 700  -- px around the target
local GOAL_SPREAD   = 80   -- px: Yardball shots aim this far up or down the goal mouth

-- look/stats: of a rowdy in src/rowdies.lua (the world picks it, see World.BOT_DAMAGE)
function Enemy.new(x, y, look, stats)
    local self = setmetatable({}, Enemy)
    self:init(x, y, look, stats)
    self.state = "patrol"
    self.wx, self.wy = x, y
    self.wanderTimer = 0
    self.strafeDir, self.strafeTimer = 1, 0
    self.stuckTimer, self.unstickTimer, self.unstickDir = 0, 0, 1
    self.flank, self.searchDX, self.searchDY = 0, 0, 0 -- (new ones at every respawn)
    return self
end

function Enemy:respawn()
    Rowdy.respawn(self)
    self.state = "patrol"
    self.lastSeenX, self.lastSeenY = nil, nil
    self.wanderTimer = 0
    self.flank = (math.random() * 2 - 1) * FLANK
    local a, r = math.random() * math.pi * 2, math.random() * SEARCH_OFFSET
    self.searchDX, self.searchDY = math.cos(a) * r, math.sin(a) * r
    self.aimOffset = (math.random() * 2 - 1) * GOAL_SPREAD -- (Yardball: where it shoots)
end

-- Unit vector (x, y) turned by angle a
local function turn(x, y, a)
    local c, s = math.cos(a), math.sin(a)
    return x * c - y * s, x * s + y * c
end

-- Push away from team mates closer than SPREAD (stronger the closer they are)
local function separation(self, world)
    local sx, sy = 0, 0
    for _, o in ipairs(world.entities) do
        if o ~= self and o.team == self.team and not o.dead then
            local dx, dy = self.x - o.x, self.y - o.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d < SPREAD then
                if d < 0.001 then dx, dy, d = math.random() - 0.5, math.random() - 0.5, 1 end
                local w = (SPREAD - d) / SPREAD
                local len = math.sqrt(dx * dx + dy * dy)
                sx, sy = sx + dx / len * w * 1.5, sy + dy / len * w * 1.5
            end
        end
    end
    return sx, sy
end

local walk -- (below: moves the bot, slides along walls it is stuck on)

-- Hide and seek (World:hidePlan): hide, run, fetch pieces - or seek and swing the tag
function Enemy:updateHide(dt, world)
    self:tick(dt)
    if self.dead then return end
    if not self:canMove() then
        if not self.push then self:move(0, 0, dt) end
        return
    end
    local plan = world:hidePlan(self)
    local mx, my = 0, 0
    if plan then
        local px, py = plan.x - self.x, plan.y - self.y
        local pd = math.sqrt(px * px + py * py)
        if pd > 6 then mx, my = px / pd, py / pd end
        self.state = plan.state or "hide"
        if mx ~= 0 or my ~= 0 then self.aim = math.atan2(my, mx) end
        if plan.tag then
            self.aim = plan.tag
            world:tag(self)
        end
    else
        self.state = "still"
    end
    walk(self, mx, my, dt)
end

-- world: see src/world.lua. The bot goes after an opponent (World:botTarget).
function Enemy:update(dt, world)
    if world.hide then return self:updateHide(dt, world) end
    self:tick(dt)
    if self.dead then return end
    if not self:canMove() then -- frozen, pulled or leaping (src/rowdies.lua)
        if not self.push then self:move(0, 0, dt) end
        return
    end

    -- a healing super (src/rowdies.lua: kind "heal") is for when it's hurt, not for a target
    local super = self.super
    local heals = super and super.kind == "heal"
    if heals and self:superReady() and self.cooldown <= 0 and self.hp < self.maxHp * 0.55 then
        self:shootSuper(world.bullets)
    end

    local target = world:botTarget(self)
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
    if visible and target.burrowed then visible = false end -- underground
    if visible and target.vanished and dist > BUSH_REVEAL then visible = false end
    if target and target.carrying and not target.dead and dist <= SIGHT_RANGE then
        visible = Arena.hasLineOfSight(self.x, self.y, target.x, target.y) -- the ball shows it
    end

    local mx, my = 0, 0
    if visible then
        self.lastSeenX, self.lastSeenY = target.x, target.y
        local ox, oy = target.x + self.searchDX, target.y + self.searchDY
        if not Arena.hitsSolid(ox, oy, self.radius) then self.lastSeenX, self.lastSeenY = ox, oy end
        self.aim = math.atan2(dy, dx)
        local ux, uy = dx / dist, dy / dist

        if self.burrowed then -- underground: straight at it, to pop out under it
            self.state = "chase"
            mx, my = ux, uy
        elseif self.hp < self.maxHp * 0.3 and not self.boss then -- a boss stands its ground
            self.state = "flee"
            mx, my = -ux, -uy
        elseif dist > math.min(PREFERRED_MAX, self.range * 0.75) then
            self.state = "chase" -- on a curve (flank), so bots come from different sides
            mx, my = turn(ux, uy, self.flank)
        elseif dist < math.min(PREFERRED_MIN, self.range * 0.45) then
            self.state = "retreat"
            mx, my = turn(-ux, -uy, self.flank)
        else
            self.state = "strafe"
            self.strafeTimer = self.strafeTimer - dt
            if self.strafeTimer <= 0 then
                self.strafeDir = -self.strafeDir
                self.strafeTimer = 0.8 + math.random() * 1.2
            end
            mx, my = -uy * self.strafeDir, ux * self.strafeDir
        end

        -- bombs land where the target stands (aimDist is measured from the body centre)
        self.aimDist = dist
        if super and not heals and self:superReady() and self.cooldown <= 0
            and dist <= self:reach(super) * SHOOT_RANGE then
            local exact = self.aim
            self.aim = exact + (math.random() - 0.5) * AIM_SPREAD * 0.5
            self:shootSuper(world.bullets)
            self.aim = exact
        elseif dist <= self:reach(self.attack) * SHOOT_RANGE and self.cooldown <= 0 and self.ammo >= 1 then
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
            local z = world.zone -- (King of the Yard: inside the clear circle)
            if target and math.random() < PATROL_TOWARDS then -- roam towards the action
                self.wx, self.wy = Arena.randomOpenPoint(target.x, target.y, PATROL_AREA)
            elseif z then -- around here, but not out in the fog
                self.wx, self.wy = Arena.randomOpenPoint(self.x, self.y, PATROL_AREA)
                if not world:inZone(self.wx, self.wy, 150) then
                    self.wx, self.wy = Arena.randomOpenPoint(z.x, z.y, math.max(100, z.r * 0.5))
                end
            else
                self.wx, self.wy = Arena.randomOpenPoint()
            end
            self.wanderTimer = 4
        else
            mx, my = wx / wd, wy / wd
        end
    end

    -- Yardball (World:ballPlan): carry the ball to the goal and shoot, go for a free ball
    -- or the carrier; King of the Yard (World:kingPlan): out of the fog, onto a team
    -- mate's heart; Flower Gardens (World:flowerPlan): flowers home, a bulldozer to a
    -- fence - shooting at the target goes on as above
    local plan = world.ballPlan and world:ballPlan(self)
    if not plan and world.zone and world.kingPlan then plan = world:kingPlan(self, visible, dist) end
    if not plan and world.flowerGame then plan = world:flowerPlan(self, visible, dist) end
    if plan and plan.kick then
        world:kick(self, plan.angle, plan.dist)
    elseif plan then
        local px, py = plan.x - self.x, plan.y - self.y
        local pd = math.sqrt(px * px + py * py)
        if pd > 4 then mx, my = px / pd, py / pd else mx, my = 0, 0 end
        self.state = plan.state or plan.fog and "fog" or plan.beacon and "revive" or "ball"
        if (self.carrying or self.driving) and (mx ~= 0 or my ~= 0) then self.aim = math.atan2(my, mx) end
    end

    -- Keep apart from team mates (not underground: it heads for its target there)
    if not self.burrowed then
        local sx, sy = separation(self, world)
        local moving = mx ~= 0 or my ~= 0
        if moving or sx * sx + sy * sy > 0.1 then -- (standing: only when really close)
            mx, my = mx + sx, my + sy
            local len = math.sqrt(mx * mx + my * my)
            if len > 1 then mx, my = mx / len, my / len end
        end
    end

    -- Face the walking direction when not aiming at the player
    if not visible and (mx ~= 0 or my ~= 0) then
        self.aim = math.atan2(my, mx)
    end

    walk(self, mx, my, dt)
end

-- Walk in direction mx, my (unit vector or 0, 0). Stuck on a wall? Slide sideways for
-- a moment.
function walk(self, mx, my, dt)
    if self.unstickTimer > 0 then
        self.unstickTimer = self.unstickTimer - dt
        mx, my = -my * self.unstickDir, mx * self.unstickDir
    end

    if not self:walks() then return end -- dashing (a punch) or handcuffed
    local ox, oy = self.x, self.y
    self:move(mx, my, dt)

    if mx ~= 0 or my ~= 0 then
        local moved = math.sqrt((self.x - ox) ^ 2 + (self.y - oy) ^ 2)
        if moved < self.speed * dt * 0.25 then
            self.stuckTimer = self.stuckTimer + dt
            if self.stuckTimer > 0.3 then
                -- slide sideways, to the open side if only one is
                local open = {}
                for _, dir in ipairs({ 1, -1 }) do
                    if not Arena.hitsSolid(self.x - my * dir * 56, self.y + mx * dir * 56, self.radius) then
                        open[#open + 1] = dir
                    end
                end
                self.unstickDir = #open == 1 and open[1] or ((math.random(2) == 1) and 1 or -1)
                self.stuckTimer = 0
                self.unstickTimer = 0.8
                self.wanderTimer = 0
            end
        else
            self.stuckTimer = 0
        end
    end
end

return Enemy
