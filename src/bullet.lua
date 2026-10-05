local Cosmetics = require("src.cosmetics")

local Bullet = {}
Bullet.__index = Bullet

-- Defaults (a rowdy can override speed and range in its stats)
Bullet.radius = 6
Bullet.speed = 600
Bullet.life = 0.8
Bullet.range = Bullet.speed * Bullet.life -- 480px

-- attack: the parameters of this shot (rowdy stats or its super, see
-- src/rowdies.lua); defaults to the owner's normal attack.
function Bullet.new(x, y, angle, owner, attack)
    local super = attack ~= nil
    attack = attack or owner
    local speed = attack.bulletSpeed or Bullet.speed
    local range = attack.range or Bullet.range
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

function Bullet:draw()
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
