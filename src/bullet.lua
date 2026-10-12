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

-- attack: the parameters of this shot (owner.attack or owner.super, see
-- src/rowdies.lua).
-- dist: how far a bomb (attack.lob) flies, clamped to MIN_THROW..range (nil = range)
function Bullet.new(x, y, angle, owner, attack, dist)
    local super = attack == owner.super
    local speed = attack.bulletSpeed or Bullet.speed
    local range = attack.range or Bullet.range
    if attack.lob then -- flies `dist`, then explodes (src/world.lua)
        range = math.max(Bullet.MIN_THROW, math.min(range, tonumber(dist) or range))
    end
    return setmetatable({
        x = x, y = y,
        homeX = x, homeY = y, -- a boomerang flies back here
        vx = math.cos(angle) * speed,
        vy = math.sin(angle) * speed,
        life = range / speed,
        owner = owner,
        team = owner.team, -- only hits rowdies of other teams
        damage = attack.damage,
        radius = attack.radius or Bullet.radius,
        -- size against walls/crates (default: radius); smaller lets a big ball graze them
        wallRadius = attack.wallRadius,
        -- flies through rowdies (hits each one once; a boomerang once per leg)
        pierce = attack.pierce or attack.boomerang,
        boomerang = attack.boomerang, -- turns after `range` (src/world.lua)
        lob = attack.lob,       -- a bomb: over everything, explodes when life runs out
        -- explosion radius: a bomb's where it lands, any other shot's where it stops
        -- (hits a rowdy, a wall or a chest, or its range is flown: a firework rocket)
        blast = attack.blast,
        freeze = attack.freeze, -- seconds a rowdy it hits can't move or attack
        hold = attack.hold,     -- seconds a rowdy it hits can't walk (handcuffs)
        goo = attack.goo,       -- extra damage the rowdy it hits takes over GOO_TIME
        chargeHit = attack.chargeHit, -- super charge per hit (an attack without damage)
        pull = attack.pull,     -- the rowdy it hits flies to the shooter
        projectile = attack.projectile, -- how it is drawn (see Bullet:draw)
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

-- Projectiles with their own look (src/rowdies.lua: projectile), drawn centred on
-- x, y; r = the bullet radius; spin = turning angle; dir = flight direction
local ITEMS = {}

function ITEMS.pen(b, x, y, r, spin, dir) -- a ballpoint pen, tip first
    local c = b.color or { 0.25, 0.45, 1 }
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(dir)
    love.graphics.setColor(0.1, 0.1, 0.15)
    love.graphics.rectangle("fill", -15, -4.5, 26, 9, 3, 3)
    love.graphics.polygon("fill", 10, -4.5, 19, 0, 10, 4.5)
    love.graphics.setColor(c[1], c[2], c[3])
    love.graphics.rectangle("fill", -13, -2.5, 23, 5, 2, 2)
    love.graphics.setColor(0.95, 0.95, 0.9)
    love.graphics.polygon("fill", 11, -2.5, 16, 0, 11, 2.5)
    love.graphics.setColor(0.85, 0.85, 0.9) -- the clip
    love.graphics.rectangle("fill", -12, -3.5, 8, 2)
    love.graphics.pop()
end

function ITEMS.pan(b, x, y, r, spin) -- a frying pan, spinning
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(spin)
    love.graphics.setColor(0.08, 0.08, 0.1)
    love.graphics.rectangle("fill", r - 2, -4, r + 6, 8, 3, 3)
    love.graphics.circle("fill", 0, 0, r + 2)
    love.graphics.setColor(0.55, 0.32, 0.15) -- wooden handle
    love.graphics.rectangle("fill", r + 1, -2.5, r + 2, 5, 2, 2)
    love.graphics.setColor(0.35, 0.36, 0.4)
    love.graphics.circle("fill", 0, 0, r)
    love.graphics.setColor(0.2, 0.2, 0.24)
    love.graphics.circle("fill", 0, 0, r * 0.72)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.circle("fill", -r * 0.3, -r * 0.3, r * 0.22)
    love.graphics.pop()
end

function ITEMS.waffle(b, x, y, r, spin) -- a golden waffle iron, spinning
    local h = r * 0.95
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(spin * 0.5)
    love.graphics.setColor(0.25, 0.14, 0.05)
    love.graphics.rectangle("fill", -h - 2, -h - 2, 2 * h + 4, 2 * h + 4, 6, 6)
    love.graphics.setColor(0.95, 0.72, 0.3)
    love.graphics.rectangle("fill", -h, -h, 2 * h, 2 * h, 5, 5)
    love.graphics.setColor(0.7, 0.45, 0.15)
    love.graphics.setLineWidth(2)
    for i = -1, 1 do -- the grid
        love.graphics.line(i * h * 0.5, -h + 3, i * h * 0.5, h - 3)
        love.graphics.line(-h + 3, i * h * 0.5, h - 3, i * h * 0.5)
    end
    love.graphics.setLineWidth(1)
    love.graphics.pop()
end

function ITEMS.book(b, x, y, r, spin) -- a thick red book, tumbling
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(spin * 0.6)
    local w, h = r * 1.3, r
    love.graphics.setColor(0.15, 0.05, 0.05)
    love.graphics.rectangle("fill", -w - 2, -h - 2, 2 * w + 4, 2 * h + 4, 3, 3)
    love.graphics.setColor(0.8, 0.2, 0.2)
    love.graphics.rectangle("fill", -w, -h, 2 * w, 2 * h, 2, 2)
    love.graphics.setColor(0.97, 0.95, 0.85) -- the pages
    love.graphics.rectangle("fill", -w + 3, h - 5, 2 * w - 6, 4)
    love.graphics.setColor(1, 0.85, 0.3) -- a gold title
    love.graphics.rectangle("fill", -w * 0.5, -h * 0.4, w, 3)
    love.graphics.pop()
end

function ITEMS.snowball(b, x, y, r) -- an icy ball with a sparkle
    love.graphics.setColor(0.25, 0.45, 0.6)
    love.graphics.circle("fill", x, y, r + 2)
    love.graphics.setColor(0.85, 0.95, 1)
    love.graphics.circle("fill", x, y, r)
    love.graphics.setColor(0.6, 0.85, 1)
    love.graphics.circle("fill", x + r * 0.25, y + r * 0.25, r * 0.55)
    love.graphics.setColor(1, 1, 1)
    love.graphics.circle("fill", x - r * 0.35, y - r * 0.35, r * 0.25)
    local s = 3 + 2 * math.sin(love.timer.getTime() * 12)
    love.graphics.line(x + r - s, y - r, x + r + s, y - r)
    love.graphics.line(x + r, y - r - s, x + r, y - r + s)
end

function ITEMS.potion(b, x, y, r, spin) -- a round flask of green slime
    r = math.max(r, 8)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(spin * 0.7)
    love.graphics.setColor(0.1, 0.15, 0.1)
    love.graphics.rectangle("fill", -4, -r - 7, 8, 9, 2, 2)
    love.graphics.circle("fill", 0, 0, r + 2)
    love.graphics.setColor(0.75, 0.55, 0.35) -- cork
    love.graphics.rectangle("fill", -2.5, -r - 6, 5, 6, 1, 1)
    love.graphics.setColor(0.85, 0.95, 1, 0.9) -- glass
    love.graphics.circle("fill", 0, 0, r)
    love.graphics.setColor(0.4, 0.95, 0.25) -- slime
    love.graphics.arc("fill", "pie", 0, 0, r - 1, 0.1, math.pi - 0.1, 16)
    love.graphics.circle("fill", -r * 0.3, r * 0.1, r * 0.25)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.circle("fill", -r * 0.4, -r * 0.4, r * 0.2)
    love.graphics.pop()
end

function ITEMS.magnet(b, x, y, r, spin, dir) -- a red horseshoe magnet, open end first
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(dir)
    love.graphics.setLineWidth(r * 0.9 + 3)
    love.graphics.setColor(0.15, 0.05, 0.05)
    love.graphics.arc("line", "open", 0, 0, r, math.pi / 2, math.pi * 1.5, 16)
    love.graphics.setLineWidth(r * 0.9)
    love.graphics.setColor(0.9, 0.15, 0.15)
    love.graphics.arc("line", "open", 0, 0, r, math.pi / 2, math.pi * 1.5, 16)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(0.85, 0.85, 0.9) -- silver tips
    love.graphics.rectangle("fill", 0, -r - r * 0.45, r * 0.7, r * 0.9)
    love.graphics.rectangle("fill", 0, r - r * 0.45, r * 0.7, r * 0.9)
    love.graphics.pop()
end

function ITEMS.glove(b, x, y, r, spin, dir) -- a big red boxing glove
    local g = r * 0.7
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(dir)
    love.graphics.setColor(0.25, 0.05, 0.05)
    love.graphics.circle("fill", 0, 0, g + 2)
    love.graphics.rectangle("fill", -g - 8, -g * 0.6 - 2, 12, g * 1.2 + 4, 3, 3)
    love.graphics.setColor(0.95, 0.95, 0.9) -- cuff
    love.graphics.rectangle("fill", -g - 6, -g * 0.6, 9, g * 1.2, 2, 2)
    love.graphics.setColor(0.9, 0.15, 0.15)
    love.graphics.circle("fill", 0, 0, g)
    love.graphics.setColor(1, 1, 1, 0.45)
    love.graphics.circle("fill", g * 0.3, -g * 0.35, g * 0.3)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 0.7) -- speed lines
    for i = -1, 1 do
        local c, s = math.cos(dir), math.sin(dir)
        local ox, oy = -s * i * g * 0.6, c * i * g * 0.6
        love.graphics.line(x - c * (g + 8) + ox, y - s * (g + 8) + oy, x - c * (g + 20) + ox, y - s * (g + 20) + oy)
    end
end

function ITEMS.swing(b, x, y, r, spin, dir) -- a shovel swing: a swoosh and the blade
    love.graphics.setLineWidth(5)
    love.graphics.setColor(1, 1, 1, 0.55)
    love.graphics.arc("line", "open", x - math.cos(dir) * r, y - math.sin(dir) * r, r * 1.3,
        dir - 1.1, dir + 1.1, 14)
    love.graphics.setLineWidth(1)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(dir)
    love.graphics.setColor(0.15, 0.15, 0.18)
    love.graphics.polygon("fill", -9, -9, 7, -8, 12, 0, 7, 8, -9, 9)
    love.graphics.setColor(0.7, 0.72, 0.78)
    love.graphics.polygon("fill", -7, -7, 6, -6, 9, 0, 6, 6, -7, 7)
    love.graphics.setColor(0.55, 0.35, 0.18)
    love.graphics.rectangle("fill", -22, -2.5, 15, 5, 2, 2)
    love.graphics.pop()
end

function ITEMS.apple(b, x, y, r, spin) -- a shiny red apple with a leaf, spinning
    r = math.max(r, 8)
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(spin * 0.6)
    love.graphics.setColor(0.3, 0.05, 0.05)
    love.graphics.circle("fill", 0, 0, r + 2)
    love.graphics.setColor(0.9, 0.15, 0.15)
    love.graphics.circle("fill", 0, 0, r)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.circle("fill", -r * 0.35, -r * 0.35, r * 0.25)
    love.graphics.setColor(0.4, 0.25, 0.1)
    love.graphics.rectangle("fill", -1, -r - 4, 2.5, 6)
    love.graphics.setColor(0.3, 0.75, 0.2)
    love.graphics.ellipse("fill", 4, -r - 2, 4, 2)
    love.graphics.pop()
end

function ITEMS.stone(b, x, y, r, spin) -- a grey pebble from a slingshot
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(spin * 0.4)
    love.graphics.setColor(0.15, 0.15, 0.17)
    love.graphics.ellipse("fill", 0, 0, r + 2, r * 0.8 + 2)
    love.graphics.setColor(0.6, 0.6, 0.62)
    love.graphics.ellipse("fill", 0, 0, r, r * 0.8)
    love.graphics.setColor(0.8, 0.8, 0.82)
    love.graphics.circle("fill", -r * 0.3, -r * 0.25, r * 0.3)
    love.graphics.pop()
end

function ITEMS.goo(b, x, y, r, spin) -- a wobbly blob of green goo
    local w = 1 + 0.15 * math.sin(spin * 2 + x * 0.05)
    love.graphics.setColor(0.15, 0.35, 0.05)
    love.graphics.ellipse("fill", x, y, (r + 2) * w, (r + 2) / w)
    love.graphics.setColor(0.5, 0.95, 0.2)
    love.graphics.ellipse("fill", x, y, r * w, r / w)
    love.graphics.setColor(0.85, 1, 0.6)
    love.graphics.circle("fill", x - r * 0.3, y - r * 0.3, r * 0.3)
end

function ITEMS.rocket(b, x, y, r, spin, dir) -- a striped paper firework rocket, sparks behind
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(dir)
    love.graphics.setBlendMode("add")
    local t = love.timer.getTime()
    for i = 1, 5 do -- sparkling tail
        love.graphics.setColor(1, 0.7 + 0.06 * i, 0.2, 0.5 - i * 0.08)
        love.graphics.circle("fill", -16 - i * 6 + math.sin(t * 40 + i) * 2, math.cos(t * 33 + i) * 3, 4 - i * 0.5)
    end
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(0.1, 0.1, 0.15)
    love.graphics.rectangle("fill", -16, -6, 24, 12, 2, 2)
    love.graphics.polygon("fill", 7, -6, 18, 0, 7, 6)
    love.graphics.setColor(0.2, 0.5, 1)
    love.graphics.rectangle("fill", -14, -4, 21, 8)
    love.graphics.setColor(1, 0.9, 0.3) -- stripes
    love.graphics.rectangle("fill", -10, -4, 4, 8)
    love.graphics.rectangle("fill", -1, -4, 4, 8)
    love.graphics.setColor(1, 0.3, 0.35)
    love.graphics.polygon("fill", 8, -4, 15, 0, 8, 4)
    love.graphics.pop()
end

function ITEMS.cuffs(b, x, y, r, spin) -- toy handcuffs: two silver rings, spinning
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(spin * 0.8)
    for _, side in ipairs({ -1, 1 }) do
        love.graphics.setLineWidth(5)
        love.graphics.setColor(0.15, 0.15, 0.2)
        love.graphics.circle("line", side * 7, 0, 6)
        love.graphics.setLineWidth(3)
        love.graphics.setColor(0.85, 0.87, 0.92)
        love.graphics.circle("line", side * 7, 0, 6)
    end
    love.graphics.setColor(0.6, 0.62, 0.7)
    love.graphics.rectangle("fill", -2, -1.5, 4, 3)
    love.graphics.setLineWidth(1)
    love.graphics.pop()
end

-- A bomb in flight: a shadow on the ground where it is, the bomb above it on an arc
-- (highest in the middle of the flight), with a sparking fuse (other thrown things:
-- their ITEMS look instead of the bomb)
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
    local item = ITEMS[self.projectile]
    if item then
        item(self, x, y, r, spin, math.atan2(self.vy, self.vx))
        return
    end
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
    local item = ITEMS[self.projectile]
    if item then
        item(self, self.x, self.y, r, love.timer.getTime() * 14, math.atan2(self.vy, self.vx))
        return
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
