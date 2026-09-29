local Assets   = require("src.assets")
local Arena    = require("src.arena")
local Camera   = require("src.camera")
local Controls = require("src.controls")
local Rowdies = require("src.rowdies")
local Player   = require("src.player")
local Enemy    = require("src.enemy")
local Bullet   = require("src.bullet")
local Effects  = require("src.effects")

local player, enemy
local bullets = {}
local kills, deaths = 0, 0
local rowdyIndex = 1
local input -- last controls reading
local hudFont

local HIDE_REVEAL = 150 -- enemy in a bush is only visible this close

-- HUD is laid out for a 720px screen (short side) and scaled on bigger/denser screens
local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end

local function selectRowdy(i)
    rowdyIndex = ((i - 1) % #Rowdies) + 1
    local def = Rowdies[rowdyIndex]
    player:setRowdy(Assets.look(def.character, def.weapon), def.stats)
    Controls.switchLabel = "Rowdy: " .. def.name
end

function love.load()
    love.graphics.setBackgroundColor(0.05, 0.15, 0.08)
    Assets.load()
    local def = Rowdies[rowdyIndex]
    player = Player.new(Arena.spawn.x, Arena.spawn.y,
        Assets.look(def.character, def.weapon), def.stats)
    enemy = Enemy.new(Arena.enemySpawn.x, Arena.enemySpawn.y, Assets.look("robot1", "machine"))
    Camera.snap(player.x, player.y, Arena.width, Arena.height)
    love.resize()
    selectRowdy(rowdyIndex)
end

function love.resize()
    hudFont = love.graphics.newFont(16, "normal", math.max(1, uiScale()))
    Controls.font = hudFont
end

local function enemyHidden()
    if enemy.dead or not Arena.inBush(enemy.x, enemy.y) then return false end
    local dx, dy = enemy.x - player.x, enemy.y - player.y
    return dx * dx + dy * dy > HIDE_REVEAL * HIDE_REVEAL
end

function love.update(dt)
    if Controls.switchRequested then
        Controls.switchRequested = false
        selectRowdy(rowdyIndex + 1)
    end

    -- Tap auto-aim only targets an enemy the player can actually see
    local target = (not enemy.dead and not enemyHidden()) and enemy or nil
    input = Controls.get(player, target)
    player:update(dt, input, bullets)
    enemy:update(dt, player, bullets)
    Effects.update(dt)

    for i = #bullets, 1, -1 do
        local b = bullets[i]
        -- Move in small sub-steps so fast bullets can't skip through targets
        local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
        local steps = math.max(1, math.ceil(speed * dt / 10))
        local remove = false

        for _ = 1, steps do
            b:update(dt / steps)
            if Arena.hitsSolid(b.x, b.y, Bullet.radius) then
                Effects.sparks(b.x, b.y, 4, b.color, 140) -- impact on wall / crate
                remove = true
                break
            elseif b.life <= 0 then
                remove = true
                break
            end
            local victim = (b.owner == player) and enemy or player
            if not victim.dead then
                local dx, dy = victim.x - b.x, victim.y - b.y
                local r = victim.radius + Bullet.radius
                if dx * dx + dy * dy < r * r then
                    remove = true
                    Effects.sparks(b.x, b.y, 7, { 1, 0.45, 0.3 }, 200)
                    if victim == player then Camera.shake(5) end
                    if victim:takeDamage(b.damage) then
                        if victim == enemy then kills = kills + 1
                        else deaths = deaths + 1 end
                    end
                    break
                end
            end
        end

        if remove then table.remove(bullets, i) end
    end

    Camera.update(dt, player.x, player.y, Arena.width, Arena.height)
end

local function drawMinimap(screenW)
    local mw = 200
    local s = mw / Arena.width
    local mh = Arena.height * s
    local x0, y0 = screenW - mw - 12, 12
    local T = 64 * s

    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", x0 - 3, y0 - 3, mw + 6, mh + 6, 4, 4)
    love.graphics.setColor(0.2, 0.55, 0.3, 0.95)
    love.graphics.rectangle("fill", x0, y0, mw, mh)
    love.graphics.setColor(0.1, 0.35, 0.18, 0.95)
    for _, b in ipairs(Arena.bushes) do
        love.graphics.rectangle("fill", x0 + b.x * T, y0 + b.y * T, b.w * T, b.h * T)
    end
    love.graphics.setColor(0.25, 0.25, 0.28, 1)
    for _, w in ipairs(Arena.walls) do
        love.graphics.rectangle("fill", x0 + w.x * T, y0 + w.y * T, w.w * T, w.h * T)
    end
    if not enemy.dead and not enemyHidden() then
        love.graphics.setColor(0.95, 0.25, 0.25, 1)
        love.graphics.circle("fill", x0 + enemy.x * s, y0 + enemy.y * s, 3.5)
    end
    if not player.dead then
        love.graphics.setColor(0.3, 0.7, 1, 1)
        love.graphics.circle("fill", x0 + player.x * s, y0 + player.y * s, 3.5)
    end
end

function love.draw()
    -- World (moves with the camera)
    Camera.attach()
    Arena.drawBelow()
    if input and input.aiming and not player.dead then player:drawAim() end
    Effects.drawBelow()
    for _, b in ipairs(bullets) do b:draw() end
    if not enemyHidden() then enemy:draw() end
    player:draw()
    Effects.drawAbove()
    Arena.drawBushes(player)
    Camera.detach()

    -- Virtual sticks + switch button (touch only)
    Controls.draw()

    -- HUD (fixed on screen, scaled)
    local ui = uiScale()
    local sw = love.graphics.getWidth() / ui
    love.graphics.push()
    love.graphics.scale(ui)
    love.graphics.setFont(hudFont)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("FPS: " .. love.timer.getFPS() ..
        (Controls.touchMode and "" or
            ("   [1-" .. #Rowdies .. "] " .. Rowdies[rowdyIndex].name)), 10, 10)
    love.graphics.printf("You " .. kills .. " : " .. deaths .. " Bot",
        0, 10, sw, "center")
    if player.dead then
        love.graphics.printf(string.format("You were defeated - respawn in %.1f",
            player.respawnTimer), 0, 60, sw, "center")
    end
    drawMinimap(sw)
    love.graphics.pop()
end

-- Touch input (Android/iOS)
function love.touchpressed(id, x, y)  Controls.touchpressed(id, x, y) end
function love.touchmoved(id, x, y)    Controls.touchmoved(id, x, y) end
function love.touchreleased(id, x, y) Controls.touchreleased(id, x, y) end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
    local n = tonumber(key)
    if n and Rowdies[n] then selectRowdy(n) end
end
