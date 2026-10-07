-- A newer downloaded build (src/updater.lua) runs instead of this one: nothing else here
if require("src.updater").boot() then return end

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
local Loot     = require("src.loot")
local Profile  = require("src.profile")
local Picker   = require("src.picker")
local Result   = require("src.result")
local Scoreboard = require("src.scoreboard")
local Sound    = require("src.sound")
local Updater  = require("src.updater")
local Cosmetics = require("src.cosmetics")
local Pass     = require("src.pass")
local PassView = require("src.passview")
local Seasons  = require("src.seasons")
local Unlock   = require("src.unlock")
local Wardrobe = require("src.wardrobe")

-- Game modes (round rules: see World.KILL_TARGET / TIME_LIMIT / LIVES).
--   waves = false: duel - the bots respawn; first to 10 kills or most kills after
--                  3 minutes wins (LAN: free-for-all)
--   waves = true : killed bots stay dead; clearing a wave starts a bigger one; 3 lives
--                  per player (LAN: co-op)
--   teams = true : team fight - 3 vs 3, the players together, bots fill the empty places;
--                  first team to 15 kills
--   boss = index : boss fight against that rowdy (src/unlock.lua; built in startBoss,
--                  not on the mode list) - no time limit, won when the boss is out
local MODES = {
    duel  = { name = "Duel",  waves = false },
    team  = { name = "Team fight", waves = false, teams = true },
    waves = { name = "Waves", waves = true },
}

-- Modes on the start screen (src/menu.lua): solo first, then the LAN ones.
-- id: saved with the last choice; icon: picture on the mode card.
Menu.entries = {
    { id = "duel", name = "Duel", description = "1 vs 1 against a bot - first to 10 knockouts",
      icon = "duel", mode = MODES.duel },
    { id = "team", name = "Team fight", description = "You + 2 bots vs 3 bots - first team to 15 knockouts",
      icon = "team", mode = MODES.team },
    { id = "waves", name = "Waves", description = "3 lives - every wave brings one more bot",
      icon = "waves", mode = MODES.waves },
    { id = "hostDuel", name = "Host duel", description = "Free-for-all - everybody against everybody",
      icon = "duel", mode = MODES.duel, host = true, lan = true },
    { id = "hostTeam", name = "Host team fight", description = "Play together - 3 vs 3 with bots",
      icon = "team", mode = MODES.team, host = true, lan = true },
    { id = "hostWaves", name = "Host waves", description = "Survive waves together",
      icon = "waves", mode = MODES.waves, host = true, lan = true },
    { id = "join", name = "Join", description = "Play in a game hosted in your Wi-Fi",
      icon = "join", join = true, lan = true },
}

local MAX_STEPS = 5 -- simulation steps per frame at most (after a hitch: slow down instead)
local MUTE_SIZE = 44 -- touch mute button in the top right corner (HUD units)
local OPPONENT_COLOR = { 1, 0.5, 0.15 } -- health bar of other players
local TEAMMATE_COLOR = { 0.3, 0.6, 1 }
local ENEMY_TEAM_COLOR = { 1, 0.3, 0.25 } -- team fight: enemies (bots and players)

local state = "menu" -- "menu", "pick" (rowdy choice), "join", "game", "pass" (Yard Pass)
                     -- or "style" (cosmetics)
local pickFor        -- what the rowdy choice is for: "lobby" or "between" rounds
local styleFrom      -- where the style screen goes back to: "menu" or "pick"
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
local pendingDist    -- how far that shot's bomb flies (input.aimDist of its frame)
local input -- last controls reading
local muteTouch -- id of the touch that pressed the mute button (its release is ignored)
local hudFont
local boardFonts -- scoreboard: { small, big, banner }
local watch = {} -- last frame's round state, to notice what is worth a banner
local watchMatch -- (defined with the HUD below; called from love.update)
local betweenRounds -- (defined with playing() below)
local roundCoins = 0 -- coins the own rowdy picked up this round
local roundReward    -- coins for the finished round: { outcome, coins } (result screen)
local roundXp        -- Yard Pass XP of the finished round (Pass.onRoundOver + shownAt)
local roundUnlock    -- boss fight won: what it unlocked (Unlock.won's message)
local tierUpSoundAt  -- love.timer time to play "tierUp" (when the result's XP bar is full)

-- HUD is laid out for a 720px screen (short side) and scaled on bigger/denser screens
local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end

local function resetGame()
    accumulator, pendingFire, pendingSuper, input = 0, nil, nil, nil
    world, player, localId = nil, nil, nil
    Effects.clear()
    Controls.reset()
    Scoreboard.clear()
    watch = {}
    roundCoins, roundReward, roundXp, tierUpSoundAt, roundUnlock = 0, nil, nil, nil, nil
    Pass.roundStart()
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
    Menu.modesOpen = false
    Menu.message, Menu.notice = message, nil
    Controls.reset()
end

-- Single player or LAN host: this device runs the world. def: the own rowdy
-- (default: the one chosen in the lobby)
local function newGame(mode, host, def)
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
    def = def or Rowdies[Menu.rowdy]
    if mode.teams then
        player = world:addTeamPlayer(def, Pass.style(def))
    else
        player = world:addPlayer(def, Arena.spawn.x, Arena.spawn.y, nil, Pass.style(def))
    end
    localId = player.id
    world:start()
    world:takeEvents() -- the bots' spawn sounds would all play at once
    Sound.play("roundStart")
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
    client, err = Net.newClient(address, Menu.rowdy, Pass.style(Rowdies[Menu.rowdy]))
    if not client then Join.status = err return end
    Join.save()
    Join.close()
    closeFinder()
    resetGame()
    replica = Replica.new()
    state, role = "game", "client"
    Menu.message = nil
end

-- Buy a beaten rowdy with coins (src/profile.lua). Returns the message to show.
local function buy(def)
    if Profile.unlock(def) then
        Sound.play("unlock")
        return def.name .. " unlocked!"
    end
    Sound.play("click")
    return "Not enough coins - win rounds and break boxes"
end

-- Rowdy choice from the start screen ("lobby") or between rounds ("between")
local function openPicker(forWhat)
    Sound.play("click")
    state, pickFor = "pick", forWhat
    Picker.selected = Menu.rowdy
    Picker.message = nil
    Picker.reveal()
    if forWhat == "between" then
        Picker.confirmLabel = (role == "client") and "OK" or "Play"
    else
        Picker.confirmLabel = "Select"
    end
end

-- The boss fight panel in the lobby, for the rowdy shown there (src/unlock.lua)
local function openBoss()
    Sound.play("click")
    local def = Rowdies[Menu.rowdy]
    if not Unlock.canChallenge(def) then
        Menu.notice = Unlock.why(def)
        return
    end
    Menu.checkFighter()
    Menu.bossOpen = true
end

local function confirmPick()
    if Picker.locked() then
        local def = Rowdies[Picker.selected]
        local lock = Unlock.state(def)
        if lock == "buy" then
            Picker.message = buy(def)
        elseif pickFor ~= "lobby" then -- between rounds: only from the lobby
            Sound.play("click")
            Picker.message = lock == "pass" and Unlock.why(def)
                or ("Challenge the " .. def.name .. " from the lobby")
        elseif lock == "pass" then -- the button says "Yard Pass"
            Sound.play("click")
            state = "pass"
            PassView.open()
        else -- "Challenge": the boss fight panel in the lobby
            Menu.rowdy = Picker.selected
            Menu.save()
            state = "menu"
            openBoss()
        end
        return
    end
    Sound.play("click")
    Menu.rowdy = Picker.selected
    Menu.save()
    if pickFor == "between" then
        state = "game"
        local def = Rowdies[Menu.rowdy]
        if client then
            client:selectRowdy(Menu.rowdy, Pass.style(def)) -- the host switches us before its next round
        else
            world:setRowdy(player, def, Pass.style(def))
            world:restartMatch()
        end
    else
        state = "menu"
    end
end

local function cancelPick()
    Sound.play("click")
    if pickFor == "between" then state = "game" else state = "menu" end
end

-- Yard Pass screen (src/passview.lua) and style screen (src/wardrobe.lua)
local function openPass()
    Sound.play("click")
    state = "pass"
    PassView.open()
end

local function openStyle(from, rowdyIndex)
    Sound.play("click")
    styleFrom = from
    state = "style"
    Wardrobe.open(rowdyIndex)
end

local function closeStyle()
    Sound.play("click")
    if styleFrom == "pick" then
        state = "pick"
        Picker.selected = Wardrobe.rowdy
        Picker.reveal()
    else
        state = "menu"
        if Profile.isUnlocked(Rowdies[Wardrobe.rowdy]) then -- show what was styled
            Menu.rowdy = Wardrobe.rowdy
            Menu.save()
        end
    end
end

-- Pass screen actions (from PassView.hit / PassView.keypressed)
local function passAction(what, i)
    local season = Pass.season()
    if what == "back" then
        Sound.play("click")
        state = "menu"
    elseif what == "prev" or what == "next" then
        if PassView.switchSeason(what == "next" and 1 or -1) then Sound.play("click") end
    elseif what == "swap" then
        Sound.play("click")
        if Pass.swap(i) then PassView.say("New challenge!") end
    elseif what == "tier" or what == "bonus" then
        local msg
        if what == "tier" then msg = Pass.claim(season, i) else msg = Pass.claimBonus(season) end
        if msg then
            Sound.play("claim")
            PassView.celebrate(msg, what == "tier" and i or #season.tiers + 1)
        elseif what == "tier" and Pass.tierState(season, i) == "locked" then
            Sound.play("click")
            PassView.say("Reach tier " .. i .. " to claim this")
        end
    elseif what == "claimAll" and season then
        local n, last = 0, nil
        for t = 1, #season.tiers do
            local msg = Pass.claim(season, t)
            if msg then n, last = n + 1, msg end
        end
        while Pass.bonusReady(season) > 0 do
            last, n = Pass.claimBonus(season), n + 1
        end
        if n > 0 then
            Sound.play("claim")
            PassView.celebrate(n == 1 and last or (n .. " rewards claimed!"))
        end
    end
end

-- Boss fight against the rowdy shown in the lobby, with Menu.fighter
local function startBoss(host)
    local def = Rowdies[Menu.rowdy]
    Menu.bossOpen = false
    Menu.save()
    newGame({ name = "Boss fight: " .. def.name, boss = Menu.rowdy }, host, Rowdies[Menu.fighter])
end

-- PLAY on the start screen: the chosen mode with the chosen rowdy (a locked one:
-- CHALLENGE / UNLOCK / YARD PASS, see src/unlock.lua)
local function play()
    local lock = Unlock.state(Rowdies[Menu.rowdy])
    if lock == "pass" then openPass() return end
    if lock == "challenge" then openBoss() return end
    if lock == "buy" then
        Menu.notice = buy(Rowdies[Menu.rowdy])
        return
    end
    Sound.play("click")
    Menu.fighter = Menu.rowdy
    Menu.save()
    local entry = Menu.entry()
    if entry.join then openJoin() else newGame(entry.mode, entry.host) end
end

-- Hidden test mode (Profile.testMode): 7 taps on the build line within 4 seconds
local versionTaps = {}
local function tapVersion()
    local now = love.timer.getTime()
    versionTaps[#versionTaps + 1] = now
    while versionTaps[1] and now - versionTaps[1] > 4 do table.remove(versionTaps, 1) end
    if #versionTaps < 7 then return end
    versionTaps = {}
    Profile.setTestMode(not Profile.testMode)
    Sound.play(Profile.testMode and "unlock" or "click")
    Menu.notice = Profile.testMode and "Test mode: all rowdies and Yard Pass items unlocked"
        or "Test mode off"
end

-- Start screen actions (from Menu.hit / Menu.keypressed)
local function menuAction(what, i)
    if what == "play" then play()
    elseif what == "bossSolo" or what == "bossHost" then startBoss(what == "bossHost")
    elseif what == "bossBack" then Sound.play("click"); Menu.bossOpen = false
    elseif what == "fighterPrev" or what == "fighterNext" then
        Sound.play("click")
        Menu.switchFighter(what == "fighterNext" and 1 or -1)
        Menu.save()
    elseif what == "version" then tapVersion()
    elseif what == "rowdies" then openPicker("lobby")
    elseif what == "pass" then openPass()
    elseif what == "style" then openStyle("menu", Menu.rowdy)
    elseif what == "prev" or what == "next" then
        Sound.play("click")
        Menu.notice = nil
        Menu.rowdy = (Menu.rowdy - 1 + (what == "next" and 1 or -1)) % #Rowdies + 1
        Menu.save()
    elseif what == "mode" then Sound.play("click"); Menu.modesOpen = true
    elseif what == "pick" then Sound.play("click"); Menu.mode = i
    elseif what == "close" or what == "outside" then
        Sound.play("click")
        Menu.modesOpen = false
        Menu.save()
    elseif what == "quit" then love.event.quit() end
end

local function playing()
    return state == "game" and player ~= nil and not world.match.over
end

-- The rowdy choice (or its style screen) between two rounds: the game goes on behind
function betweenRounds()
    return pickFor == "between" and (state == "pick" or (state == "style" and styleFrom == "pick"))
end

function love.load(args)
    love.graphics.setBackgroundColor(0.05, 0.15, 0.08)
    Assets.load()
    Sound.load()
    Profile.load()
    Pass.load()
    Pass.refresh(true)
    Menu.load()
    love.resize()
    openMenu()
    -- Testing shortcuts: love . [--rowdy N] [--coins N] --host [team|waves] |
    -- --boss N [host] (boss fight against rowdy N, fighting with the last used one) |
    -- --join <address> | --find   (--coins adds to the saved coins)
    for i, a in ipairs(args or {}) do
        if a == "--coins" then Profile.addCoins(tonumber(args[i + 1]) or 0) end
        if a == "--rowdy" then Menu.rowdy = Rowdies[tonumber(args[i + 1])] and tonumber(args[i + 1]) or 1 end
        if a == "--find" then openJoin() end
        if a == "--boss" and Rowdies[tonumber(args[i + 1])] then -- boss fight (any rowdy)
            Menu.rowdy = tonumber(args[i + 1])
            Menu.checkFighter()
            startBoss(args[i + 2] == "host")
        end
        if a == "--host" then
            newGame(MODES[args[i + 1]] or MODES.duel, true) -- duel / team / waves
        elseif a == "--join" and args[i + 1] then
            Join.address = args[i + 1]
            joinGame()
        end
    end
    Updater.start(args)
end

function love.resize()
    local dpi = math.max(1, uiScale())
    hudFont = love.graphics.newFont(16, "normal", dpi)
    Controls.font = hudFont
    boardFonts = {
        small  = love.graphics.newFont(12, "normal", dpi),
        big    = love.graphics.newFont(24, "normal", dpi),
        banner = love.graphics.newFont(40, "normal", dpi),
    }
    menuFonts = {
        title  = love.graphics.newFont(56, "normal", dpi),
        button = love.graphics.newFont(26, "normal", dpi),
        text   = hudFont,
    }
end

local function hidden(e) return world:isHiddenFrom(e, player) end

-- How the finished round went for this device's player: "win", "draw", "loss" or
-- "waves" (no winner in co-op)
local function outcomeOf(ev)
    if world.mode.waves then return "waves" end
    if world.mode.teams or world.mode.boss then -- (boss fight: the players' team wins)
        if not ev.winnerTeam then return "draw" end
        return (player and ev.winnerTeam == player.team) and "win" or "loss"
    end
    if not ev.winner then return "draw" end
    return ev.winner == localId and "win" or "loss"
end

local WOOD = { 0.6, 0.3, 0.15 }
local GOLD = { 1, 0.82, 0.2 }

-- Turn simulation events into particles, screen shake and sounds (and Yard Pass XP)
local function playEvents(events)
    for _, ev in ipairs(events) do
        Pass.onEvent(ev, localId, world)
        if ev.kind == "spawn" then
            Effects.ring(ev.x, ev.y, 45, { 1, 1, 1 })
            Sound.play("spawn", ev.x, ev.y, 0.7)
        elseif ev.kind == "death" then -- knocked out: a cartoon poof (CHARTER.md)
            Effects.poof(ev.x, ev.y)
            Effects.ring(ev.x, ev.y, 55, { 1, 1, 1 })
            Sound.play("poof", ev.x, ev.y)
        elseif ev.kind == "step" then
            Effects.puff(ev.x, ev.y)
        elseif ev.kind == "shot" then
            local e = world:get(ev.id)
            Sound.play(Sound.shotFor(e and e.def), ev.x, ev.y, ev.id == localId and 0.8 or 0.6)
        elseif ev.kind == "impact" then
            Effects.sparks(ev.x, ev.y, 4, ev.color, 140) -- bullet hit a wall / crate
            Sound.play("impact", ev.x, ev.y)
        elseif ev.kind == "super" then
            Effects.ring(ev.x, ev.y, 50, { 1, 0.82, 0.1 })
            Effects.sparks(ev.x, ev.y, 10, { 1, 0.85, 0.3 }, 260)
            if ev.id == localId then Camera.shake(4) end
            Sound.play("super", ev.x, ev.y)
        elseif ev.kind == "superReady" then
            if ev.id == localId then Sound.play("superReady") end
        elseif ev.kind == "heal" then
            Effects.heal(ev.x, ev.y)
            Effects.ring(ev.x, ev.y, 40, { 0.4, 1, 0.4 })
            Sound.play("heal", ev.x, ev.y)
        elseif ev.kind == "hit" then
            Effects.sparks(ev.x, ev.y, 7, { 1, 0.92, 0.55 }, 200)
            if ev.victim == localId then
                Camera.shake(5)
                Sound.play("hurt")
            else
                Sound.play("hit", ev.x, ev.y)
            end
        elseif ev.kind == "blast" then -- a bomb exploded: fire ring, smoke, sparks
            local r = tonumber(ev.radius) or 90
            Effects.ring(ev.x, ev.y, r, { 1, 0.55, 0.15 })
            Effects.ring(ev.x, ev.y, r * 0.6, { 1, 0.9, 0.4 })
            Effects.burst(ev.x, ev.y, { 1, 0.5, 0.1 }, math.floor(10 + r / 10))
            Effects.burst(ev.x, ev.y, { 0.35, 0.33, 0.32 }, 8)
            Effects.sparks(ev.x, ev.y, 14, { 1, 0.85, 0.4 }, 320)
            for i = 1, 8 do
                local a = i / 8 * math.pi * 2
                Effects.puff(ev.x + math.cos(a) * r * 0.5, ev.y + math.sin(a) * r * 0.5)
            end
            if player then
                local d = math.sqrt((player.x - ev.x) ^ 2 + (player.y - ev.y) ^ 2)
                if d < 500 then Camera.shake((ev.super and 9 or 6) * (1 - d / 500)) end
            end
            Sound.play(ev.super and "blastBig" or "blast", ev.x, ev.y)
        elseif ev.kind == "box" then
            Effects.ring(ev.x, ev.y, 50, GOLD)
            Sound.play("box", ev.x, ev.y)
        elseif ev.kind == "boxHit" then
            Effects.sparks(ev.x, ev.y, 5, WOOD, 160)
            Sound.play("boxHit", ev.x, ev.y)
        elseif ev.kind == "boxBreak" then
            Effects.burst(ev.x, ev.y, WOOD, 14)
            Effects.sparks(ev.x, ev.y, 12, GOLD, 240)
            Effects.ring(ev.x, ev.y, 60, GOLD)
            Sound.play("boxBreak", ev.x, ev.y)
        elseif ev.kind == "coin" then
            Effects.sparks(ev.x, ev.y, 6, GOLD, 150)
            if ev.id == localId then -- ours: the coins go to this device's profile
                local value = tonumber(ev.value) or 0
                roundCoins = roundCoins + value
                Profile.addCoins(value)
                Sound.play("coin")
            else
                Sound.play("coin", ev.x, ev.y, 0.5)
            end
        elseif ev.kind == "matchStart" then
            roundCoins, roundReward, roundXp, tierUpSoundAt, roundUnlock = 0, nil, nil, nil, nil
            Pass.roundStart()
            Sound.play("roundStart")
        elseif ev.kind == "matchOver" then
            local outcome = outcomeOf(ev)
            Sound.play((outcome == "win" and "victory") or (outcome == "draw" and "draw")
                or "defeat")
            if player then
                roundReward = { outcome = outcome, coins = Profile.roundReward(outcome, ev.wave) }
                Profile.addCoins(roundReward.coins)
                roundXp = Pass.onRoundOver(outcome, ev.wave, localId, world)
                -- boss fight won: every device that took part unlocks on its own (the
                -- one that started it pays; a LAN helper may unlock it later)
                local boss = world.mode.boss and Rowdies[tonumber(world.mode.boss)]
                if boss and outcome == "win" then
                    roundUnlock = Unlock.won(boss, role ~= "client")
                    if roundUnlock and Profile.owns(boss) then
                        Sound.play("unlock")
                        Menu.rowdy, Menu.fighter = tonumber(world.mode.boss), tonumber(world.mode.boss)
                        Menu.save()
                    end
                end
                if roundXp then
                    roundXp.shownAt = love.timer.getTime() + 0.4
                    if roundXp.tiersUp > 0 then tierUpSoundAt = roundXp.shownAt + 1.5 end
                end
            end
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
    if input.fire or input.super then pendingDist = input.aimDist end

    accumulator = math.min(accumulator + dt, World.TICK * MAX_STEPS)
    while accumulator >= World.TICK do
        accumulator = accumulator - World.TICK
        local inputs = { [localId] = { dx = input.dx, dy = input.dy, aim = input.aim,
            aimDist = (pendingFire or pendingSuper) and pendingDist or input.aimDist,
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
    if input.aim then player.aim, player.aimDist = input.aim, input.aimDist end
end

function love.update(dt)
    Updater.update(dt)
    Menu.status = Updater.status
    -- A downloaded update is used right away if nobody is busy in the lobby
    if Updater.ready and state == "menu" and not Menu.modesOpen then
        love.event.quit("restart")
    end
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
    if state == "pass" then PassView.update(dt) end
    if tierUpSoundAt and love.timer.getTime() >= tierUpSoundAt then
        tierUpSoundAt = nil
        Sound.play("tierUp")
    end
    -- The game keeps running while a rowdy is chosen between rounds (LAN!)
    local inGame = state == "game" or betweenRounds()
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
    Scoreboard.update(dt)
    if player and world then watchMatch() end
    if player then
        Camera.update(dt, player.x, player.y, Arena.width, Arena.height)
        Sound.setListener(player.x, player.y)
    end
end

-- Minimap position and size (HUD units): top right, left of the mute button on touch
local function minimapRect(screenW)
    local mw = 200
    local x0 = screenW - mw - 12
    if Controls.touchMode then x0 = x0 - MUTE_SIZE - 12 end -- room for the mute button
    return x0, 12, mw, Arena.height * mw / Arena.width
end

local function drawMinimap(screenW)
    local x0, y0, mw, mh = minimapRect(screenW)
    local s = mw / Arena.width
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
    love.graphics.setColor(1, 0.8, 0.15, 1)
    for _, b in ipairs(world.boxes) do
        love.graphics.rectangle("fill", x0 + b.x * s - 3.5, y0 + b.y * s - 3.5, 7, 7)
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

local function nameOf(e)
    if e.id == localId then return "You" end
    if e.boss then return "Boss" end
    if e.isBot then return "Bot" end
    return "Player " .. e.id
end

-- "1 knockout", "3 knockouts"
local function count(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

-- A scoreboard line's numbers: "3 knockouts   out 1 time"
local function score(e) return count(e.kills, "knockout") .. "   out " .. count(e.deaths, "time") end

-- Name with the Yard Pass title, for the result scoreboard ('You "Yard Veteran"')
local function fullName(e)
    local title = Cosmetics.get(e.title, "title")
    return nameOf(e) .. (title and (' "' .. title.name .. '"') or "")
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
        lines[#lines + 1] = { string.format("%s (%s)   %s", fullName(e),
            e.def and e.def.name or "?", score(e)), e.id == localId,
            Cosmetics.get(e.badge, "badge") and e.badge }
    end

    local info = { lines = lines }
    if world.mode.teams then
        -- scoreboard: own team first
        table.sort(list, function(a, b)
            local ma, mb = a.team == player.team, b.team == player.team
            if ma ~= mb then return ma end
            if a.kills ~= b.kills then return a.kills > b.kills end
            return a.id < b.id
        end)
        lines = {}
        for _, e in ipairs(list) do
            lines[#lines + 1] = { string.format("%s  %s (%s)   %s",
                e.team == player.team and "[Your team]" or "[Enemies]", fullName(e),
                e.def and e.def.name or "?", score(e)), e.id == localId,
                Cosmetics.get(e.badge, "badge") and e.badge }
        end
        info.lines = lines
        if not m.winnerTeam then
            info.title, info.color = "Draw", { 1, 1, 1 }
        elseif m.winnerTeam == player.team then
            info.title, info.color = "Victory!", { 1, 0.82, 0.1 }
        else
            info.title, info.color = "Defeat", { 1, 0.35, 0.3 }
        end
        local s = world:teamScores()
        local own, other = s[player.team] or 0, 0
        for team, k in pairs(s) do if team ~= player.team then other = other + k end end
        info.subtitle = ((m.timeLeft and m.timeLeft <= 0) and "Time is up" or "Knockout target reached")
            .. "   -   Your team " .. own .. " : " .. other .. " Enemies"
    elseif world.mode.boss then -- always won: you can't lose a boss fight
        local boss = world:boss()
        info.title, info.color = "Boss beaten!", { 1, 0.82, 0.1 }
        info.subtitle = roundUnlock or ("The " .. (boss and boss.def.name or "boss") .. " is out!")
    elseif world.mode.waves then
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
            info.subtitle = nameOf(winner) .. " reached " .. World.KILL_TARGET .. " knockouts"
        end
    end
    if roundReward then
        local parts = {}
        if roundReward.coins > 0 then
            local what = { win = "victory", draw = "draw", loss = "round", waves = "waves" }
            parts[#parts + 1] = what[roundReward.outcome] .. " " .. roundReward.coins
        end
        if roundCoins > 0 then parts[#parts + 1] = "boxes " .. roundCoins end
        local total = roundReward.coins + roundCoins
        info.reward = "+" .. total .. (#parts > 0 and ("  (" .. table.concat(parts, " + ") .. ")") or "")
            .. "   -   you have " .. Profile.coins
    end
    info.xp = roundXp
    if role == "client" then
        info.buttons = { { "rowdy", "Rowdy" }, { "menu", "Leave" } }
        info.note = "Waiting for the host to start the next round"
    elseif world.mode.boss then -- won: nothing to play again alone (friends may want theirs)
        info.buttons = role == "host" and { { "again", "Fight again" }, { "menu", "Menu" } }
            or { { "menu", "Back to the lobby" } }
        if role == "host" then
            info.note = "Players who joined stay for the next fight (" .. server:playerCount() .. ")"
        end
    else
        info.buttons = { { "again", "Play again" }, { "rowdy", "Rowdy" }, { "menu", "Menu" } }
        if role == "host" then
            info.note = "Players who joined stay for the next round (" .. server:playerCount() .. ")"
        end
    end
    return info
end

local function resultAction(id)
    Sound.play("click")
    if id == "again" then
        world:setStyle(player, Pass.style(player.def)) -- (changed in the style screen)
        world:restartMatch()
        Result.selected = 1
    elseif id == "rowdy" then
        openPicker("between")
    elseif id == "menu" then
        openMenu()
    end
end

local OWN_COLOR, BOT_COLOR = { 0.25, 0.7, 0.35 }, { 0.85, 0.25, 0.25 }

-- What the scoreboard shows (src/scoreboard.lua). Duel: you against whoever of the
-- others has the most kills (the bot, or the leading player in a LAN game).
local function scoreboardInfo()
    local m = world.match
    if world.mode.boss then
        local boss = world:boss()
        return { kind = "boss", name = boss and boss.def.name:upper() or "BOSS",
                 hp = boss and boss.hp or 0, maxHp = boss and boss.maxHp or 1 }
    end
    if world.mode.waves then
        return { kind = "waves", wave = world.wave, bots = world:countBots(),
                 lives = world:livesLeft(player), maxLives = World.LIVES }
    end
    local info = { kind = "versus", timeLeft = m.timeLeft }
    if world.mode.teams then
        local s = world:teamScores()
        local other = 0
        for team, k in pairs(s) do if team ~= player.team then other = other + k end end
        info.left = { name = "YOUR TEAM", score = s[player.team] or 0, color = TEAMMATE_COLOR }
        info.right = { name = "ENEMIES", score = other, color = ENEMY_TEAM_COLOR }
        info.target = World.TEAM_KILL_TARGET
        return info
    end
    local best
    for _, e in ipairs(world.entities) do
        if e ~= player and (not best or e.kills > best.kills) then best = e end
    end
    info.left = { name = "YOU", score = player.kills, color = OWN_COLOR }
    info.right = { name = best and nameOf(best):upper() or "-", who = best and nameOf(best),
                   score = best and best.kills or 0,
                   color = (best and not best.isBot) and OPPONENT_COLOR or BOT_COLOR }
    info.target = World.KILL_TARGET
    return info
end

-- Banners for things that just happened: time marks, a new wave, a lost life,
-- one kill to win (compares with the last frame, so it works on LAN clients too)
function watchMatch()
    if world.match.over then watch = {} return end
    local now = {}
    if world.mode.boss then -- cheer the players on halfway and near the end
        local info = scoreboardInfo()
        now.share = info.hp / info.maxHp
        for _, mark in ipairs({ { 0.5, "Halfway there!" }, { 0.2, "Almost done - keep going!" } }) do
            if watch.share and watch.share > mark[1] and now.share <= mark[1] then
                Scoreboard.flash(mark[2], { 0.5, 1, 0.5 })
            end
        end
    elseif world.mode.waves then
        now.wave, now.lives = world.wave, world:livesLeft(player)
        if now.wave > (watch.wave or 0) then Scoreboard.flash("Wave " .. now.wave) end
        if watch.lives and now.lives < watch.lives and now.lives > 0 then
            Scoreboard.flash(now.lives == 1 and "Last life!" or (now.lives .. " lives left"),
                { 1, 0.45, 0.45 })
        end
    else
        local info = scoreboardInfo()
        now.time, now.left, now.right = info.timeLeft, info.left.score, info.right.score
        for _, mark in ipairs({ { 60, "1 minute left" }, { 30, "30 seconds left!" }, { 10, "10 seconds!" } }) do
            if watch.time and watch.time > mark[1] and now.time <= mark[1] then
                Scoreboard.flash(mark[2], mark[1] <= 30 and { 1, 0.45, 0.45 } or nil)
            end
        end
        local need = info.target - 1
        if watch.left and watch.left < need and now.left >= need then
            Scoreboard.flash("1 knockout to win!", { 0.5, 1, 0.5 })
        elseif watch.right and watch.right < need and now.right >= need then
            Scoreboard.flash(world.mode.teams and "Enemies need 1 more knockout!"
                or (info.right.who .. " needs 1 more knockout!"), { 1, 0.45, 0.45 })
        end
    end
    watch = now
end

local function drawHud()
    local ui = uiScale()
    local sw, sh = love.graphics.getWidth() / ui, love.graphics.getHeight() / ui
    love.graphics.push()
    love.graphics.scale(ui)
    love.graphics.setFont(hudFont)
    love.graphics.setColor(1, 1, 1)
    local superInfo = ""
    if player.super and not Controls.touchMode then
        superInfo = "   [RMB/E] " .. player.super.name .. ": " ..
            (player.charge >= 1 and "READY" or (math.floor(player.charge * 100) .. "%"))
    end
    local topText = "FPS: " .. love.timer.getFPS() .. "   " ..
        (player.def and player.def.name or "") .. superInfo
    love.graphics.print(topText, 10, 10)
    if roundCoins > 0 then Loot.drawCounter("+" .. roundCoins, hudFont, 10, 52, 32) end
    -- Network details at the bottom left (out of the scoreboard's way)
    local net
    if role == "host" then
        net = "Hosting at " .. hostAddress .. "   players joined: " ..
            server:playerCount() .. "   searches answered: " .. (server.queries or 0) ..
            (server.lastQueryFrom and (" (last from " .. server.lastQueryFrom .. ")") or "")
    elseif role == "client" then
        net = "Ping: " .. client:ping() .. " ms"
    end
    if net then
        love.graphics.setColor(1, 1, 1, 0.7)
        love.graphics.print(net, 10, sh - 26)
        love.graphics.setColor(1, 1, 1)
    end

    -- Scoreboard top centre; below the minimap when it doesn't fit next to it
    -- (portrait / narrow windows)
    local mx, my, _, mh = minimapRect(sw)
    local W = Scoreboard.WIDTH
    local cx, top = sw / 2, 10
    if cx - W / 2 < 20 + hudFont:getWidth(topText) or cx + W / 2 > mx - 12 then
        top = my + mh + 16
    end
    Scoreboard.draw(scoreboardInfo(), boardFonts, cx, top, love.timer.getTime())

    love.graphics.setFont(hudFont)
    love.graphics.setColor(1, 1, 1)
    local y = top + Scoreboard.HEIGHT + 14
    if world.match.over then
        -- the result screen says it all
    elseif player.out then
        love.graphics.printf("Out of lives - watching your team", 0, y, sw, "center")
    elseif player.dead then
        love.graphics.printf(string.format("You're out - back in %.1f",
            math.max(0, player.respawnTimer)), 0, y, sw, "center")
    elseif world.mode.waves and world:countBots() == 0 then
        love.graphics.printf(string.format("Wave cleared! %d bots incoming in %.1f",
            math.min(world.waveSize + 1, World.MAX_BOTS), math.max(0, world.waveTimer)),
            0, y, sw, "center")
    end
    Scoreboard.drawBanner(boardFonts.banner, sw, sh * 0.3)
    drawMinimap(sw)
    love.graphics.pop()
end

local function drawGame()
    -- Health bars: own green; allies blue; enemy bots red, enemy players orange.
    -- Team fight: everybody else blue/red by team, plus a ring in that color.
    for _, e in ipairs(world.entities) do
        e.showAmmo = (e == player)
        local ally = not world:isOpponent(e, player)
        if e == player then e.hudColor = nil
        elseif ally then e.hudColor = TEAMMATE_COLOR
        elseif world.mode.teams then e.hudColor = ENEMY_TEAM_COLOR
        elseif e.boss then e.hudColor = BOT_COLOR -- its own bar colour may be green
        elseif e.isBot then e.hudColor = nil
        else e.hudColor = OPPONENT_COLOR end
        e.teamColor = world.mode.teams and (ally and TEAMMATE_COLOR or ENEMY_TEAM_COLOR) or nil
    end

    -- World (moves with the camera)
    Camera.attach()
    Arena.drawBelow()
    if input and not player.dead then
        if input.aimingSuper and player.super then player:drawAim(true)
        elseif input.aiming then player:drawAim() end
    end
    for _, m in ipairs(world.medpacks) do Medpack.draw(m, world.time) end
    for _, c in ipairs(world.coins) do Loot.drawGroundCoin(c, world.time) end
    for _, b in ipairs(world.boxes) do Loot.drawBox(b, world.time) end
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

-- Mute button (touch only): top right corner, HUD units
local function muteRect()
    local sw = love.graphics.getWidth() / uiScale()
    return sw - MUTE_SIZE - 12, 12, MUTE_SIZE
end

local function hitMute(x, y)
    if not Controls.touchMode then return false end
    local ui = uiScale()
    local bx, by, size = muteRect()
    x, y = x / ui, y / ui
    return x >= bx - 8 and x <= bx + size + 8 and y >= by - 8 and y <= by + size + 8
end

local function drawMuteButton()
    if not Controls.touchMode then return end
    local bx, by, size = muteRect()
    love.graphics.push()
    love.graphics.scale(uiScale())
    love.graphics.translate(bx, by)
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", 0, 0, size, size, 8, 8)
    -- speaker: box + cone
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.rectangle("fill", 9, 17, 7, 10)
    love.graphics.polygon("fill", 16, 17, 25, 9, 25, 35, 16, 27)
    love.graphics.setLineWidth(3)
    if Sound.muted then
        love.graphics.setColor(1, 0.35, 0.3)
        love.graphics.line(29, 16, 38, 28)
        love.graphics.line(38, 16, 29, 28)
    else
        love.graphics.arc("line", "open", 26, 22, 7, -0.9, 0.9)
        love.graphics.arc("line", "open", 26, 22, 13, -0.9, 0.9)
    end
    love.graphics.setLineWidth(1)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1)
end

local function drawScreen()
    local between = betweenRounds()
    if state ~= "game" and not between then
        Camera.attach()
        Arena.drawBelow()
        Arena.drawBushes(nil)
        Camera.detach()
        if state == "menu" then Menu.draw(menuFonts, Controls.touchMode)
        elseif state == "join" then Join.draw(menuFonts)
        elseif state == "pass" then PassView.draw(menuFonts)
        elseif state == "style" then Wardrobe.draw(menuFonts)
        else Picker.draw(menuFonts) end
        return
    end
    if not player then
        drawWaiting(client.state == "connecting" and ("Connecting to " .. Join.address .. " ...")
            or "Joining ...")
        return
    end
    drawGame()
    if state == "style" then
        Wardrobe.draw(menuFonts)
    elseif between then
        Picker.draw(menuFonts, "Choose your rowdy for the next round")
    elseif world.match.over then
        Result.draw(resultInfo(), menuFonts)
    end
end

function love.draw()
    drawScreen()
    drawMuteButton()
end

-- Menus, rowdy choice, join screen, result screen: taps and clicks
local function press(x, y)
    if state == "menu" then
        menuAction(Menu.hit(x, y))
    elseif state == "pick" then
        local what, i = Picker.hit(x, y)
        if what == "skins" then
            Picker.selected, Picker.message = i, nil
            openStyle("pick", i)
        elseif what == "card" then
            -- a second tap selects (not buys: that takes the Unlock button)
            if Picker.selected == i and not Picker.locked() then confirmPick()
            elseif Picker.selected ~= i then
                Picker.selected, Picker.message = i, nil
                Sound.play("click")
            end
        elseif what == "confirm" then confirmPick()
        elseif what == "back" then cancelPick() end
    elseif state == "pass" then
        passAction(PassView.hit(x, y))
    elseif state == "style" then
        local what, chip = Wardrobe.hit(x, y)
        if what == "back" then closeStyle()
        elseif what == "prev" or what == "next" then
            Sound.play("click")
            Wardrobe.switch(what == "next" and 1 or -1)
        elseif what == "chip" then
            Sound.play(Wardrobe.choose(chip) and "coin" or "click")
        end
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
    Controls.touchMode = true
    if hitMute(x, y) then
        Sound.toggleMute()
        muteTouch = id
        return
    end
    if state == "pick" then Picker.touchStart() end
    if state == "pass" then PassView.touchStart() end
    if playing() then Controls.touchpressed(id, x, y) end
end
function love.touchmoved(id, x, y, dx, dy)
    if id == muteTouch then return end
    if state == "pick" then Picker.drag(dy) end
    if state == "pass" then PassView.drag(dx) end
    if playing() then Controls.touchmoved(id, x, y) end
end
function love.touchreleased(id, x, y)
    if id == muteTouch then muteTouch = nil return end
    if playing() then Controls.touchreleased(id, x, y)
    elseif state == "pick" and Picker.dragged then Controls.touchMode = true -- scrolled
    elseif state == "pass" and PassView.dragged then Controls.touchMode = true
    else Controls.touchMode = true; press(x, y) end
end

-- Mouse (touches also arrive here as emulated mouse events: skip those)
function love.mousereleased(x, y, button, istouch)
    if not playing() and button == 1 and not istouch then press(x, y) end
end
function love.mousemoved(x, y, dx, dy, istouch)
    if state == "menu" and not istouch then
        Menu.mousemoved(x, y)
    end
end

function love.wheelmoved(x, y)
    if state == "pick" then Picker.wheel(y) end
    if state == "pass" then PassView.wheel(x, y) end
end

function love.textinput(t)
    if state == "join" then Join.textinput(t) end
end

-- M: sound on/off. Escape (= Android back button): game/join -> menu, rowdy choice, pass
-- and style screens -> back, menu -> quit
function love.keypressed(key)
    if key == "m" and state ~= "join" then Sound.toggleMute() return end
    if state == "menu" then
        local before = Menu.rowdy .. " " .. Menu.mode
        menuAction(Menu.keypressed(key))
        if state == "menu" and Menu.rowdy .. " " .. Menu.mode ~= before then
            Sound.play("click")
            Menu.notice = nil
            Menu.save()
        end
        return
    elseif state == "pick" then
        local before = Picker.selected
        local action = Picker.keypressed(key)
        if Picker.selected ~= before then Picker.message = nil end
        if action == "confirm" then confirmPick()
        elseif action == "back" then cancelPick() end
        return
    elseif state == "pass" then
        passAction(PassView.keypressed(key))
        return
    elseif state == "style" then
        local before = Wardrobe.rowdy
        if Wardrobe.keypressed(key) == "back" then closeStyle()
        elseif Wardrobe.rowdy ~= before then Sound.play("click") end
        return
    elseif state == "join" then
        local action = Join.keypressed(key)
        if action == "connect" then joinGame()
        elseif action == "back" then Join.close(); openMenu() end
        return
    end
    if key == "escape" then openMenu() return end
    if world and world.match.over then
        local id = Result.keypressed(resultInfo(), key)
        if id then resultAction(id) end
    end
end

function love.quit()
    if server then server:close() end
    if client then client:close() end
end
