-- Shared base for everything that walks, aims, shoots and has HP.
-- Player and Enemy inherit from this.
-- Game logic (update/tick/move/shoot/takeDamage) never touches graphics or effects:
-- what happened is reported with self:emit() to the world (see src/world.lua).
local Arena   = require("src.arena")
local Assets  = require("src.assets")
local Bullet  = require("src.bullet")

local Rowdy = {}
Rowdy.__index = Rowdy

-- Sprite geometry (Kenney characters: body center at (16, 21.5), facing right)
local ORIGIN_X, ORIGIN_Y = 16, 21.5
-- Where the barrel ends, per weapon pose: {forward, sideways} from the body center
local MUZZLE = { gun = { 33, 8 }, machine = { 33, 8 }, silencer = { 38, 8 } }

local RESPAWN_TIME = 2.5
local SPAWN_TIME   = 0.35 -- pop-in animation after respawn
local FLASH_TIME   = 0.07 -- muzzle flash
local SUPER_COLOR  = { 1, 0.82, 0.1 } -- super meter, aim and "ready" glow

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
    self.super       = stats.super             -- nil: no super attack
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
    if self.dead then
        self.respawnTimer = self.respawnTimer - dt
        -- out = no lives left (Waves): stays down
        if self.respawnTimer <= 0 and not self.out then self:respawn() end
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
    self.cooldown = 0.5
    self.spawnAnim = SPAWN_TIME
    self:emit("spawn", { x = self.x, y = self.y, id = self.id })
end

-- Returns true if this hit killed the rowdy.
function Rowdy:takeDamage(amount)
    if self.dead then return false end
    self.hp = self.hp - amount
    self.hitFlash = 0.12
    if self.hp <= 0 then
        self.hp = 0
        self.dead = true
        self.respawnTimer = RESPAWN_TIME
        self:emit("death", { x = self.x, y = self.y, id = self.id, color = self.barColor })
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
        self.x = self.x + self.dirX * self.speed * dt
        self.y = self.y + self.dirY * self.speed * dt
    end
    self.x, self.y = Arena.resolveCircle(self.x, self.y, self.radius)
    self:animateWalk(math.sqrt((self.x - ox) ^ 2 + (self.y - oy) ^ 2), dt)
end

-- World position of the gun barrel (bullets spawn here)
function Rowdy:muzzle()
    local m = self.look.muzzle or MUZZLE[self.look.weapon] or MUZZLE.gun
    local c, s = math.cos(self.aim), math.sin(self.aim)
    return self.x + c * m[1] - s * m[2],
           self.y + s * m[1] + c * m[2]
end

-- Fire `attack.pellets` projectiles in a cone of `attack.spread` (attack: self for the
-- normal attack, or self.super); spread >= pi: an even ring from the body centre
local function fire(self, bullets, attack)
    local bx, by = self:muzzle()
    local n, spread = attack.pellets or 1, attack.spread or 0
    local ring = spread >= math.pi
    if ring then bx, by = self.x, self.y end
    for i = 1, n do
        local a = self.aim
        if n > 1 then
            local t = (i - 1) / (n - 1) - 0.5 -- -0.5 .. 0.5 across the cone
            a = a + t * spread
            if not ring then a = a + (math.random() - 0.5) * spread * 0.15 end
        end
        bullets[#bullets + 1] = Bullet.new(bx, by, a, self, attack ~= self and attack or nil)
    end
    self.cooldown = self.reload
    self.recoil = 1
    self.flashTimer = FLASH_TIME
    self.flashSize = (n > 1) and 1.5 or 1
    if attack == self then self:emit("shot", { id = self.id, x = bx, y = by }) end
end

-- One attack: uses one ammo bar and fires `pellets` projectiles in a cone.
-- Returns true if the attack happened.
function Rowdy:shoot(bullets)
    if self.dead or self.cooldown > 0 or self.ammo < 1 then return false end
    fire(self, bullets, self)
    self.ammo = self.ammo - 1
    return true
end

function Rowdy:superReady()
    return self.super ~= nil and self.charge >= 1 and not self.dead
end

-- Damage dealt with normal attacks fills the super meter
function Rowdy:addCharge(damage)
    if not self.super then return end
    local before = self.charge
    self.charge = math.min(1, self.charge + damage / self.super.charge)
    -- 10 x 0.1 adds up to 0.999..., which would need one hit more than intended
    if self.charge > 1 - 1e-6 then self.charge = 1 end
    if before < 1 and self.charge >= 1 then self:emit("superReady", { id = self.id }) end
end

-- The super attack: needs a full meter, no ammo. Returns true if it happened.
function Rowdy:shootSuper(bullets)
    if not self:superReady() or self.cooldown > 0 then return false end
    fire(self, bullets, self.super)
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
    local a = (useSuper and self.super) or self
    local spread, radius = a.spread or 0, a.radius or Bullet.radius
    local c = (a == self) and self.bulletColor or SUPER_COLOR
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
    local len = Arena.raycast(mx, my, self.aim, a.range or Bullet.range, a.wallRadius or radius)
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
        elseif i == self.ammo + 1 then fill = self.ammoTimer / self.ammoRefill end
        if fill > 0 then
            love.graphics.setColor(1, 0.6, 0.15, 1)
            love.graphics.rectangle("fill", sx, y, sw * fill, 5, 1, 1)
        end
    end
end

function Rowdy:drawHealthBar()
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

    love.graphics.setColor(0, 0, 0, 0.25 * alpha)
    love.graphics.ellipse("fill", self.x, self.y + 6, self.radius * pop, self.radius * 0.8 * pop)

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

    if self.hitFlash > 0 then
        love.graphics.setColor(1, 0.4, 0.4, alpha)
    else
        love.graphics.setColor(1, 1, 1, alpha)
    end
    local look = self.look
    if look.style == "comic" then
        -- Comic art faces up: rotate a quarter turn more, and sx (the aim axis) is its y
        local k = look.scale
        love.graphics.draw(Assets.comic[look.image], px, py, self.aim + sway + math.pi / 2,
            k * sy, k * sx, look.origin[1], look.origin[2])
    else
        -- Out of ammo: show the reload pose
        local poses = Assets.characters[look.character]
        local pose = (self.ammo == 0) and "reload" or look.weapon
        local img = poses[pose] or poses.gun
        love.graphics.draw(img, px, py, self.aim + sway, sx, sy, ORIGIN_X, ORIGIN_Y)
    end

    self:drawMuzzleFlash()
    self:drawHealthBar()
    love.graphics.setColor(1, 1, 1, 1)
end

return Rowdy
