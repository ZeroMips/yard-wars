local Assets   = require("src.assets")
local Arena    = require("src.arena")
local Camera   = require("src.camera")
local Controls = require("src.controls")
local Rowdies = require("src.rowdies")
local Player   = require("src.player")
local Enemy    = require("src.enemy")
local Bullet   = require("src.bullet")
local Effects  = require("src.effects")
local Menu     = require("src.menu")

-- Game modes shown on the start screen.
--   waves = false: the bots respawn after dying (endless duel)
--   waves = true : killed bots stay dead; clearing a wave starts a bigger one
local MODES = {
    { name = "Duel",  description = "1 vs 1 against a bot that keeps respawning",
      waves = false },
    { name = "Waves", description = "Survive waves - every wave brings one more bot",
      waves = true },
}

local state = "menu" -- "menu" or "game"
local mode           -- entry of MODES while playing
local menuTime = 0   -- drives the camera pan behind the menu
local menuFonts

local player
local enemies = {}
local bullets = {}
local kills, deaths = 0, 0
local wave, waveSize = 0, 0
local waveTimer = 0 -- countdown to the next wave once all bots are dead
local rowdyIndex = 1
local input -- last controls reading
local hudFont

local HIDE_REVEAL    = 150 -- enemy in a bush is only visible this close
local WAVE_DELAY     = 2   -- seconds between clearing a wave and the next one
local MAX_ENEMIES    = 64  -- safety cap for the wave size
local SPAWN_MIN_DIST = 600 -- bots never spawn closer than this to the player

-- HUD is laid out for a 720px screen (short side) and scaled on bigger/denser screens
local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end

local function selectRowdy(i)
    rowdyIndex = ((i - 1) % #Rowdies) + 1
    local def = Rowdies[rowdyIndex]
    player:setRowdy(Assets.look(def.character, def.weapon, def.comic), def.stats)
    Controls.switchLabel = "Rowdy: " .. def.name
end

local function farFromPlayer(x, y)
    local dx, dy = x - player.x, y - player.y
    return dx * dx + dy * dy >= SPAWN_MIN_DIST * SPAWN_MIN_DIST
end

-- The first bot uses the regular enemy spawn, the rest a random free spot.
-- Either way it has to be far enough from the player.
local function enemySpawnPoint(i)
    local sx, sy = Arena.enemySpawn.x, Arena.enemySpawn.y
    if i == 1 and farFromPlayer(sx, sy) then return sx, sy end
    for _ = 1, 20 do
        local x, y = Arena.randomOpenPoint()
        if farFromPlayer(x, y) then return x, y end
    end
    return sx, sy
end

local function botLook()
    local bot = Rowdies.bot
    return Assets.look(bot.character, bot.weapon, bot.comic)
end

local function spawnBots(count)
    for i = 1, count do
        local x, y = enemySpawnPoint(i)
        local e = Enemy.new(x, y, botLook())
        e:respawn() -- pop-in animation + spawn ring
        enemies[#enemies + 1] = e
    end
end

-- Every wave has one bot more than the one before.
local function startWave()
    wave = wave + 1
    waveSize = math.min(waveSize + 1, MAX_ENEMIES)
    spawnBots(waveSize)
end

local function newGame(m)
    mode, state = m, "game"
    enemies, bullets = {}, {}
    kills, deaths = 0, 0
    wave, waveSize, waveTimer = 0, 0, 0
    Effects.clear()
    Controls.reset()

    local def = Rowdies[rowdyIndex]
    player = Player.new(Arena.spawn.x, Arena.spawn.y,
        Assets.look(def.character, def.weapon, def.comic), def.stats)
    selectRowdy(rowdyIndex)
    if mode.waves then startWave() else spawnBots(1) end
    Camera.snap(player.x, player.y, Arena.width, Arena.height)
end

local function openMenu()
    state = "menu"
    Controls.reset()
end

function love.load()
    love.graphics.setBackgroundColor(0.05, 0.15, 0.08)
    Assets.load()
    love.resize()
    openMenu()
end

function love.resize()
    local dpi = math.max(1, uiScale())
    hudFont = love.graphics.newFont(16, "normal", dpi)
    Controls.font = hudFont
    menuFonts = {
        title  = love.graphics.newFont(56, "normal", dpi),
        button = love.graphics.newFont(26, "normal", dpi),
        text   = hudFont,
    }
end

local function enemyHidden(enemy)
    if enemy.dead or not Arena.inBush(enemy.x, enemy.y) then return false end
    local dx, dy = enemy.x - player.x, enemy.y - player.y
    return dx * dx + dy * dy > HIDE_REVEAL * HIDE_REVEAL
end

-- Nearest enemy the player can actually see (for tap auto-aim)
local function nearestVisibleEnemy()
    local best, bestD2
    for _, e in ipairs(enemies) do
        if not e.dead and not enemyHidden(e) then
            local dx, dy = e.x - player.x, e.y - player.y
            local d2 = dx * dx + dy * dy
            if not bestD2 or d2 < bestD2 then best, bestD2 = e, d2 end
        end
    end
    return best
end

local function bulletHits(b, victim)
    if victim.dead then return false end
    local dx, dy = victim.x - b.x, victim.y - b.y
    local r = victim.radius + Bullet.radius
    return dx * dx + dy * dy < r * r
end

function love.update(dt)
    if state == "menu" then
        -- Slow pan over the arena behind the menu
        menuTime = menuTime + dt
        Camera.snap(Arena.width / 2 + math.sin(menuTime * 0.15) * Arena.width * 0.3,
            Arena.height / 2, Arena.width, Arena.height)
        return
    end

    if Controls.switchRequested then
        Controls.switchRequested = false
        selectRowdy(rowdyIndex + 1)
    end

    input = Controls.get(player, nearestVisibleEnemy())
    player:update(dt, input, bullets)
    for _, e in ipairs(enemies) do e:update(dt, player, bullets) end
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
            -- Player bullets hit any bot, bot bullets only the player
            local victim
            if b.owner == player then
                for _, e in ipairs(enemies) do
                    if bulletHits(b, e) then victim = e break end
                end
            elseif bulletHits(b, player) then
                victim = player
            end
            if victim then
                remove = true
                Effects.sparks(b.x, b.y, 7, { 1, 0.45, 0.3 }, 200)
                if victim == player then Camera.shake(5) end
                if victim:takeDamage(b.damage) then
                    if victim == player then deaths = deaths + 1
                    else kills = kills + 1 end
                end
                break
            end
        end

        if remove then table.remove(bullets, i) end
    end

    -- Waves: killed bots stay dead; once the wave is cleared the next one follows.
    -- (Otherwise dead bots stay in the list and respawn by themselves.)
    if mode.waves then
        for i = #enemies, 1, -1 do
            if enemies[i].dead then
                table.remove(enemies, i)
                if #enemies == 0 then waveTimer = WAVE_DELAY end
            end
        end
        if #enemies == 0 then
            waveTimer = waveTimer - dt
            if waveTimer <= 0 then startWave() end
        end
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
    love.graphics.setColor(0.95, 0.25, 0.25, 1)
    for _, e in ipairs(enemies) do
        if not e.dead and not enemyHidden(e) then
            love.graphics.circle("fill", x0 + e.x * s, y0 + e.y * s, 3.5)
        end
    end
    if not player.dead then
        love.graphics.setColor(0.3, 0.7, 1, 1)
        love.graphics.circle("fill", x0 + player.x * s, y0 + player.y * s, 3.5)
    end
end

function love.draw()
    if state == "menu" then
        Camera.attach()
        Arena.drawBelow()
        Arena.drawBushes(nil)
        Camera.detach()
        Menu.draw(MODES, menuFonts, Controls.touchMode)
        return
    end

    -- World (moves with the camera)
    Camera.attach()
    Arena.drawBelow()
    if input and input.aiming and not player.dead then player:drawAim() end
    Effects.drawBelow()
    for _, b in ipairs(bullets) do b:draw() end
    for _, e in ipairs(enemies) do
        if not enemyHidden(e) then e:draw() end
    end
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
    if mode.waves then
        love.graphics.printf("Wave " .. wave .. "   Bots left: " .. #enemies,
            0, 32, sw, "center")
    end
    if player.dead then
        love.graphics.printf(string.format("You were defeated - respawn in %.1f",
            player.respawnTimer), 0, 60, sw, "center")
    elseif mode.waves and #enemies == 0 then
        love.graphics.printf(string.format("Wave cleared! %d bots incoming in %.1f",
            math.min(waveSize + 1, MAX_ENEMIES), math.max(0, waveTimer)), 0, 60, sw, "center")
    end
    drawMinimap(sw)
    love.graphics.pop()
end

-- Menu: start the mode whose button was tapped/clicked
local function menuPress(x, y)
    local i = Menu.hit(MODES, x, y)
    if i then
        Menu.selected = i
        newGame(MODES[i])
    end
end

-- Touch input (Android/iOS)
function love.touchpressed(id, x, y)
    if state == "game" then Controls.touchpressed(id, x, y) end
end
function love.touchmoved(id, x, y)
    if state == "game" then Controls.touchmoved(id, x, y) end
end
function love.touchreleased(id, x, y)
    if state == "game" then Controls.touchreleased(id, x, y)
    else Controls.touchMode = true; menuPress(x, y) end
end

-- Mouse (touches also arrive here as emulated mouse events: skip those)
function love.mousereleased(x, y, button, istouch)
    if state == "menu" and button == 1 and not istouch then menuPress(x, y) end
end
function love.mousemoved(x, y, dx, dy, istouch)
    if state == "menu" and not istouch then
        Menu.selected = Menu.hit(MODES, x, y) or Menu.selected
    end
end

-- Escape (= Android back button): game -> menu, menu -> quit
function love.keypressed(key)
    if state == "menu" then
        if key == "escape" then love.event.quit() return end
        local i = Menu.keypressed(MODES, key)
        if i then newGame(MODES[i]) end
        return
    end
    if key == "escape" then openMenu() return end
    if key == "f2" then -- toggle art style: comic <-> Kenney (only the looks change)
        Assets.style = (Assets.style == "comic") and "kenney" or "comic"
        local hp, ammo = player.hp, player.ammo
        selectRowdy(rowdyIndex)
        player.hp, player.ammo = hp, ammo
        for _, e in ipairs(enemies) do e.look = botLook() end
        return
    end
    local n = tonumber(key)
    if n and Rowdies[n] then selectRowdy(n) end
end
