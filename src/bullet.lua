local Cosmetics = require("src.cosmetics")

local Bullet = {}
Bullet.__index = Bullet

-- Defaults (a rowdy can override speed and range in its stats)
Bullet.radius = 6
Bullet.speed = 600
Bullet.life = 0.8
Bullet.range = Bullet.speed * Bullet.life -- 480px

Bullet.MIN_THROW = 60 -- px: the shortest throw of a bomb
Bullet.BOMB_RADIUS = 9 -- drawn size of a bomb without its own radius

-- attack: the parameters of this shot (rowdy stats or its super, see
-- src/rowdies.lua); defaults to the owner's normal attack.
-- dist: how far a bomb (attack.lob) flies, clamped to MIN_THROW..range (nil = range)
function Bullet.new(x, y, angle, owner, attack, dist)
    local super = attack ~= nil
    attack = attack or owner
    local speed = attack.bulletSpeed or Bullet.speed
    local range = attack.range or Bullet.range
    if attack.lob then -- flies `dist`, then explodes (src/world.lua)
        range = math.max(Bullet.MIN_THROW, math.min(range, tonumber(dist) or range))
    end
    return setmetatable({
        x = x, y = y,
        vx = math.cos(angle) * speed,
        vy = math.sin(angle) * speed,
        life = range / speed,
        owner = owner,
        team = owner.team, -- only hits rowdies of other teams
        damage = attack.damage,
        -- (owner.radius is the rowdy's body, so only a super sets the bullet size)
        radius = super and attack.radius or Bullet.radius,
        -- size against walls/crates (default: radius); smaller lets a big ball graze them
        wallRadius = super and attack.wallRadius or nil,
        pierce = super and attack.pierce, -- flies through rowdies (hits each one once)
        lob = attack.lob,       -- a bomb: over everything, explodes when life runs out
        blast = attack.lob and attack.blast or nil,
        flight = range / speed, -- whole flight time (a bomb's arc is drawn from it)
        super = super,
        color = owner.bulletColor,
        trail = owner.trail, -- Yard Pass trail (src/cosmetics.lua), only drawn
    }, Bullet)
end

function Bullet:update(dt)
    self.x = self.x + self.vx * dt
    self.y = self.y + self.vy * dt
    self.life = self.life - dt
end

-- A bomb in flight: a shadow on the ground where it is, the bomb above it on an arc
-- (highest in the middle of the flight), with a sparking fuse
function Bullet:drawBomb()
    local r = math.max(self.radius or 0, Bullet.BOMB_RADIUS)
    local p = math.max(0, math.min(1, 1 - self.life / self.flight))
    local speed = math.sqrt(self.vx * self.vx + self.vy * self.vy)
    local h = math.sin(p * math.pi) * math.min(140, self.flight * speed * 0.35)
    local k = 1 - 0.4 * h / 140
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.ellipse("fill", self.x, self.y, r * k, r * 0.55 * k)
    local x, y = self.x, self.y - h
    local spin = p * 9
    love.graphics.setColor(0.08, 0.08, 0.1)
    love.graphics.circle("fill", x, y, r + 2)
    love.graphics.setColor(0.22, 0.22, 0.28)
    love.graphics.circle("fill", x, y, r)
    if self.super then -- powder keg: gold bands
        love.graphics.setColor(1, 0.75, 0.2)
        love.graphics.setLineWidth(3)
        love.graphics.line(x - r * 0.9, y - r * 0.35, x + r * 0.9, y - r * 0.35)
        love.graphics.line(x - r * 0.9, y + r * 0.35, x + r * 0.9, y + r * 0.35)
        love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.circle("fill", x - r * 0.35, y - r * 0.35, r * 0.28)
    local fx, fy = x + math.cos(spin) * r, y + math.sin(spin) * r
    love.graphics.setColor(0.6, 0.45, 0.25)
    love.graphics.setLineWidth(2)
    love.graphics.line(x + math.cos(spin) * r * 0.7, y + math.sin(spin) * r * 0.7, fx, fy)
    love.graphics.setLineWidth(1)
    love.graphics.setBlendMode("add")
    local flicker = 0.6 + 0.4 * math.sin(love.timer.getTime() * 40)
    love.graphics.setColor(1, 0.7, 0.2, flicker)
    love.graphics.circle("fill", fx, fy, 3 + 2 * flicker)
    love.graphics.setBlendMode("alpha")
end

function Bullet:draw()
    if self.lob then return self:drawBomb() end
    local r, c = self.radius or Bullet.radius, self.color
    if self.super then -- glowing trail + halo
        love.graphics.setBlendMode("add")
        local len = math.sqrt(self.vx * self.vx + self.vy * self.vy)
        local tx, ty = -self.vx / len, -self.vy / len
        for i = 1, 4 do
            love.graphics.setColor(1, 0.85, 0.3, 0.25 - i * 0.05)
            love.graphics.circle("fill", self.x + tx * r * i * 0.9, self.y + ty * r * i * 0.9, r * (1.3 - i * 0.15))
        end
        love.graphics.setColor(1, 0.9, 0.4, 0.35)
        love.graphics.circle("fill", self.x, self.y, r * 1.8)
        love.graphics.setBlendMode("alpha")
    end
    local trail = not self.super and Cosmetics.get(self.trail, "trail")
    if trail then
        c = trail.color
        Bullet.drawTrail(self, trail, r)
    end
    love.graphics.setColor(0.1, 0.1, 0.1, 1)
    love.graphics.circle("fill", self.x, self.y, r + 2)
    love.graphics.setColor(c[1], c[2], c[3], 1)
    love.graphics.circle("fill", self.x, self.y, r)
    if self.super then
        love.graphics.setColor(1, 1, 0.85, 1)
        love.graphics.circle("fill", self.x, self.y, r * 0.45)
    end
end

-- What a bullet with a trail cosmetic leaves behind (style: see src/cosmetics.lua)
function Bullet.drawTrail(b, trail, r)
    local len = math.sqrt(b.vx * b.vx + b.vy * b.vy)
    if len < 1 then return end
    local tx, ty = -b.vx / len, -b.vy / len
    local c = trail.color
    local t = love.timer.getTime()
    if trail.style == "leaf" then -- little leaves tumbling behind it
        for i = 1, 4 do
            local d = r + i * 8
            local side = (i % 2 == 0 and 1 or -1) * 4
            local x, y = b.x + tx * d - ty * side, b.y + ty * d + tx * side
            love.graphics.push()
            love.graphics.translate(x, y)
            love.graphics.rotate(t * 9 + i * 1.7 + b.x * 0.01)
            love.graphics.setColor(0.1, 0.25, 0.05, 0.6 - i * 0.12)
            love.graphics.ellipse("fill", 0, 0, 5.5, 3)
            love.graphics.setColor(c[1], c[2], c[3], 0.95 - i * 0.18)
            love.graphics.ellipse("fill", 0, 0, 4.5, 2.2)
            love.graphics.pop()
        end
    elseif trail.style == "bubble" then
        for i = 1, 4 do
            love.graphics.setColor(c[1], c[2], c[3], 0.7 - i * 0.15)
            love.graphics.circle("line", b.x + tx * (r + i * 9), b.y + ty * (r + i * 9), 2 + i * 0.8)
        end
    else -- spark: a glowing streak
        love.graphics.setBlendMode("add")
        for i = 1, 5 do
            love.graphics.setColor(c[1], c[2], c[3], 0.4 - i * 0.07)
            love.graphics.circle("fill", b.x + tx * r * i * 0.9, b.y + ty * r * i * 0.9, r * (1.1 - i * 0.12))
        end
        love.graphics.setBlendMode("alpha")
    end
end

return Bullet
