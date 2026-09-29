local Bullet = {}
Bullet.__index = Bullet

-- Defaults (a rowdy can override speed and range in its stats)
Bullet.radius = 6
Bullet.speed = 600
Bullet.life = 0.8
Bullet.range = Bullet.speed * Bullet.life -- 480px

function Bullet.new(x, y, angle, owner)
    local speed = owner.bulletSpeed or Bullet.speed
    local range = owner.range or Bullet.range
    return setmetatable({
        x = x, y = y,
        vx = math.cos(angle) * speed,
        vy = math.sin(angle) * speed,
        life = range / speed,
        owner = owner,
        damage = owner.damage,
        color = owner.bulletColor,
    }, Bullet)
end

function Bullet:update(dt)
    self.x = self.x + self.vx * dt
    self.y = self.y + self.vy * dt
    self.life = self.life - dt
end

function Bullet:draw()
    love.graphics.setColor(0.1, 0.1, 0.1, 1)
    love.graphics.circle("fill", self.x, self.y, Bullet.radius + 2)
    love.graphics.setColor(self.color[1], self.color[2], self.color[3], 1)
    love.graphics.circle("fill", self.x, self.y, Bullet.radius)
end

return Bullet
