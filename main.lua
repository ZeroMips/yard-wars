-- Client side: menu, input, fixed-step loop, camera, effects and HUD.
-- The game itself (rowdies, bullets, hits, scores, waves) lives in src/world.lua.
local Assets   = require("src.assets")
local Arena    = require("src.arena")
local Camera   = require("src.camera")
local Controls = require("src.controls")
local Rowdies = require("src.rowdies")
local World    = require("src.world")
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

local MAX_STEPS = 5 -- simulation steps per frame at most (after a hitch: slow down instead)

local state = "menu" -- "menu" or "game"
local mode           -- entry of MODES while playing
local menuTime = 0   -- drives the camera pan behind the menu
local menuFonts

local world
local localId        -- id of the player on this device
local player         -- world:get(localId), refreshed every frame
local accumulator = 0
local pendingFire    -- a shot requested since the last simulation step
local rowdyIndex = 1
local input -- last controls reading
local hudFont

-- HUD is laid out for a 720px screen (short side) and scaled on bigger/denser screens
local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end

local function selectRowdy(i)
    rowdyIndex = ((i - 1) % #Rowdies) + 1
    local def = Rowdies[rowdyIndex]
    world:setRowdy(player, def)
    Controls.switchLabel = "Rowdy: " .. def.name
end

local function newGame(m)
    mode, state = m, "game"
    accumulator, pendingFire, input = 0, nil, nil
    Effects.clear()
    Controls.reset()

    world = World.new(mode)
    player = world:addPlayer(Rowdies[rowdyIndex], Arena.spawn.x, Arena.spawn.y)
    localId = player.id
    selectRowdy(rowdyIndex)
    world:start()
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

local function hidden(e) return world:isHiddenFrom(e, player) end

-- Turn simulation events into particles and screen shake
local function playEvents(events)
    for _, ev in ipairs(events) do
        if ev.kind == "spawn" then
            Effects.ring(ev.x, ev.y, 45, { 1, 1, 1 })
        elseif ev.kind == "death" then
            Effects.burst(ev.x, ev.y, ev.color, 16)
            Effects.ring(ev.x, ev.y, 55, ev.color)
        elseif ev.kind == "step" then
            Effects.puff(ev.x, ev.y)
        elseif ev.kind == "impact" then
            Effects.sparks(ev.x, ev.y, 4, ev.color, 140) -- bullet hit a wall / crate
        elseif ev.kind == "hit" then
            Effects.sparks(ev.x, ev.y, 7, { 1, 0.45, 0.3 }, 200)
            if ev.victim == localId then Camera.shake(5) end
        end
    end
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

    -- Read the controls every frame; a shot is kept until a simulation step uses it
    input = Controls.get(player, world:nearestOpponent(player, true))
    if input.fire then pendingFire = true end

    -- Fixed-step simulation
    accumulator = math.min(accumulator + dt, World.TICK * MAX_STEPS)
    while accumulator >= World.TICK do
        accumulator = accumulator - World.TICK
        local cmd = { dx = input.dx, dy = input.dy, aim = input.aim, fire = pendingFire }
        pendingFire = nil
        world:update(World.TICK, { [localId] = cmd })
        playEvents(world:takeEvents())
    end
    player = world:get(localId)

    Effects.update(dt)
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
    for _, e in ipairs(world.entities) do
        if e ~= player and world:isOpponent(e, player) and not e.dead and not hidden(e) then
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
    for _, b in ipairs(world.bullets) do b:draw() end
    for _, e in ipairs(world.entities) do
        if e ~= player and not hidden(e) then e:draw() end
    end
    player:draw() -- own rowdy on top
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
    love.graphics.printf("You " .. player.kills .. " : " .. player.deaths .. " Bot",
        0, 10, sw, "center")
    if mode.waves then
        love.graphics.printf("Wave " .. world.wave .. "   Bots left: " .. world:countBots(),
            0, 32, sw, "center")
    end
    if player.dead then
        love.graphics.printf(string.format("You were defeated - respawn in %.1f",
            player.respawnTimer), 0, 60, sw, "center")
    elseif mode.waves and world:countBots() == 0 then
        love.graphics.printf(string.format("Wave cleared! %d bots incoming in %.1f",
            math.min(world.waveSize + 1, World.MAX_BOTS), math.max(0, world.waveTimer)),
            0, 60, sw, "center")
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
        world:restyle()
        return
    end
    local n = tonumber(key)
    if n and Rowdies[n] then selectRowdy(n) end
end
