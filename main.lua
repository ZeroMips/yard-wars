-- Client side: menu, input, fixed-step loop, camera, effects and HUD.
-- The game itself (rowdies, bullets, hits, scores, waves) lives in src/world.lua.
--
-- Roles while playing:
--   "local"  single player: this device runs the world
--   "host"   LAN game: this device runs the world + a Net server (src/net.lua)
--   "client" LAN game: the world is a copy rebuilt from the host (src/replica.lua)
local Assets   = require("src.assets")
local Arena    = require("src.arena")
local Camera   = require("src.camera")
local Controls = require("src.controls")
local Rowdies = require("src.rowdies")
local World    = require("src.world")
local Effects  = require("src.effects")
local Menu     = require("src.menu")
local Join     = require("src.join")
local Net      = require("src.net")
local Replica  = require("src.replica")
local Medpack  = require("src.medpack")
local Picker   = require("src.picker")
local Result   = require("src.result")

-- Game modes (round rules: see World.KILL_TARGET / TIME_LIMIT / LIVES).
--   waves = false: duel - the bots respawn; first to 10 kills or most kills after
--                  3 minutes wins (LAN: free-for-all)
--   waves = true : killed bots stay dead; clearing a wave starts a bigger one; 3 lives
--                  per player (LAN: co-op)
local MODES = {
    duel  = { name = "Duel",  waves = false },
    waves = { name = "Waves", waves = true },
}

-- Start screen buttons
local MENU = {
    { name = "Duel", description = "1 vs 1 against a bot - first to 10 kills",
      mode = MODES.duel },
    { name = "Waves", description = "Survive waves with 3 lives - each wave one more bot",
      mode = MODES.waves },
    { name = "Host LAN duel", description = "Free-for-all with friends in your Wi-Fi",
      mode = MODES.duel, host = true },
    { name = "Host LAN waves", description = "Survive waves together with friends",
      mode = MODES.waves, host = true },
    { name = "Join LAN game", description = "Play in a game hosted in your Wi-Fi",
      join = true },
}

local MAX_STEPS = 5 -- simulation steps per frame at most (after a hitch: slow down instead)
local OPPONENT_COLOR = { 1, 0.5, 0.15 } -- health bar of other players
local TEAMMATE_COLOR = { 0.3, 0.6, 1 }

local state = "menu" -- "menu", "pick" (rowdy choice), "join" or "game"
local pickFor        -- what the rowdy choice is for: a MENU entry, or "between" rounds
local role           -- "local", "host" or "client" while playing
local menuTime = 0   -- drives the camera pan behind the menu
local menuFonts

local world          -- World (local/host) or the replica's copy (client)
local localId        -- id of the player on this device
local player         -- the own rowdy, refreshed every frame (nil while joining)
local server, hostAddress -- host
local client, replica     -- client
local finder              -- looks for LAN games while the join screen is open
local accumulator = 0
local pendingFire    -- a shot requested since the last simulation step
local pendingSuper   -- same for the super attack
local rowdyIndex = 1
local input -- last controls reading
local hudFont

-- HUD is laid out for a 720px screen (short side) and scaled on bigger/denser screens
local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end

local function resetGame()
    accumulator, pendingFire, pendingSuper, input = 0, nil, nil, nil
    world, player, localId = nil, nil, nil
    Effects.clear()
    Controls.reset()
end

local function closeFinder()
    if finder then finder:close() end
    finder = nil
end

-- Back to the start screen (message: why, e.g. "Connection lost")
local function openMenu(message)
    if server then server:close() end
    if client then client:close() end
    closeFinder()
    server, client, replica = nil, nil, nil
    state, role = "menu", nil
    Menu.message = message
    Controls.reset()
end

-- Single player or LAN host: this device runs the world
local function newGame(mode, host)
    resetGame()
    world = World.new(mode)
    if host then
        local err
        server, err = Net.newServer(world)
        if not server then openMenu("Can't host: " .. err) return end
        hostAddress = Net.localAddress() or "(no network)"
    end
    state, role = "game", host and "host" or "local"
    Menu.message = nil
    player = world:addPlayer(Rowdies[rowdyIndex], Arena.spawn.x, Arena.spawn.y)
    localId = player.id
    world:start()
    Camera.snap(player.x, player.y, Arena.width, Arena.height)
end

local function openJoin()
    state = "join"
    Join.status = nil
    Join.games = {}
    Join.open()
    finder = Net.newFinder({ Join.address }) -- ask the last joined host first
end

-- address: a found game's address, or nil for the one typed in
local function joinGame(address)
    if address then Join.address = address end
    address = Join.address
    if address == "" then Join.status = "Enter the host's address" return end
    local err
    client, err = Net.newClient(address, rowdyIndex)
    if not client then Join.status = err return end
    Join.save()
    Join.close()
    closeFinder()
    resetGame()
    replica = Replica.new()
    state, role = "game", "client"
    Menu.message = nil
end

-- Rowdy choice before a game (forWhat = MENU entry) or between rounds ("between")
local function openPicker(forWhat)
    state, pickFor = "pick", forWhat
    Picker.selected = rowdyIndex
    if forWhat == "between" then
        Picker.confirmLabel = (role == "client") and "OK" or "Play"
    else
        Picker.confirmLabel = forWhat.join and "Next" or "Play"
    end
end

local function confirmPick()
    rowdyIndex = Picker.selected
    if pickFor == "between" then
        state = "game"
        if client then
            client:selectRowdy(rowdyIndex) -- the host switches us before its next round
        else
            world:setRowdy(player, Rowdies[rowdyIndex])
            world:restartMatch()
        end
    elseif pickFor.join then
        openJoin()
    else
        newGame(pickFor.mode, pickFor.host)
    end
end

local function cancelPick()
    if pickFor == "between" then state = "game" else state = "menu" end
end

local function startMenuEntry(i)
    Menu.selected = i
    openPicker(MENU[i])
end

-- Is the player steering their rowdy right now (not in a menu or between rounds)?
local function playing()
    return state == "game" and player ~= nil and not world.match.over
end

function love.load(args)
    love.graphics.setBackgroundColor(0.05, 0.15, 0.08)
    Assets.load()
    love.resize()
    openMenu()
    -- Testing shortcuts: love . [--rowdy N] --host [waves] | --join <address> | --find
    for i, a in ipairs(args or {}) do
        if a == "--rowdy" then rowdyIndex = Rowdies[tonumber(args[i + 1])] and tonumber(args[i + 1]) or 1 end
        if a == "--find" then openJoin() end
        if a == "--host" then
            newGame(args[i + 1] == "waves" and MODES.waves or MODES.duel, true)
        elseif a == "--join" and args[i + 1] then
            Join.address = args[i + 1]
            joinGame()
        end
    end
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
        elseif ev.kind == "super" then
            Effects.ring(ev.x, ev.y, 50, { 1, 0.82, 0.1 })
            Effects.sparks(ev.x, ev.y, 10, { 1, 0.85, 0.3 }, 260)
            if ev.id == localId then Camera.shake(4) end
        elseif ev.kind == "heal" then
            Effects.heal(ev.x, ev.y)
            Effects.ring(ev.x, ev.y, 40, { 0.4, 1, 0.4 })
        elseif ev.kind == "hit" then
            Effects.sparks(ev.x, ev.y, 7, { 1, 0.45, 0.3 }, 200)
            if ev.victim == localId then Camera.shake(5) end
        end
    end
end

local function readInput()
    if not playing() then -- menu / round over: stand still
        input = { dx = 0, dy = 0 }
        return
    end
    Controls.hasSuper = player.super ~= nil
    Controls.superCharge = player.charge or 0
    input = Controls.get(player, world:nearestOpponent(player, true))
end

-- Local / host: run the simulation in fixed steps
local function updateWorld(dt)
    if server then server:service() end
    readInput()
    if input.fire then pendingFire = true end -- kept until a step uses it
    if input.super then pendingSuper = true end

    accumulator = math.min(accumulator + dt, World.TICK * MAX_STEPS)
    while accumulator >= World.TICK do
        accumulator = accumulator - World.TICK
        local inputs = { [localId] = { dx = input.dx, dy = input.dy, aim = input.aim,
            fire = pendingFire, super = pendingSuper } }
        pendingFire, pendingSuper = nil, nil
        if server then server:addInputs(inputs) end
        world:update(World.TICK, inputs)
        local events = world:takeEvents()
        playEvents(events)
        if server then server:afterStep(events) end
    end
    player = world:get(localId)
end

-- Client: exchange messages with the host and rebuild the world copy
local function updateClient()
    client:service()
    if client.state == "closed" then openMenu(client.error) return end
    replica:receive(client:takeInbox())
    local due = replica:update()
    if not due then return end -- nothing received yet
    playEvents(due)
    world, localId, player = replica.world, replica.localId, replica:player()
    if not player then return end
    readInput()
    client:sendInput(input)
    -- Show the own aim right away (the host's answer takes a moment)
    if input.aim then player.aim = input.aim end
end

function love.update(dt)
    if state == "join" then
        if finder then
            finder:update(dt)
            Join.games = finder.games
            Join.searching = finder.network or "no network"
            Join.stats = finder:stats()
        else
            Join.searching = "search not available"
        end
    end
    -- The game keeps running while a rowdy is chosen between rounds (LAN!)
    local inGame = state == "game" or (state == "pick" and pickFor == "between")
    if not inGame then
        -- Slow pan over the arena behind the menu
        menuTime = menuTime + dt
        Camera.snap(Arena.width / 2 + math.sin(menuTime * 0.15) * Arena.width * 0.3,
            Arena.height / 2, Arena.width, Arena.height)
        return
    end

    if role == "client" then updateClient() else updateWorld(dt) end
    if state == "menu" then return end -- connection lost

    Effects.update(dt)
    if player then Camera.update(dt, player.x, player.y, Arena.width, Arena.height) end
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
    for _, e in ipairs(world.entities) do
        if e ~= player and not e.dead and not hidden(e) then
            if world:isOpponent(e, player) then love.graphics.setColor(0.95, 0.25, 0.25, 1)
            else love.graphics.setColor(TEAMMATE_COLOR) end
            love.graphics.circle("fill", x0 + e.x * s, y0 + e.y * s, 3.5)
        end
    end
    if not player.dead then
        love.graphics.setColor(0.3, 0.7, 1, 1)
        love.graphics.circle("fill", x0 + player.x * s, y0 + player.y * s, 3.5)
    end
end

-- Arena in the background + one centered line of text (while connecting)
local function drawWaiting(text)
    Camera.attach()
    Arena.drawBelow()
    Arena.drawBushes(nil)
    Camera.detach()
    local ui = uiScale()
    love.graphics.push()
    love.graphics.scale(ui)
    local sw, sh = love.graphics.getWidth() / ui, love.graphics.getHeight() / ui
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    love.graphics.setFont(menuFonts.button)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(text, 0, sh / 2 - 40, sw, "center")
    love.graphics.setFont(hudFont)
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.printf(Controls.touchMode and "Back to cancel" or "Esc to cancel",
        0, sh / 2 + 10, sw, "center")
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

local function formatTime(t)
    t = math.max(0, math.ceil(t or 0))
    return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

local function nameOf(e)
    if e.id == localId then return "You" end
    if e.isBot then return "Bot" end
    return "Player " .. e.id
end

-- What the end-of-round screen shows (src/result.lua)
local function resultInfo()
    local m = world.match
    local list = {}
    for _, e in ipairs(world.entities) do
        if not (world.mode.waves and e.isBot) then list[#list + 1] = e end
    end
    table.sort(list, function(a, b)
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.id < b.id
    end)
    local lines = {}
    for _, e in ipairs(list) do
        lines[#lines + 1] = { string.format("%s (%s)   %d kills   %d deaths", nameOf(e),
            e.def and e.def.name or "?", e.kills, e.deaths), e.id == localId }
    end

    local info = { lines = lines }
    if world.mode.waves then
        info.title, info.color = "Game over", { 1, 0.55, 0.3 }
        info.subtitle = "You reached wave " .. (m.wave or world.wave)
    else
        if not m.winner then
            info.title, info.color = "Draw", { 1, 1, 1 }
        elseif m.winner == localId then
            info.title, info.color = "Victory!", { 1, 0.82, 0.1 }
        else
            info.title, info.color = "Defeat", { 1, 0.35, 0.3 }
        end
        local winner = m.winner and world:get(m.winner)
        if m.timeLeft and m.timeLeft <= 0 then
            info.subtitle = "Time is up"
        elseif winner then
            info.subtitle = nameOf(winner) .. " reached " .. World.KILL_TARGET .. " kills"
        end
    end
    if role == "client" then
        info.buttons = { { "rowdy", "Rowdy" }, { "menu", "Leave" } }
        info.note = "Waiting for the host to start the next round"
    else
        info.buttons = { { "again", "Play again" }, { "rowdy", "Rowdy" }, { "menu", "Menu" } }
        if role == "host" then
            info.note = "Players who joined stay for the next round (" .. server:playerCount() .. ")"
        end
    end
    return info
end

local function resultAction(id)
    if id == "again" then
        world:restartMatch()
        Result.selected = 1
    elseif id == "rowdy" then
        openPicker("between")
    elseif id == "menu" then
        openMenu()
    end
end

local function drawHud()
    local ui = uiScale()
    local sw = love.graphics.getWidth() / ui
    love.graphics.push()
    love.graphics.scale(ui)
    love.graphics.setFont(hudFont)
    love.graphics.setColor(1, 1, 1)
    local superInfo = ""
    if player.super and not Controls.touchMode then
        superInfo = "   [RMB/E] " .. player.super.name .. ": " ..
            (player.charge >= 1 and "READY" or (math.floor(player.charge * 100) .. "%"))
    end
    love.graphics.print("FPS: " .. love.timer.getFPS() .. "   " ..
        (player.def and player.def.name or "") .. superInfo, 10, 10)
    if role == "host" then
        love.graphics.print("Hosting at " .. hostAddress .. "   players joined: " ..
            server:playerCount() .. "   searches answered: " .. (server.queries or 0) ..
            (server.lastQueryFrom and (" (last from " .. server.lastQueryFrom .. ")") or ""), 10, 32)
    elseif role == "client" then
        love.graphics.print("Ping: " .. client:ping() .. " ms", 10, 32)
    end
    if role == "local" then
        love.graphics.printf("You " .. player.kills .. " : " .. player.deaths .. " Bot",
            0, 10, sw, "center")
    else
        love.graphics.printf("Kills " .. player.kills .. "   Deaths " .. player.deaths,
            0, 10, sw, "center")
    end
    if world.mode.waves then
        love.graphics.printf("Wave " .. world.wave .. "   Bots left: " .. world:countBots() ..
            "   Lives: " .. world:livesLeft(player), 0, 32, sw, "center")
    else
        love.graphics.printf(formatTime(world.match.timeLeft) .. "   -   first to " ..
            World.KILL_TARGET .. " kills", 0, 32, sw, "center")
    end
    if world.match.over then
        -- the result screen says it all
    elseif player.out then
        love.graphics.printf("Out of lives - watching your team", 0, 60, sw, "center")
    elseif player.dead then
        love.graphics.printf(string.format("You were defeated - respawn in %.1f",
            math.max(0, player.respawnTimer)), 0, 60, sw, "center")
    elseif world.mode.waves and world:countBots() == 0 then
        love.graphics.printf(string.format("Wave cleared! %d bots incoming in %.1f",
            math.min(world.waveSize + 1, World.MAX_BOTS), math.max(0, world.waveTimer)),
            0, 60, sw, "center")
    end
    drawMinimap(sw)
    love.graphics.pop()
end

local function drawGame()
    -- Health bars: own and bots in their own colors, other players by team
    for _, e in ipairs(world.entities) do
        e.showAmmo = (e == player)
        if e == player or e.isBot then e.hudColor = nil
        elseif world:isOpponent(e, player) then e.hudColor = OPPONENT_COLOR
        else e.hudColor = TEAMMATE_COLOR end
    end

    -- World (moves with the camera)
    Camera.attach()
    Arena.drawBelow()
    if input and not player.dead then
        if input.aimingSuper and player.super then player:drawAim(true)
        elseif input.aiming then player:drawAim() end
    end
    for _, m in ipairs(world.medpacks) do Medpack.draw(m, world.time) end
    Effects.drawBelow()
    for _, b in ipairs(world.bullets) do b:draw() end
    for _, e in ipairs(world.entities) do
        if e ~= player and not hidden(e) then e:draw() end
    end
    player:draw() -- own rowdy on top
    Effects.drawAbove()
    Arena.drawBushes(player)
    Camera.detach()

    -- Virtual sticks + super button (touch only)
    if playing() then Controls.draw() end
    if not world.match.over then drawHud() end -- the result screen shows the scores
end

function love.draw()
    local betweenRounds = state == "pick" and pickFor == "between"
    if state == "menu" or state == "join" or (state == "pick" and not betweenRounds) then
        Camera.attach()
        Arena.drawBelow()
        Arena.drawBushes(nil)
        Camera.detach()
        if state == "menu" then Menu.draw(MENU, menuFonts, Controls.touchMode)
        elseif state == "join" then Join.draw(menuFonts)
        else Picker.draw(menuFonts) end
        return
    end
    if not player then
        drawWaiting(client.state == "connecting" and ("Connecting to " .. Join.address .. " ...")
            or "Joining ...")
        return
    end
    drawGame()
    if betweenRounds then
        Picker.draw(menuFonts, "Choose your rowdy for the next round")
    elseif world.match.over then
        Result.draw(resultInfo(), menuFonts)
    end
end

-- Menus, rowdy choice, join screen, result screen: taps and clicks
local function press(x, y)
    if state == "menu" then
        local i = Menu.hit(MENU, x, y)
        if i then startMenuEntry(i) end
    elseif state == "pick" then
        local what, i = Picker.hit(x, y)
        if what == "card" then
            if Picker.selected == i then confirmPick() else Picker.selected = i end
        elseif what == "confirm" then confirmPick()
        elseif what == "back" then cancelPick() end
    elseif state == "game" and world and world.match.over then
        local id = Result.hit(resultInfo(), x, y)
        if id then resultAction(id) end
    elseif state == "join" then
        local what, i = Join.hit(x, y)
        if what == "game" then joinGame(Join.games[i].address)
        elseif what == "connect" then joinGame()
        elseif what == "back" then Join.close(); openMenu()
        elseif what == "field" then love.keyboard.setTextInput(true) end
    end
end

-- Touch input (Android/iOS)
function love.touchpressed(id, x, y)
    if playing() then Controls.touchpressed(id, x, y) end
end
function love.touchmoved(id, x, y)
    if playing() then Controls.touchmoved(id, x, y) end
end
function love.touchreleased(id, x, y)
    if playing() then Controls.touchreleased(id, x, y)
    else Controls.touchMode = true; press(x, y) end
end

-- Mouse (touches also arrive here as emulated mouse events: skip those)
function love.mousereleased(x, y, button, istouch)
    if not playing() and button == 1 and not istouch then press(x, y) end
end
function love.mousemoved(x, y, dx, dy, istouch)
    if state == "menu" and not istouch then
        Menu.selected = Menu.hit(MENU, x, y) or Menu.selected
    end
end

function love.textinput(t)
    if state == "join" then Join.textinput(t) end
end

-- Escape (= Android back button): game/join -> menu, rowdy choice -> back,
-- menu -> quit
function love.keypressed(key)
    if state == "menu" then
        if key == "escape" then love.event.quit() return end
        local i = Menu.keypressed(MENU, key)
        if i then startMenuEntry(i) end
        return
    elseif state == "pick" then
        local action = Picker.keypressed(key)
        if action == "confirm" then confirmPick()
        elseif action == "back" then cancelPick() end
        return
    elseif state == "join" then
        local action = Join.keypressed(key)
        if action == "connect" then joinGame()
        elseif action == "back" then Join.close(); openMenu() end
        return
    end
    if key == "escape" then openMenu() return end
    if key == "f2" then -- toggle art style: comic <-> Kenney (only the looks change)
        Assets.style = (Assets.style == "comic") and "kenney" or "comic"
        if world then world:restyle() end
        return
    end
    if world and world.match.over then
        local id = Result.keypressed(resultInfo(), key)
        if id then resultAction(id) end
    end
end

function love.quit()
    if server then server:close() end
    if client then client:close() end
end
