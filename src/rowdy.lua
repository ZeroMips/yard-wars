-- Shared base for everything that walks, aims, shoots and has HP.
-- Player and Enemy inherit from this.
-- Game logic (update/tick/move/shoot/takeDamage) never touches graphics or effects:
-- what happened is reported with self:emit() to the world (see src/world.lua).
local Arena   = require("src.arena")
local Assets  = require("src.assets")
local Bullet  = require("src.bullet")

local Rowdy = {}
Rowdy.__index = Rowdy

local RESPAWN_TIME = 2.5
local SPAWN_TIME   = 0.35 -- pop-in animation after respawn
local FLASH_TIME   = 0.07 -- muzzle flash
local SUPER_COLOR  = { 1, 0.82, 0.1 } -- super meter, aim and "ready" glow
local BURST_DELAY  = 0.08 -- default seconds between the shots of a burst
local DASH_TIME    = 0.1  -- seconds a punch's dash (attack.dash) takes
local LEAP_HEIGHT  = 90   -- px: top of a leap's arc (drawn)
local BURROW_SPEED = 1.25 -- walking faster underground
local BEAM_TICK    = 0.1  -- s: a beam hits this often (attack.damage each time)
local BEAM_DRAIN   = 1    -- ammo bars per second of beam
local BEAM_SOUND   = 0.3  -- s between two "shot" events of a beam (its hum)
local HOLD_SPEED   = 700  -- px/s: a grabbed rowdy follows the aim this fast at most
local FLING_SPEED  = 950  -- px/s and FLING_TIME s: how a grabbed rowdy is flung
local FLING_TIME   = 0.45
local BEAM_COLOR   = { 0.75, 0.45, 1 }
local ICE_COLOR    = { 0.55, 0.85, 1 }

local fire -- (defined below, used by tick for the shots of a burst)

-- Apply a stats table (see src/rowdies.lua). Used by init() and setRowdy().
function Rowdy:applyStats(stats)
    self.speed       = stats.speed or 250
    self.maxHp       = stats.hp or 100
    self.damage      = stats.damage or 20      -- per projectile
    self.reload      = stats.reload or 0.3     -- minimum delay between attacks
    self.maxAmmo     = stats.maxAmmo or 3
    self.ammoRefill  = stats.ammoRefill or 1.5 -- seconds per ammo bar
    self.pellets     = stats.pellets or 1
    self.spread      = stats.spread or 0       -- total cone angle (radians)
    self.range       = stats.range or Bullet.range
    self.bulletSpeed = stats.bulletSpeed or Bullet.speed
    self.barColor    = stats.barColor or self.barColor or { 0.3, 0.9, 0.3 }
    self.bulletColor = stats.bulletColor or self.bulletColor or { 1, 0.85, 0.2 }
    self.lob         = stats.lob               -- throws bombs (see src/rowdies.lua)
    self.blast       = stats.blast             -- their explosion radius
    self.super       = stats.super             -- nil: no super attack
    -- The normal attack as a table like the super (the attack fields of the stats,
    -- with the defaults above): what fire() and the aim preview read
    self.attack = setmetatable({ damage = self.damage, pellets = self.pellets,
        spread = self.spread, range = self.range, bulletSpeed = self.bulletSpeed },
        { __index = stats })
end

-- look: see Assets.look
function Rowdy:init(x, y, look, stats)
    self.x, self.y = x, y
    self.spawnX, self.spawnY = x, y
    self.look = look
    self.radius = 18
    self:applyStats(stats or {})
    self.hp = self.maxHp
    self.ammo = self.maxAmmo
    self.ammoTimer = 0
    self.showAmmo = false
    self.aim = 0
    self.cooldown = 0
    self.hitFlash = 0
    self.dead = false
    self.respawnTimer = 0
    self.charge = 0 -- super meter 0..1 (kept when defeated, reset when switching)
    self.frozen = 0 -- seconds left frozen (src/rowdies.lua: freeze): no moving, no attacks
    self.rooted = 0 -- seconds left handcuffed (src/rowdies.lua: hold): no walking
    self.muzzleSide = 1 -- twin attacks: which of the two muzzles fires next (1 / -1)
    self.air = 0        -- height above the ground while leaping (drawn)
    self.beamLen = 0    -- length of the beam this step (0 = off; drawn)
    self.beamHold = 0   -- seconds the beam stays on (input / bot keeps it up)
    -- push (forced or own movement { vx, vy, t, own }), leap, burrowed: see Rowdy:act
    -- carrying: has the ball (Yardball, set by src/world.lua): no attacks, only the super
    -- noAttacks: Hide and seek (src/world.lua) - no attacks and no super at all
    -- driving: Flower Gardens' bulldozer { expires, speed } (src/world.lua): can't be
    --   hurt or pushed, no attacks, drives at its speed
    -- animation state
    self.walkPhase, self.walkBlend, self.stepTimer = 0, 0, 0
    self.dirX, self.dirY = 1, 0
    self.recoil, self.flashTimer, self.flashSize, self.spawnAnim = 0, 0, 1, 0
end

-- Switch to another rowdy type (resets HP and ammo)
function Rowdy:setRowdy(look, stats)
    self.look = look
    self:applyStats(stats)
    self.hp = self.maxHp
    self.ammo = self.maxAmmo
    self.ammoTimer = 0
    self.cooldown = 0
    self.charge = 0
    self:clearActions()
end

-- Back to normal: no burst, push, leap or burrow going on (respawn, rowdy switch)
function Rowdy:clearActions()
    self:releaseGrab()
    if self.vanished then self:reappear() end
    self.bursting, self.push, self.leap, self.burrowed = nil, nil, nil, nil
    self.frozen, self.air, self.beamLen, self.beamHold = 0, 0, 0, 0
    self.rooted, self.goo = 0, nil
    self.heldBy = nil
end

-- Lets go of a grabbed rowdy (without flinging it)
function Rowdy:releaseGrab()
    local grab = self.grab
    self.grab = nil
    local victim = grab and self.world and self.world.byId[grab.id]
    if victim and victim.heldBy == self.id then victim.heldBy = nil end
end

-- The end of a vanish: visible again, and out of the wall it may be in
function Rowdy:reappear()
    self.vanished = nil
    self.x, self.y = Arena.nearestOpen(self.x, self.y, self.radius)
    self:emit("appear", { id = self.id, x = self.x, y = self.y })
end

-- Report something that happened (spawn, death, step, ...) to the world, if any.
function Rowdy:emit(kind, data)
    if self.world then self.world:emit(kind, data) end
end

-- Call once per simulation step: timers, ammo refill and respawn.
function Rowdy:tick(dt)
    self.cooldown = math.max(0, self.cooldown - dt)
    self.hitFlash = math.max(0, self.hitFlash - dt)
    self.recoil = math.max(0, self.recoil - dt * 8)
    self.flashTimer = math.max(0, self.flashTimer - dt)
    self.spawnAnim = math.max(0, self.spawnAnim - dt)
    self.frozen = math.max(0, self.frozen - dt)
    self.rooted = math.max(0, (self.rooted or 0) - dt)
    if not self.dead then self:act(dt) end
    local burst = self.bursting -- the rest of a burst (src/rowdies.lua: burst)
    if burst then
        if not self:canAct() or not self.world then
            self.bursting = nil
        else
            burst.timer = burst.timer - dt
            while burst.timer <= 0 and burst.left > 0 do
                fire(self, self.world.bullets, burst.attack, true)
                burst.left = burst.left - 1
                burst.timer = burst.timer + burst.delay
            end
            if burst.left <= 0 then self.bursting = nil end
        end
    end
    if self.dead then
        self.respawnTimer = self.respawnTimer - dt
        -- out = no lives left (Waves): stays down
        if self.respawnTimer <= 0 and not self.out then self:respawn() end
    elseif self.attack.kind == "beam" then -- energy: refills smoothly while it's off
        if self.beamLen <= 0 then self.ammo = math.min(self.maxAmmo, self.ammo + dt / self.ammoRefill) end
        self.ammoTimer = 0
    elseif self.ammo < self.maxAmmo then
        self.ammoTimer = self.ammoTimer + dt
        if self.ammoTimer >= self.ammoRefill then
            self.ammo = self.ammo + 1
            self.ammoTimer = 0
        end
    end
end

function Rowdy:respawn()
    self.x, self.y = self.spawnX, self.spawnY
    self.hp = self.maxHp
    self.ammo = self.maxAmmo
    self.ammoTimer = 0
    self.dead = false
    self:clearActions()
    self.cooldown = 0.5
    self.spawnAnim = SPAWN_TIME
    self:emit("spawn", { x = self.x, y = self.y, id = self.id })
end

-- Returns true if this hit killed the rowdy. killer: id of the shooter (in the
-- death event, for the Yard Pass XP)
function Rowdy:takeDamage(amount, killer)
    if self.dead then return false end
    self.hp = self.hp - amount
    self.hitFlash = 0.12
    if self.hp <= 0 then
        self.hp = 0
        self.dead = true
        self:releaseGrab()
        self.beamLen, self.beamHold = 0, 0
        self.respawnTimer = RESPAWN_TIME
        self:emit("death", { x = self.x, y = self.y, id = self.id, color = self.barColor,
            killer = killer })
        return true
    end
    return false
end

-- Walk animation state + footstep dust. `moved` = distance covered this frame.
function Rowdy:animateWalk(moved, dt)
    local walking = moved > dt * 20 -- faster than 20 px/s
    local target = walking and 1 or 0
    self.walkBlend = self.walkBlend + (target - self.walkBlend) * math.min(1, dt * 12)
    self.walkPhase = self.walkPhase + moved * 0.09
    if walking then
        self.stepTimer = self.stepTimer - dt
        if self.stepTimer <= 0 then
            self.stepTimer = 0.14
            if not Arena.inBush(self.x, self.y) then -- dust would give away a hiding spot
                self:emit("step", { id = self.id,
                    x = self.x - self.dirX * 12, y = self.y - self.dirY * 12 + 10 })
            end
        end
    end
end

-- Move in direction (dx, dy); the vector is normalized here.
function Rowdy:move(dx, dy, dt)
    local ox, oy = self.x, self.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0 then
        self.dirX, self.dirY = dx / len, dy / len
        local speed = self.burrowed and self.speed * BURROW_SPEED or self.speed
        if self.driving then speed = self.driving.speed or speed end
        self.x = self.x + self.dirX * speed * dt
        self.y = self.y + self.dirY * speed * dt
    end
    if self.vanished then -- walks through walls, but stays in the arena
        local r = self.radius
        self.x = math.max(r, math.min(Arena.width - r, self.x))
        self.y = math.max(r, math.min(Arena.height - r, self.y))
    else
        self.x, self.y = Arena.resolveCircle(self.x, self.y, self.radius)
    end
    self:animateWalk(math.sqrt((self.x - ox) ^ 2 + (self.y - oy) ^ 2), dt)
end

-- World position of the gun barrel (bullets spawn here); twin attacks alternate
-- between it and its mirror image (muzzleSide)
function Rowdy:muzzle()
    local m = self.look.muzzle
    local c, s = math.cos(self.aim), math.sin(self.aim)
    local side = m[2] * (self.muzzleSide or 1)
    return self.x + c * m[1] - s * side,
           self.y + s * m[1] + c * side
end

-- Not knocked out, frozen, pushed by somebody else or flying through the air (may
-- walk unless it is dashing: see Rowdy:walks)
function Rowdy:canMove()
    return not self.dead and self.frozen <= 0 and not (self.push and not self.push.own)
        and not self.leap and not self.heldBy
end

-- Walks by its own input this step (not during any push, not handcuffed)
function Rowdy:walks()
    return self:canMove() and not self.push and (self.rooted or 0) <= 0
end

-- May attack: can move, isn't underground and holds nobody
function Rowdy:canAct()
    return self:canMove() and not self.burrowed and not self.grab
end

-- Out of reach of bullets and blasts (in the air, underground or in a bulldozer)
function Rowdy:untouchable()
    return self.leap ~= nil or self.burrowed ~= nil or self.driving ~= nil
end

-- Move by a push: forced (pulled to a rowdy, flung) or own (the dash of a punch).
-- impact = { owner, attack }: hitting a wall, chest or rowdy hurts (a fling)
function Rowdy:pushBy(vx, vy, t, own, impact)
    self.push = { vx = vx, vy = vy, t = t, own = own, impact = impact }
end

-- A flung rowdy hits something: it takes the attack's damage, so does a rowdy it
-- crashes into (if that is an opponent of the flinger), and a chest
local function crash(self, push, other, box)
    local world, imp = self.world, push.impact
    self.push = nil
    if not world then return end
    world:emit("bonk", { id = self.id, x = self.x, y = self.y })
    world:hitWith(imp.owner, imp.attack, self, self.x, self.y)
    if other and other.team ~= imp.owner.team then
        world:hitWith(imp.owner, imp.attack, other, other.x, other.y)
    end
    if box then world:hitBox(box, { x = self.x, y = self.y, damage = imp.attack.damage, owner = imp.owner }) end
end

-- Ongoing actions, every step on the world side (from tick): pushes, leaps, burrows
function Rowdy:act(dt)
    local push = self.push
    if push then
        local step = math.min(dt, push.t)
        local ox, oy = self.x, self.y
        local wx, wy = self.x + push.vx * step, self.y + push.vy * step
        self.x, self.y = Arena.resolveCircle(wx, wy, self.radius)
        self:animateWalk(math.sqrt((self.x - ox) ^ 2 + (self.y - oy) ^ 2), dt)
        push.t = push.t - dt
        if push.t <= 0 then self.push = nil end
        if push.gust and self.world then -- a gust: stops at the first opponent or a wall
            local hit = push.t <= 0 or (wx - self.x) ^ 2 + (wy - self.y) ^ 2 > 1
            for _, e in ipairs(self.world.entities) do
                local reach = self.radius + e.radius + 6
                if e.team ~= self.team and not e.dead and not e:untouchable()
                    and (e.x - self.x) ^ 2 + (e.y - self.y) ^ 2 < reach * reach then
                    hit = true
                end
            end
            if hit then
                self.push = nil
                self.world:blastAt(self, push.gust, self.x, self.y)
            end
        end
        if push.impact and self.world then
            local other
            for _, e in ipairs(self.world.entities) do
                local reach = self.radius + e.radius
                if e ~= self and e ~= push.impact.owner and not e.dead and not e:untouchable()
                    and (e.x - self.x) ^ 2 + (e.y - self.y) ^ 2 < reach * reach then
                    other = e
                end
            end
            local box = self.world.boxAt and self.world:boxAt(self.x, self.y, self.radius + 2)
            local wall = (wx - self.x) ^ 2 + (wy - self.y) ^ 2 > 1
            if other or box or wall then crash(self, push, other, box) end
        end
    end
    local v = self.vanished
    if v then
        v.time = v.time - dt
        if v.time <= 0 then self:reappear() end
    end
    self:actBeam(dt)
    local grab = self.grab
    if grab then -- the grabbed rowdy follows the aim, then it is flung
        local victim = self.world and self.world.byId[grab.id]
        grab.time = grab.time - dt
        if not victim or victim.dead or victim.heldBy ~= self.id or self.frozen > 0 then
            self:releaseGrab()
        else
            local c, s = math.cos(self.aim), math.sin(self.aim)
            local hx, hy = self.x + c * grab.dist, self.y + s * grab.dist
            local dx, dy = hx - victim.x, hy - victim.y
            local d = math.sqrt(dx * dx + dy * dy)
            local stepLen = math.min(d, HOLD_SPEED * dt)
            if d > 0 then
                victim.x, victim.y = Arena.resolveCircle(victim.x + dx / d * stepLen,
                    victim.y + dy / d * stepLen, victim.radius)
            end
            self.beamLen = math.sqrt((victim.x - self.x) ^ 2 + (victim.y - self.y) ^ 2)
            if grab.time <= 0 then
                self:releaseGrab()
                victim:pushBy(c * FLING_SPEED, s * FLING_SPEED, FLING_TIME, false,
                    { owner = self, attack = grab.attack })
                self:emit("fling", { id = victim.id, by = self.id, x = victim.x, y = victim.y })
                self.beamLen = 0
            end
        end
    end
    local leap = self.leap
    if leap then
        leap.time = leap.time + dt
        local k = math.min(1, leap.time / leap.duration)
        self.x = leap.fromX + (leap.toX - leap.fromX) * k
        self.y = leap.fromY + (leap.toY - leap.fromY) * k
        self.air = math.sin(k * math.pi) * leap.height
        if k >= 1 then -- landed: everybody around is hit
            self.leap, self.air = nil, 0
            self.x, self.y = Arena.resolveCircle(self.x, self.y, self.radius)
            if self.world then self.world:blastAt(self, leap.attack, self.x, self.y) end
        end
    end
    local b = self.burrowed
    if b then
        b.time = b.time - dt
        local touched = false
        for _, e in ipairs(self.world and self.world.entities or {}) do
            local reach = self.radius + e.radius + 6
            if e.team ~= self.team and not e.dead and not e:untouchable()
                and (e.x - self.x) ^ 2 + (e.y - self.y) ^ 2 < reach * reach then
                touched = true
            end
        end
        if touched or b.time <= 0 then -- pops out, hitting everybody around
            self.burrowed = nil
            self.cooldown = math.max(self.cooldown, 0.3)
            if self.world then self.world:blastAt(self, b.attack, self.x, self.y) end
        end
    end
end

-- How far away an opponent can be for `attack` to reach it (bots decide with it):
-- punches dash forward first
function Rowdy:reach(attack)
    local range = attack.range or Bullet.range
    if attack.dash then range = range + attack.dash * (attack.burst or 1) end
    return range
end

-- Where a leap of `attack` would land now: aimDist away (from the body centre,
-- MIN_THROW..range), moved back towards the rowdy until there is room to stand
function Rowdy:leapTarget(attack)
    local range = attack.range or Bullet.range
    local d = math.max(Bullet.MIN_THROW, math.min(range, self.aimDist or range))
    local c, s = math.cos(self.aim), math.sin(self.aim)
    while d > 0 do
        local x, y = self.x + c * d, self.y + s * d
        if not Arena.hitsSolid(x, y, self.radius)
            and not (self.world and self.world.boxAt and self.world:boxAt(x, y, self.radius)) then
            return x, y
        end
        d = d - 8
    end
    return self.x, self.y
end

-- The beam (attack.kind "beam") while it is held: hits the first opponent or chest
-- on its line every BEAM_TICK, uses BEAM_DRAIN ammo bars per second
function Rowdy:actBeam(dt)
    self.beamHold = math.max(0, self.beamHold - dt)
    if self.grab then return end -- (its beam is the grab's)
    local attack = self.attack
    if attack.kind ~= "beam" or self.beamHold <= 0 or not self:canAct() or self.ammo <= 0
        or not self.world or self.carrying or self.driving then
        self.beamLen, self.beamTimer, self.beamSound = 0, nil, nil
        return
    end
    self.ammo = math.max(0, self.ammo - BEAM_DRAIN * dt)
    local len, victim, box = self.world:traceBeam(self, attack.range or Bullet.range)
    self.beamLen = len
    self.beamTimer = (self.beamTimer or 0) - dt
    if self.beamTimer <= 0 then
        self.beamTimer = self.beamTimer + BEAM_TICK
        local x, y = self.x + math.cos(self.aim) * len, self.y + math.sin(self.aim) * len
        if victim then self.world:hitWith(self, attack, victim, x, y)
        elseif box then self.world:hitBox(box, { x = x, y = y, damage = attack.damage, owner = self }) end
    end
    self.beamSound = (self.beamSound or 0) - dt
    if self.beamSound <= 0 then
        self.beamSound = BEAM_SOUND
        self:emit("shot", { id = self.id, x = self.x, y = self.y })
    end
end

-- Attacks that move the rowdy instead of firing projectiles (attack.kind)
local ACTIONS = {}

function ACTIONS.blink(self, attack) -- teleports (also through walls) with a "boo"
    local fx, fy = self.x, self.y
    self.x, self.y = self:leapTarget(attack)
    self:emit("blink", { id = self.id, x = fx, y = fy, toX = self.x, toY = self.y })
    if self.world then self.world:blastAt(self, attack, self.x, self.y) end
end

function ACTIONS.vanish(self, attack) -- invisible and through walls for a while
    self.vanished = { time = attack.duration or 5 }
    self:emit("vanish", { id = self.id, x = self.x, y = self.y })
end

function ACTIONS.grab(self, attack) -- the beam grabs the first opponent on its line
    if not self.world then return end
    local len, victim = self.world:traceBeam(self, attack.range or Bullet.range)
    local x, y = self.x + math.cos(self.aim) * len, self.y + math.sin(self.aim) * len
    if not victim then
        self:emit("grab", { id = self.id, x = x, y = y })
        return
    end
    victim.heldBy, victim.push, victim.bursting = self.id, nil, nil
    victim.beamHold = 0
    self.grab = { id = victim.id, time = attack.duration or 1.2, attack = attack,
        dist = math.max(self.radius + victim.radius + 30, math.min(len, 160)) }
    self:emit("grab", { id = self.id, victim = victim.id, x = victim.x, y = victim.y })
end

function ACTIONS.leap(self, attack) -- flies on an arc over everything, lands with a slam
    local tx, ty = self:leapTarget(attack)
    local d = math.sqrt((tx - self.x) ^ 2 + (ty - self.y) ^ 2)
    self.leap = { fromX = self.x, fromY = self.y, toX = tx, toY = ty, time = 0,
        duration = math.max(0.25, d / (attack.bulletSpeed or Bullet.speed)),
        height = LEAP_HEIGHT * math.max(0.5, math.min(1, d / 200)), attack = attack }
    self.push = nil
    self:emit("leap", { id = self.id, x = self.x, y = self.y, toX = tx, toY = ty })
end

function ACTIONS.heal(self, attack) -- heals itself (a share of its max HP)
    local amount = math.min(self.maxHp - self.hp, math.ceil(self.maxHp * (attack.heal or 0.5)))
    self.hp = self.hp + amount
    self:emit("heal", { id = self.id, x = self.x, y = self.y, amount = amount })
end

function ACTIONS.spin(self, attack) -- a spin: hits everybody around it
    if self.world then self.world:blastAt(self, attack, self.x, self.y) end
end

-- Where a gust (kind "gust") would carry the rowdy now: aimDist far (MIN_THROW..range),
-- up to the first wall
function Rowdy:gustTarget(attack)
    local range = attack.range or Bullet.range
    local d = math.max(Bullet.MIN_THROW, math.min(range, self.aimDist or range))
    d = Arena.raycast(self.x, self.y, self.aim, d, self.radius)
    return self.x + math.cos(self.aim) * d, self.y + math.sin(self.aim) * d, d
end

function ACTIONS.gust(self, attack) -- rides a gust of wind; hits the first opponent
    local tx, ty, d = self:gustTarget(attack)
    local speed = attack.bulletSpeed or 900
    local c, s = math.cos(self.aim), math.sin(self.aim)
    self.push = { vx = c * speed, vy = s * speed, t = math.max(0.05, d / speed), own = true,
        gust = attack }
    self:emit("gust", { id = self.id, x = self.x, y = self.y, toX = tx, toY = ty })
end

function ACTIONS.magnet(self, attack) -- pulls the `targets` nearest opponents in range
    local world = self.world
    if not world then return end
    local list = {}
    for _, e in ipairs(world.entities) do
        local d2 = (e.x - self.x) ^ 2 + (e.y - self.y) ^ 2
        local range = (attack.range or Bullet.range) + e.radius
        if e.team ~= self.team and not e.dead and not e:untouchable() and d2 < range * range
            and not world:isHiddenFrom(e, self)
            and Arena.hasLineOfSight(self.x, self.y, e.x, e.y) then
            list[#list + 1] = { e = e, d2 = d2 }
        end
    end
    table.sort(list, function(a, b) return a.d2 < b.d2 end)
    self:emit("magnet", { id = self.id, x = self.x, y = self.y, n = math.min(#list, attack.targets or 2) })
    for i = 1, math.min(#list, attack.targets or 2) do
        world:hitWith(self, attack, list[i].e, list[i].e.x, list[i].e.y)
    end
end

function ACTIONS.barrier(self, attack) -- a fence only the own team gets through
    if self.world then self.world:addBarrier(self, attack) end
end

function ACTIONS.burrow(self, attack) -- digs in: can't be hit, pops out under somebody
    self.burrowed = { time = attack.duration or 4, attack = attack }
    self:emit("burrow", { id = self.id, x = self.x, y = self.y })
end

-- Fire `attack.pellets` projectiles in a cone of `attack.spread` (attack: self.attack
-- or self.super); spread >= pi: an even ring from the body centre.
-- Bombs (attack.lob) fly self.aimDist far (where the player aimed).
-- A burst attack fires its first shot here and the others from tick(); follow = one
-- of those.
function fire(self, bullets, attack, follow)
    local action = ACTIONS[attack.kind]
    if action then
        action(self, attack)
        self.cooldown = self.reload
        return
    end
    if attack.dash then -- a punch: a short dash forward (up to an opponent), then the hit
        local c, s = math.cos(self.aim), math.sin(self.aim)
        local dash = attack.dash
        for _, e in ipairs(self.world and self.world.entities or {}) do
            if e.team ~= self.team and not e.dead then
                local along = (e.x - self.x) * c + (e.y - self.y) * s
                local across = math.abs((e.y - self.y) * c - (e.x - self.x) * s)
                local room = self.radius + e.radius
                if along > 0 and across < room then dash = math.min(dash, math.max(0, along - room - 4)) end
            end
        end
        self:pushBy(c * dash / DASH_TIME, s * dash / DASH_TIME, DASH_TIME, true)
        self:emit("punch", { id = self.id, x = self.x, y = self.y })
    end
    if attack.twin then self.muzzleSide = -(self.muzzleSide or 1) else self.muzzleSide = 1 end
    local bx, by = self:muzzle()
    local n, spread = attack.pellets or 1, attack.spread or 0
    local ring = spread >= math.pi
    if ring then bx, by = self.x, self.y end
    for i = 1, n do
        local a = self.aim
        if ring then -- evenly all around, the first one straight along the aim
            a = a + (i - 1) / n * math.pi * 2
        elseif n > 1 then
            local t = (i - 1) / (n - 1) - 0.5 -- -0.5 .. 0.5 across the cone
            a = a + t * spread + (math.random() - 0.5) * spread * 0.15
        end
        bullets[#bullets + 1] = Bullet.new(bx, by, a, self, attack, self:throwDist())
    end
    if not follow then
        self.cooldown = self.reload
        local shots = attack.burst or 1
        if shots > 1 then
            local delay = attack.burstDelay or BURST_DELAY
            self.bursting = { attack = attack, left = shots - 1, timer = delay, delay = delay }
        end
    end
    self.recoil = 1
    self.flashTimer = FLASH_TIME
    self.flashSize = (n > 1) and 1.5 or 1
    if attack == self.attack then self:emit("shot", { id = self.id, x = bx, y = by }) end
end

-- How far a bomb flies from the muzzle: aimDist is measured from the body centre, so
-- the bomb lands where the player aimed (nil = full range)
function Rowdy:throwDist()
    return self.aimDist and (self.aimDist - self.look.muzzle[1])
end

-- Where a bomb of `attack` (self.attack or self.super) would land now; angle: the
-- direction of one of its pellets (default: the aim)
function Rowdy:landing(attack, angle)
    local mx, my = self:muzzle()
    local range = attack.range or Bullet.range
    local d = math.max(Bullet.MIN_THROW, math.min(range, self:throwDist() or range))
    angle = angle or self.aim
    return mx + math.cos(angle) * d, my + math.sin(angle) * d
end

-- One attack: uses one ammo bar and fires `pellets` projectiles in a cone.
-- Returns true if the attack happened. (Not while carrying the ball: the attack kicks it;
-- not in a bulldozer.)
function Rowdy:shoot(bullets, hold)
    if self.carrying or self.noAttacks or self.driving then return false end
    if self.attack.kind == "beam" then -- keeps the beam on (a tap: a bit longer)
        if not self:canAct() or self.ammo <= 0.05 then return false end
        self.beamHold = math.max(self.beamHold, hold and 0.12 or 0.35)
        return true
    end
    if not self:canAct() or self.cooldown > 0 or self.ammo < 1 or self.bursting then
        return false
    end
    fire(self, bullets, self.attack)
    self.ammo = self.ammo - 1
    return true
end

function Rowdy:superReady()
    return self.super ~= nil and self.charge >= 1 and not self.dead
end

-- Damage dealt with normal attacks fills the super meter (chargeScale: slower for bots)
function Rowdy:addCharge(damage)
    if not self.super then return end
    local before = self.charge
    self.charge = math.min(1, self.charge + damage * (self.chargeScale or 1) / self.super.charge)
    -- 10 x 0.1 adds up to 0.999..., which would need one hit more than intended
    if self.charge > 1 - 1e-6 then self.charge = 1 end
    if before < 1 and self.charge >= 1 then self:emit("superReady", { id = self.id }) end
end

-- The super attack: needs a full meter, no ammo. Returns true if it happened.
function Rowdy:shootSuper(bullets)
    if not self:superReady() or not self:canAct() or self.cooldown > 0 or self.noAttacks
        or self.driving then
        return false
    end
    self.bursting = nil
    fire(self, bullets, self.super)
    -- (a burst super keeps its follow-up shots: fire set self.bursting again)
    self.charge = 0
    self.flashSize = 2.2
    local mx, my = self:muzzle()
    self:emit("super", { id = self.id, x = mx, y = my })
    return true
end

-- Aiming indicator: a beam for single shots, a cone for
-- spread attacks. It ends at the first wall or crate. useSuper: for the super attack
-- (gold, its own range/spread/bullet size).
function Rowdy:drawAim(useSuper)
    if self.dead then return end
    local a = (useSuper and self.super) or self.attack
    local spread = a.spread or 0
    -- (the normal attack's beam has always been as wide as the body)
    local radius = a.radius or (a == self.attack and self.radius) or Bullet.radius
    local c = (a == self.attack) and self.bulletColor or SUPER_COLOR
    if a.kind == "beam" or a.kind == "grab" then -- a thin line to the first wall
        local mx, my = self:muzzle()
        local len = Arena.raycast(mx, my, self.aim, a.range or Bullet.range, 3)
        love.graphics.setColor(c[1], c[2], c[3], 0.5)
        love.graphics.setLineWidth(3)
        love.graphics.line(mx, my, mx + math.cos(self.aim) * len, my + math.sin(self.aim) * len)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)
        return
    end
    if a.kind == "heal" then -- a green "+" ring around itself
        love.graphics.setColor(0.4, 1, 0.4, 0.7)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", self.x, self.y, self.radius + 16)
        love.graphics.rectangle("fill", self.x - 3, self.y - self.radius - 34, 6, 18)
        love.graphics.rectangle("fill", self.x - 9, self.y - self.radius - 28, 18, 6)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)
        return
    end
    if a.kind == "magnet" or a.kind == "barrier" then
        if a.kind == "barrier" then -- the fence where it will stand
            local World = require("src.world") -- (loaded by now; rowdy.lua is required by it)
            love.graphics.setColor(c[1], c[2], c[3], 0.7)
            love.graphics.setLineWidth(World.BARRIER_HALF * 2)
            love.graphics.line(World.barrierPoints(self))
        else -- a dashed circle: who is in range gets pulled
            love.graphics.setColor(c[1], c[2], c[3], 0.6)
            love.graphics.setLineWidth(2)
            local r = a.range or Bullet.range
            for i = 0, 35, 2 do
                love.graphics.arc("line", "open", self.x, self.y, r, i / 36 * math.pi * 2, (i + 1) / 36 * math.pi * 2)
            end
        end
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)
        return
    end
    if a.kind == "vanish" then -- how close opponents still see the ghost
        love.graphics.setColor(c[1], c[2], c[3], 0.6)
        love.graphics.setLineWidth(2)
        for i = 0, 23, 2 do
            love.graphics.arc("line", "open", self.x, self.y, 150, i / 24 * math.pi * 2, (i + 1) / 24 * math.pi * 2)
        end
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)
        return
    end
    if a.kind == "leap" or a.kind == "burrow" or a.kind == "blink" or a.kind == "spin"
        or a.kind == "gust" then
        -- leap: a dotted arc to the landing spot; burrow: around the rowdy. And the
        -- circle the slam / pop-out hits
        local lx, ly = self.x, self.y
        if a.kind == "blink" or a.kind == "gust" then -- a dashed line to where it goes
            if a.kind == "gust" then lx, ly = self:gustTarget(a) else lx, ly = self:leapTarget(a) end
            love.graphics.setColor(c[1], c[2], c[3], 0.75)
            for j = 1, 10, 2 do
                love.graphics.line(self.x + (lx - self.x) * j / 11, self.y + (ly - self.y) * j / 11,
                    self.x + (lx - self.x) * (j + 1) / 11, self.y + (ly - self.y) * (j + 1) / 11)
            end
        elseif a.kind == "leap" then
            lx, ly = self:leapTarget(a)
            local h = LEAP_HEIGHT * math.max(0.5, math.min(1, math.sqrt((lx - self.x) ^ 2 + (ly - self.y) ^ 2) / 200))
            love.graphics.setColor(c[1], c[2], c[3], 0.75)
            for j = 1, 11 do
                local t = j / 12
                love.graphics.circle("fill", self.x + (lx - self.x) * t,
                    self.y + (ly - self.y) * t - math.sin(t * math.pi) * h, 2.5)
            end
        end
        love.graphics.setColor(c[1], c[2], c[3], 0.18)
        love.graphics.circle("fill", lx, ly, a.blast)
        love.graphics.setColor(c[1], c[2], c[3], 0.7)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", lx, ly, a.blast)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)
        return
    end
    if a.lob then -- bomb: a dotted arc to where it lands and the blast circle there
        local n = a.pellets or 1
        local mx, my = self:muzzle()
        for i = 1, n do -- several bombs: one landing spot each
            local angle = self.aim
            if n > 1 then angle = angle + ((i - 1) / (n - 1) - 0.5) * spread end
            local lx, ly = self:landing(a, angle)
            local d = math.sqrt((lx - mx) ^ 2 + (ly - my) ^ 2)
            local h = math.min(140, d * 0.35)
            love.graphics.setColor(c[1], c[2], c[3], 0.75)
            for j = 1, 11 do
                local t = j / 12
                love.graphics.circle("fill", mx + (lx - mx) * t, my + (ly - my) * t - math.sin(t * math.pi) * h, 2.5)
            end
            love.graphics.setColor(c[1], c[2], c[3], 0.18)
            love.graphics.circle("fill", lx, ly, a.blast)
            love.graphics.setColor(c[1], c[2], c[3], 0.7)
            love.graphics.setLineWidth(2)
            love.graphics.circle("line", lx, ly, a.blast)
            love.graphics.setLineWidth(1)
        end
        love.graphics.setColor(1, 1, 1, 1)
        return
    end
    if spread >= math.pi then -- ring attack: a circle of its range around the rowdy
        local r = a.range or Bullet.range
        love.graphics.setColor(c[1], c[2], c[3], 0.12)
        love.graphics.circle("fill", self.x, self.y, r)
        love.graphics.setColor(c[1], c[2], c[3], 0.6)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", self.x, self.y, r)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)
        return
    end
    local mx, my = self:muzzle()
    local len = Arena.raycast(mx, my, self.aim, self:reach(a),
        a.wallRadius or a.radius or Bullet.radius)
    local hw = math.max(9, radius + 3)
    local hwEnd = hw + math.tan(spread / 2) * len

    self.aimMesh = self.aimMesh or love.graphics.newMesh(4, "fan", "stream")
    self.aimMesh:setVertices({
        { 0,   -hw,    0, 0, c[1], c[2], c[3], 0.55 },
        { len, -hwEnd, 0, 0, c[1], c[2], c[3], 0.12 },
        { len,  hwEnd, 0, 0, c[1], c[2], c[3], 0.12 },
        { 0,    hw,    0, 0, c[1], c[2], c[3], 0.55 },
    })

    love.graphics.push()
    love.graphics.translate(mx, my)
    love.graphics.rotate(self.aim)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.aimMesh)
    love.graphics.setColor(c[1], c[2], c[3], 0.6)
    love.graphics.setLineWidth(2)
    if spread > 0 then
        love.graphics.line(0, -hw, len, -hwEnd, len, hwEnd, 0, hw)
    elseif a.boomerang then -- a U-turn arrow at the end: it comes back
        local r = hw * 0.8
        love.graphics.arc("line", "open", len - r, 0, r, -math.pi / 2, math.pi / 2, 12)
        love.graphics.line(len - r, r, len - r - 9, r - 6)
        love.graphics.line(len - r, r, len - r - 9, r + 6)
        love.graphics.line(len - r, -r, 0, -r)
    else
        love.graphics.setColor(c[1], c[2], c[3], 0.12)
        love.graphics.circle("fill", len, 0, hw)
        love.graphics.setColor(c[1], c[2], c[3], 0.6)
        love.graphics.circle("line", len, 0, hw)
    end
    love.graphics.setLineWidth(1)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

function Rowdy:drawAmmoBar(x, y, w)
    local n, gap = self.maxAmmo, 3
    local sw = (w - gap * (n - 1)) / n
    for i = 1, n do
        local sx = x + (i - 1) * (sw + gap)
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("fill", sx - 1, y - 1, sw + 2, 7, 2, 2)
        love.graphics.setColor(0.3, 0.3, 0.3, 1)
        love.graphics.rectangle("fill", sx, y, sw, 5, 1, 1)
        local fill = 0
        if i <= self.ammo then fill = 1
        elseif i == self.ammo + 1 then fill = self.ammoTimer / self.ammoRefill
        elseif i - 1 < self.ammo then fill = self.ammo - (i - 1) end -- (beam energy)
        if fill > 0 then
            love.graphics.setColor(1, 0.6, 0.15, 1)
            love.graphics.rectangle("fill", sx, y, sw * fill, 5, 1, 1)
        end
    end
end

function Rowdy:drawHealthBar()
    if self.noBars then return end -- (Hide and seek: no HP to show, set by the renderer)
    local w, h = 48, 7
    local x, y = self.x - w / 2, self.y - self.radius - 22
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 4, 3, 3)
    love.graphics.setColor(0.25, 0.25, 0.25, 1)
    love.graphics.rectangle("fill", x, y, w, h, 2, 2)
    local c = self.hudColor or self.barColor -- hudColor: set by the renderer (team colors)
    love.graphics.setColor(c[1], c[2], c[3], 1)
    love.graphics.rectangle("fill", x, y, w * (self.hp / self.maxHp), h, 2, 2)
    if self.showAmmo then
        self:drawAmmoBar(x, y + h + 5, w)
        if self.super then -- super meter: thin gold bar under the ammo
            local sy = y + h + 13
            love.graphics.setColor(0, 0, 0, 0.8)
            love.graphics.rectangle("fill", x - 1, sy - 1, w + 2, 5, 2, 2)
            local c = SUPER_COLOR
            love.graphics.setColor(c[1], c[2], c[3], self.charge >= 1 and 1 or 0.75)
            love.graphics.rectangle("fill", x, sy, w * math.min(1, self.charge), 3, 1, 1)
        end
    end
end

-- Muzzle flash: a short additive glow with a few rays
function Rowdy:drawMuzzleFlash()
    if self.flashTimer <= 0 then return end
    local k = self.flashTimer / FLASH_TIME
    local mx, my = self:muzzle()
    local size = self.flashSize
    love.graphics.setBlendMode("add")
    love.graphics.setColor(1, 0.85, 0.4, k)
    love.graphics.circle("fill", mx, my, (6 + 6 * k) * size)
    love.graphics.setColor(1, 1, 1, k)
    love.graphics.circle("fill", mx, my, 4 * size)
    love.graphics.setColor(1, 0.8, 0.3, k)
    love.graphics.setLineWidth(3)
    for i = -1, 1 do
        local a = self.aim + i * 0.4
        love.graphics.line(mx, my, mx + math.cos(a) * 22 * size, my + math.sin(a) * 22 * size)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setBlendMode("alpha")
end

-- Frozen (src/rowdies.lua: freeze): a light-blue ice block with sparkles; it melts
-- (fades) in the last half second
function Rowdy:drawIce(alpha)
    local k = math.min(1, self.frozen / 0.5) * alpha
    local r = self.radius + 10
    local c = ICE_COLOR
    love.graphics.setColor(c[1], c[2], c[3], 0.4 * k)
    love.graphics.rectangle("fill", self.x - r, self.y - r, 2 * r, 2 * r, 8, 8)
    love.graphics.setColor(1, 1, 1, 0.85 * k)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", self.x - r, self.y - r, 2 * r, 2 * r, 8, 8)
    love.graphics.line(self.x - r + 6, self.y - r + 14, self.x - r + 14, self.y - r + 6)
    love.graphics.line(self.x - r + 6, self.y - r + 24, self.x - r + 24, self.y - r + 6)
    love.graphics.setLineWidth(1)
    local t = love.timer.getTime()
    for i = 1, 3 do -- twinkling stars
        local a = t * 1.5 + i * 2.1
        local x, y = self.x + math.cos(a) * r * 0.8, self.y + math.sin(a * 1.3) * r * 0.8
        local s = 3 + 2 * math.sin(t * 6 + i)
        love.graphics.line(x - s, y, x + s, y)
        love.graphics.line(x, y - s, x, y + s)
    end
end

-- Handcuffed (src/rowdies.lua: hold): toy cuffs round the feet, a little shake
function Rowdy:drawCuffs(alpha)
    local t = love.timer.getTime()
    local x, y = self.x + math.sin(t * 30) * 1.5, self.y + self.radius * 0.6
    for _, side in ipairs({ -1, 1 }) do
        love.graphics.setLineWidth(5)
        love.graphics.setColor(0.15, 0.15, 0.2, alpha)
        love.graphics.circle("line", x + side * 9, y, 7)
        love.graphics.setLineWidth(3)
        love.graphics.setColor(0.85, 0.87, 0.92, alpha)
        love.graphics.circle("line", x + side * 9, y, 7)
    end
    love.graphics.setLineWidth(1)
end

-- Sticky goo (src/rowdies.lua: goo): green drips and bubbles on the rowdy
function Rowdy:drawGoo(alpha)
    local t = love.timer.getTime()
    for i = 1, 4 do
        local a = i * 1.6
        local k = (t * 0.8 + i * 0.27) % 1
        local x = self.x + math.cos(a) * self.radius * 0.6
        local y = self.y + math.sin(a) * self.radius * 0.5 + k * 14
        love.graphics.setColor(0.45, 0.95, 0.2, (1 - k) * 0.9 * alpha)
        love.graphics.circle("fill", x, y, 3.5 - k * 1.5)
    end
end

-- The beam (src/rowdies.lua: beam / grab): a wobbling glowing line from the muzzle
function Rowdy:drawBeam()
    local mx, my = self:muzzle()
    local c, s = math.cos(self.aim), math.sin(self.aim)
    local len = math.max(0, self.beamLen - self.look.muzzle[1])
    local col = (self.grab or self.grabbing) and SUPER_COLOR or BEAM_COLOR
    local t = love.timer.getTime()
    local pts = {}
    for i = 0, 12 do
        local k = i / 12
        local w = math.sin(t * 30 + i * 1.7) * 4 * math.sin(k * math.pi)
        pts[#pts + 1] = mx + c * len * k - s * w
        pts[#pts + 1] = my + s * len * k + c * w
    end
    love.graphics.setBlendMode("add")
    love.graphics.setColor(col[1], col[2], col[3], 0.35)
    love.graphics.setLineWidth(12)
    love.graphics.line(pts)
    love.graphics.setColor(col[1], col[2], col[3], 0.9)
    love.graphics.setLineWidth(4)
    love.graphics.line(pts)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.setLineWidth(1.5)
    love.graphics.line(pts)
    love.graphics.setColor(col[1], col[2], col[3], 0.6)
    love.graphics.circle("fill", mx + c * len, my + s * len, 7 + 2 * math.sin(t * 20))
    love.graphics.setBlendMode("alpha")
    love.graphics.setLineWidth(1)
end

-- Underground (src/rowdies.lua: burrow): a heap of dirt with clods that wobble
function Rowdy:drawMound(alpha)
    local t = love.timer.getTime()
    local r = self.radius + 6
    local wob = 1 + 0.08 * math.sin(t * 14 + self.walkPhase)
    love.graphics.setColor(0.25, 0.16, 0.08, 0.9 * alpha)
    love.graphics.ellipse("fill", self.x, self.y + 4, r * 1.15 * wob, r * 0.8 / wob)
    love.graphics.setColor(0.5, 0.34, 0.18, alpha)
    love.graphics.ellipse("fill", self.x, self.y, r * wob, r * 0.65 / wob)
    love.graphics.setColor(0.62, 0.45, 0.26, alpha)
    for i = 1, 5 do
        local a = i * 1.3 + self.walkPhase * 0.3
        love.graphics.circle("fill", self.x + math.cos(a) * r * 0.55, self.y + math.sin(a) * r * 0.35, 4)
    end
end

function Rowdy:draw()
    if self.dead then return end

    -- Pop-in after respawn
    local pop, alpha = 1, 1
    if self.spawnAnim > 0 then
        local k = 1 - self.spawnAnim / SPAWN_TIME
        pop, alpha = 0.4 + 0.6 * k, k
    end

    -- Walk cycle: body sways and squashes with the steps; idle: slow breathing
    local t = love.timer.getTime()
    local sway = math.sin(self.walkPhase) * 0.10 * self.walkBlend
    local bob = math.sin(self.walkPhase * 2) * 0.05 * self.walkBlend
    local breath = math.sin(t * 2.5) * 0.02 * (1 - self.walkBlend)
    local sx = (1 + bob + breath) * pop * (1 - 0.06 * self.recoil)
    local sy = (1 - bob - breath) * pop

    -- Recoil pushes the body backwards along the aim direction
    local px = self.x - math.cos(self.aim) * self.recoil * 5
    local py = self.y - math.sin(self.aim) * self.recoil * 5

    -- In the air (a leap): the shadow stays on the ground, smaller; the body is higher
    -- and a bit bigger
    local air = self.air or 0
    local shadow = 1 - 0.4 * math.min(1, air / LEAP_HEIGHT)
    py = py - air
    if not self.burrowed then
        love.graphics.setColor(0, 0, 0, 0.25 * alpha)
        love.graphics.ellipse("fill", self.x, self.y + 6, self.radius * pop * shadow,
            self.radius * 0.8 * pop * shadow)
    end

    -- Team fight: ring in the team color (set by the renderer: allies blue, enemies red)
    if self.teamColor then -- wider than the sprite, so it shows around it
        local c = self.teamColor
        local rx, ry = (self.radius + 14) * pop, (self.radius + 8) * pop
        love.graphics.setColor(c[1], c[2], c[3], 0.25 * alpha)
        love.graphics.ellipse("fill", self.x, self.y + 6, rx, ry)
        love.graphics.setColor(c[1], c[2], c[3], 0.9 * alpha)
        love.graphics.setLineWidth(3)
        love.graphics.ellipse("line", self.x, self.y + 6, rx, ry)
        love.graphics.setLineWidth(1)
    end

    -- Super ready: pulsing gold ring under the rowdy (visible to everybody)
    if self:superReady() then
        local k = 0.5 + 0.5 * math.sin(t * 6)
        local c = SUPER_COLOR
        love.graphics.setColor(c[1], c[2], c[3], (0.35 + 0.35 * k) * alpha)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", self.x, self.y + 4, (self.radius + 8 + 3 * k) * pop)
        love.graphics.setLineWidth(1)
    end

    if self.vanished then -- invisible (opponents far away don't draw it at all): a shimmer
        alpha = alpha * (0.3 + 0.1 * math.sin(t * 9))
    end
    if self.burrowed then -- underground: only a dirt mound moves around
        self:drawMound(alpha)
        self:drawHealthBar()
        love.graphics.setColor(1, 1, 1, 1)
        return
    end

    if self.hitFlash > 0 then
        love.graphics.setColor(1, 0.4, 0.4, alpha)
    else
        love.graphics.setColor(1, 1, 1, alpha)
    end
    -- The art faces up: rotate a quarter turn more, and sx (the aim axis) is its y
    local look = self.look
    local k = look.scale * (1 + air / 400)
    local shaded = Assets.beginSkin(look) -- colour-change skin (src/cosmetics.lua)
    love.graphics.draw(Assets.comic[look.image], px, py, self.aim + sway + math.pi / 2,
        k * sy, k * sx, look.origin[1], look.origin[2])
    if shaded then love.graphics.setShader() end
    if self.frozen > 0 then self:drawIce(alpha) end
    if (self.rooted or 0) > 0 then self:drawCuffs(alpha) end
    if self.goo then self:drawGoo(alpha) end
    if self.heldBy then -- grabbed by a beam: purple sparkles around it
        love.graphics.setColor(BEAM_COLOR[1], BEAM_COLOR[2], BEAM_COLOR[3], 0.8 * alpha)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", self.x, py, self.radius + 8 + 3 * math.sin(t * 12))
        love.graphics.setLineWidth(1)
    end
    if (self.beamLen or 0) > 0 then self:drawBeam() end

    self:drawMuzzleFlash()
    self:drawHealthBar()
    love.graphics.setColor(1, 1, 1, 1)
end

return Rowdy
