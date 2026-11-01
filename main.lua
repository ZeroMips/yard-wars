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
local InfoView = require("src.infoview")
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
local Ball     = require("src.ball")
local Barrier  = require("src.barrier")
local King     = require("src.king")
local HideSeek = require("src.hideseek")
local Flowers  = require("src.flowers")

-- Game modes (round rules: see World.KILL_TARGET / TIME_LIMIT / LIVES).
--   waves = false: duel - the bots respawn; first to 10 kills or most kills after
--                  3 minutes wins (LAN: free-for-all)
--   waves = true : killed bots stay dead; clearing a wave starts a bigger one; 3 lives
--                  per player (LAN: co-op)
--   teams = true : team fight - 3 vs 3, the players together, bots fill the empty places;
--                  first team to 15 kills
--   boss = index : boss fight against that rowdy (src/unlock.lua; built in startBoss,
--                  not on the mode list) - no time limit, won when the boss is out
--   yardball     : a team fight with a ball and two goals (src/world.lua) - first team
--                  to 2 goals, no time limit
--   king         : King of the Yard - 4 teams of 3 on a big map, a knockout is out
--                  until a team mate brings it back at its heart; a fog closes in; the
--                  last team standing wins (LAN: the host's team fills up first)
--   hideseek     : Hide and seek - 1 seeker (random each round) and 5 hiders on a big
--                  map; hiders turn into bushes and fix the picture, the seeker tags them
--   flowers      : Flower Gardens - 4 teams of 3, each with a fenced garden in a corner;
--                  flowers carried home from the middle, every 5 a bulldozer that knocks
--                  down another team's fence (no fence: no popping back in); last team
--                  standing or the most flowers after 4 minutes (LAN: as King of the Yard)
local MODES = {
    duel  = { name = "Duel",  waves = false },
    team  = { name = "Team fight", waves = false, teams = true },
    waves = { name = "Waves", waves = true },
    yardball = { name = "Yardball", waves = false, teams = true, yardball = true },
    king = { name = "King of the Yard", waves = false, teams = true, king = true },
    hide = { name = "Hide and seek", waves = false, teams = true, hideseek = true },
    flowers = { name = "Flower Gardens", waves = false, teams = true, flowers = true },
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
    { id = "yardball", name = "Yardball", description = "3 vs 3 with a ball - first team to 2 goals",
      icon = "ball", mode = MODES.yardball },
    { id = "king", name = "King of the Yard", description = "4 teams of 3 - the last team standing wins",
      icon = "crown", mode = MODES.king },
    { id = "hide", name = "Hide and seek", description = "1 seeker, 5 hiders - turn into a bush or find them all",
      icon = "hide", mode = MODES.hide },
    { id = "flowers", name = "Flower Gardens", description = "4 teams of 3 - bring flowers home, bulldoze fences",
      icon = "flower", mode = MODES.flowers },
    { id = "hostDuel", name = "Host duel", description = "Free-for-all - everybody against everybody",
      icon = "duel", mode = MODES.duel, host = true, lan = true },
    { id = "hostTeam", name = "Host team fight", description = "Play together - 3 vs 3 with bots",
      icon = "team", mode = MODES.team, host = true, lan = true },
    { id = "hostWaves", name = "Host waves", description = "Survive waves together",
      icon = "waves", mode = MODES.waves, host = true, lan = true },
    { id = "hostYardball", name = "Host Yardball", description = "Yardball together - 3 vs 3 with bots",
      icon = "ball", mode = MODES.yardball, host = true, lan = true },
    { id = "hostKing", name = "Host King of the Yard", description = "Teams of 3 by joining order",
      icon = "crown", mode = MODES.king, host = true, lan = true },
    { id = "hostHide", name = "Host hide and seek", description = "Hide and seek together - up to 6 players",
      icon = "hide", mode = MODES.hide, host = true, lan = true },
    { id = "hostFlowers", name = "Host Flower Gardens", description = "Teams of 3 by joining order",
      icon = "flower", mode = MODES.flowers, host = true, lan = true },
    { id = "join", name = "Join", description = "Play in a game hosted in your Wi-Fi",
      icon = "join", join = true, lan = true },
}

local MAX_STEPS = 5 -- simulation steps per frame at most (after a hitch: slow down instead)
local MUTE_SIZE = 44 -- touch mute button in the top right corner (HUD units)
local OPPONENT_COLOR = { 1, 0.5, 0.15 } -- health bar of other players
local TEAMMATE_COLOR = { 0.3, 0.6, 1 }
local ENEMY_TEAM_COLOR = { 1, 0.3, 0.25 } -- team fight: enemies (bots and players)
-- King of the Yard, Flower Gardens: the own team blue, the other three in this order (by
-- team id)
local KING_COLORS = { { 1, 0.3, 0.25 }, { 0.3, 0.85, 0.35 }, { 1, 0.85, 0.2 } }
local KING_NAMES  = { "red", "green", "yellow" }

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
local dozerSound = 0 -- seconds until the next putt of the nearest bulldozer (Flower Gardens)

-- HUD is laid out for a 720px screen (short side) and scaled on bigger/denser screens
local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end

local function resetGame()
    accumulator, pendingFire, pendingSuper, input = 0, nil, nil, nil
    world, player, localId = nil, nil, nil
    Effects.clear()
    Controls.reset()
    Scoreboard.clear()
    Ball.reset()
    Flowers.reset()
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
    Arena.setLayout("yard") -- (Yardball plays on the pitch)
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

-- Info screen (updates and crashes, src/infoview.lua): long press on the build line, key I
local INFO_HOLD = 0.6 -- seconds
local versionPress = nil -- { t = when, done = opened already } while the build line is held
local function openInfo()
    Sound.play("click")
    InfoView.open()
    state = "info"
end
local function closeInfo()
    Sound.play("click")
    state = "menu"
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
    Updater.begin() -- (logs the loading steps: a crash while starting shows where)
    love.graphics.setBackgroundColor(0.05, 0.15, 0.08)
    Assets.load()
    Updater.step("assets")
    Sound.load()
    Updater.step("sound")
    Profile.load()
    Pass.load()
    Pass.refresh(true)
    Menu.load()
    love.resize()
    openMenu()
    Updater.step("done")
    -- Testing shortcuts: love . [--rowdy N] [--coins N] --host [team|waves] |
    -- --host yardball | --host king | --host hide | --host flowers |
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
            newGame(MODES[args[i + 1]] or MODES.duel, true) -- duel / team / waves / yardball / king / hide / flowers
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
        small  = love.graphics.newFont(13, "normal", dpi), -- (the info screen)
    }
end

local function hidden(e) return world:isHiddenFrom(e, player) end

-- Four teams (King of the Yard, Flower Gardens)?
local function fourTeams() return world.mode.king or world.mode.flowers end

-- Colour and name of a team as this device's player sees it: own team blue ("your
-- team"); four teams: the others red, green, yellow; else enemies red
local function teamColor(team)
    if player and team == player.team then return TEAMMATE_COLOR end
    if not fourTeams() then return ENEMY_TEAM_COLOR end
    local n = 0
    for t = 1, World.KING_TEAMS do
        if t ~= (player and player.team) then n = n + 1 end
        if t == team then return KING_COLORS[n] or ENEMY_TEAM_COLOR end
    end
    return ENEMY_TEAM_COLOR
end

local function teamName(team)
    if player and team == player.team then return "your team" end
    local n = 0
    for t = 1, World.KING_TEAMS do
        if t ~= (player and player.team) then n = n + 1 end
        if t == team then return "team " .. (KING_NAMES[n] or tostring(team)) end
    end
    return "team " .. tostring(team)
end

-- Where the camera looks: the own rowdy; King of the Yard / Hide and seek / Flower Gardens
-- while out: a team mate who is up (else anybody up)
local function focus()
    if not (player.out and (world.mode.king or world.mode.hideseek or world.mode.flowers)) then return player end
    local any
    for _, e in ipairs(world.entities) do
        if not e.dead then
            if e.team == player.team then return e end
            any = any or e
        end
    end
    return any or player
end

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
        elseif ev.kind == "blast" and ev.projectile == "book" then -- a book lands: dust
            local r = tonumber(ev.radius) or 80
            Effects.ring(ev.x, ev.y, r, { 1, 1, 1 })
            Effects.clods(ev.x, ev.y, 12, r, { 0.75, 0.68, 0.55 })
            if ev.owner ~= localId and player then Camera.shake(2) end
            Sound.play("thud", ev.x, ev.y)
        elseif ev.kind == "blast" and ev.projectile == "snowball" then -- an icy splash
            local r = tonumber(ev.radius) or 70
            Effects.ring(ev.x, ev.y, r, { 0.6, 0.85, 1 })
            Effects.ice(ev.x, ev.y, 16, r * 0.6)
            Sound.play("freeze", ev.x, ev.y)
        elseif ev.kind == "blast" and ev.projectile == "potion" then -- green slime splash
            local r = tonumber(ev.radius) or 60
            Effects.ring(ev.x, ev.y, r, { 0.45, 0.95, 0.3 })
            Effects.burst(ev.x, ev.y, { 0.4, 0.9, 0.25 }, 12)
            Sound.play("splash", ev.x, ev.y)
        elseif ev.kind == "blast" and (ev.projectile == "slam" or ev.projectile == "dirt") then
            -- a leap lands / a digger pops out: dust or dirt flies, the ground shakes
            local r = tonumber(ev.radius) or 70
            local dirt = ev.projectile == "dirt"
            Effects.ring(ev.x, ev.y, r, dirt and { 0.6, 0.42, 0.22 } or { 1, 1, 1 })
            Effects.clods(ev.x, ev.y, dirt and 18 or 10, r, dirt and { 0.5, 0.34, 0.18 } or { 0.75, 0.68, 0.55 })
            Effects.poof(ev.x, ev.y + 4)
            if player then
                local d = math.sqrt((player.x - ev.x) ^ 2 + (player.y - ev.y) ^ 2)
                if d < 450 then Camera.shake(6 * (1 - d / 450)) end
            end
            Sound.play(dirt and "pop" or "slam", ev.x, ev.y)
        elseif ev.kind == "blast" and ev.projectile == "whirl" then -- a tornado spin / gust
            local r = tonumber(ev.radius) or 90
            Effects.ring(ev.x, ev.y, r, { 0.85, 0.95, 1 })
            Effects.ring(ev.x, ev.y, r * 0.6, { 1, 1, 1 })
            for i = 1, 8 do
                local a = i / 8 * math.pi * 2
                Effects.puff(ev.x + math.cos(a) * r * 0.7, ev.y + math.sin(a) * r * 0.7)
            end
            Sound.play("whirl", ev.x, ev.y)
        elseif ev.kind == "blast" and ev.projectile == "rocket" then -- fireworks: confetti
            local r = tonumber(ev.radius) or 60
            for i, c in ipairs({ GOLD, { 1, 0.35, 0.45 }, { 0.35, 0.65, 1 }, { 0.5, 1, 0.45 } }) do
                Effects.sparks(ev.x, ev.y, 7, c, 160 + i * 50)
            end
            Effects.ring(ev.x, ev.y, r, { 1, 0.9, 0.5 })
            Sound.play("firework", ev.x, ev.y)
        elseif ev.kind == "cuff" then
            Effects.ring(ev.x, ev.y, 30, { 0.85, 0.87, 0.92 })
            Sound.play("cuff", ev.x, ev.y)
        elseif ev.kind == "gust" then
            for i = 0, 4 do
                local k = i / 4
                Effects.puff(ev.x + (ev.toX - ev.x) * k, ev.y + (ev.toY - ev.y) * k)
            end
            Sound.play("gust", ev.x, ev.y)
        elseif ev.kind == "barrier" then
            Effects.ring(ev.x, ev.y, 140, { 1, 0.85, 0.2 })
            Sound.play("barrier", ev.x, ev.y)
        elseif ev.kind == "magnet" then -- a tractor beam: blue rings pulling inwards
            Effects.ring(ev.x, ev.y, 120, { 0.4, 0.75, 1 })
            Effects.ring(ev.x, ev.y, 60, { 0.6, 0.9, 1 })
            if (tonumber(ev.n) or 0) == 0 then Sound.play("magnet", ev.x, ev.y) end
        elseif ev.kind == "blast" and ev.projectile == "boo" then -- a ghost pops up
            Effects.ring(ev.x, ev.y, tonumber(ev.radius) or 60, { 0.8, 0.92, 1 })
            Effects.poof(ev.x, ev.y)
        elseif ev.kind == "blink" then
            Effects.ring(ev.x, ev.y, 30, { 0.8, 0.92, 1 })
            Sound.play("boo", ev.x, ev.y)
        elseif ev.kind == "vanish" or ev.kind == "appear" then
            Effects.poof(ev.x, ev.y)
            Sound.play("vanish", ev.x, ev.y)
        elseif ev.kind == "grab" then
            Effects.sparks(ev.x, ev.y, 10, { 0.75, 0.45, 1 }, 200)
            if ev.victim then Sound.play("grab", ev.x, ev.y) end
        elseif ev.kind == "fling" then
            Sound.play("fling", ev.x, ev.y)
        elseif ev.kind == "bonk" then -- a flung rowdy crashes: cartoon stars
            Effects.poof(ev.x, ev.y)
            if player then
                local d = math.sqrt((player.x - ev.x) ^ 2 + (player.y - ev.y) ^ 2)
                if d < 400 then Camera.shake(5 * (1 - d / 400)) end
            end
            Sound.play("bonk", ev.x, ev.y)
        elseif ev.kind == "leap" then
            Effects.puff(ev.x, ev.y + 8)
            Sound.play("jump", ev.x, ev.y)
        elseif ev.kind == "burrow" then
            Effects.clods(ev.x, ev.y, 12, 40, { 0.5, 0.34, 0.18 })
            Sound.play("dig", ev.x, ev.y)
        elseif ev.kind == "punch" then
            Sound.play("punch", ev.x, ev.y, ev.id == localId and 0.8 or 0.6)
        elseif ev.kind == "pull" then
            Effects.ring(ev.x, ev.y, 40, { 0.9, 0.2, 0.2 })
            Sound.play("magnet", ev.x, ev.y)
        elseif ev.kind == "freeze" then -- the ice block is drawn by Rowdy:drawIce
            Effects.ice(ev.x, ev.y, 10, 18)
        elseif ev.kind == "turn" then -- a boomerang flies back
            if ev.wall then
                Effects.sparks(ev.x, ev.y, 6, { 1, 1, 0.8 }, 180)
                Sound.play("clang", ev.x, ev.y)
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
        elseif ev.kind == "kick" then -- Yardball
            Effects.puff(ev.x, ev.y)
            Sound.play("kick", ev.x, ev.y)
        elseif ev.kind == "pickup" then
            Effects.ring(ev.x, ev.y, 26, { 1, 1, 1 })
            Sound.play("pickup", ev.x, ev.y, ev.id == localId and 1 or 0.6)
        elseif ev.kind == "ballDrop" then
            Effects.puff(ev.x, ev.y)
        elseif ev.kind == "bounce" then
            Sound.play("bounce", ev.x, ev.y, 0.7)
        elseif ev.kind == "goal" then -- confetti in the goal, a cheer
            for i, c in ipairs({ GOLD, { 1, 1, 1 }, { 0.4, 0.8, 1 }, { 1, 0.45, 0.4 } }) do
                Effects.sparks(ev.x, ev.y, 10, c, 220 + i * 40)
            end
            Effects.ring(ev.x, ev.y, 90, GOLD)
            Camera.shake(4)
            Sound.play("goal")
        elseif ev.kind == "beacon" then -- King of the Yard: a heart where it was knocked out
            Effects.ring(ev.x, ev.y, 40, { 1, 0.45, 0.55 })
            Sound.play("beacon", ev.x, ev.y, 0.7)
        elseif ev.kind == "revive" then
            Effects.heal(ev.x, ev.y)
            Effects.ring(ev.x, ev.y, 60, { 0.5, 1, 0.5 })
            Effects.sparks(ev.x, ev.y, 12, { 1, 0.6, 0.7 }, 200)
            Sound.play("revive", ev.x, ev.y)
            if ev.id == localId then Scoreboard.flash("You're back!", { 0.5, 1, 0.5 }) end
        elseif ev.kind == "beaconGone" then
            Effects.poof(ev.x, ev.y)
        elseif ev.kind == "fog" then -- the fog nibbles: a small grey puff
            Effects.puff(ev.x, ev.y)
            if ev.id == localId then Sound.play("hurt", nil, nil, 0.5) end
        elseif ev.kind == "seek" then -- Hide and seek: "ready or not, here I come!"
            Sound.play("ready")
            Scoreboard.flash(ev.id == localId and "Go! Find them all!" or "Ready or not - here I come!",
                { 1, 0.82, 0.2 })
        elseif ev.kind == "tag" then
            Sound.play("shot_shovel", ev.x, ev.y)
        elseif ev.kind == "found" then
            Effects.sparks(ev.x, ev.y, 12, { 1, 0.95, 0.6 }, 220)
            local left = 0
            for _, e in ipairs(world.entities) do
                if e.team == World.TEAM_HIDERS and not e.out and e.id ~= ev.id then left = left + 1 end
            end
            if ev.id == localId then
                Scoreboard.flash("Found! Now watch the others", { 1, 0.6, 0.4 })
            elseif ev.by == localId then
                Scoreboard.flash(left == 0 and "Found them all!" or ("Found one! " .. left .. " left"), { 0.5, 1, 0.5 })
            elseif left == 1 and player and player.team == World.TEAM_HIDERS and not player.out then
                Scoreboard.flash("You're the last hider!", { 1, 0.82, 0.2 })
            end
        elseif ev.kind == "disguise" then -- (only the own team sees the leaves fly)
            local e = world:get(ev.id)
            if e and player and e.team == player.team then
                Effects.burst(ev.x, ev.y, { 0.3, 0.7, 0.3 }, 6)
                if ev.id == localId then Sound.play("rustle") end
            end
        elseif ev.kind == "pieceUp" then
            Effects.ring(ev.x, ev.y, 40, GOLD)
            Sound.play("pickup", ev.x, ev.y, ev.id == localId and 1 or 0.6)
        elseif ev.kind == "pieceDrop" then
            Effects.puff(ev.x, ev.y)
        elseif ev.kind == "piece" then
            Effects.sparks(ev.x, ev.y, 14, GOLD, 220)
            Effects.ring(ev.x, ev.y, 70, GOLD)
            Sound.play("piece")
            local n = tonumber(ev.n) or 0
            if n < 4 then
                Scoreboard.flash((ev.id == localId and "You placed a piece!" or "A picture piece is placed!")
                    .. " -" .. World.PIECE_TIME .. " s", { 1, 0.82, 0.2 })
            end
        elseif ev.kind == "picture" then -- confetti over the frame
            for i, c in ipairs({ GOLD, { 1, 1, 1 }, { 0.4, 0.8, 1 }, { 1, 0.45, 0.6 } }) do
                Effects.sparks(ev.x, ev.y, 12, c, 240 + i * 40)
            end
            Effects.ring(ev.x, ev.y, 160, GOLD)
            Sound.play("picture")
            Scoreboard.flash("The picture is complete! -" .. (World.PIECE_TIME + World.PICTURE_BONUS) .. " s",
                { 1, 0.82, 0.2 })
        elseif ev.kind == "hint" then
            Sound.play("hint")
            if player and player.team == World.TEAM_SEEKER then
                Scoreboard.flash("The hiders shimmer!", { 1, 0.95, 0.6 })
            elseif player and not player.out then
                Scoreboard.flash("You shimmer - the seeker can see you!", { 1, 0.95, 0.6 })
            end
        elseif ev.kind == "flower" then -- Flower Gardens: one grew
            Effects.ring(ev.x, ev.y, 30, { 1, 0.75, 0.85 })
        elseif ev.kind == "flowerUp" then
            Effects.ring(ev.x, ev.y, 34, { 1, 0.75, 0.85 })
            Sound.play("flower", ev.x, ev.y, ev.id == localId and 1 or 0.6)
        elseif ev.kind == "flowerDrop" then
            Effects.puff(ev.x, ev.y)
        elseif ev.kind == "deliver" then
            Effects.sparks(ev.x, ev.y, 10, { 1, 0.75, 0.85 }, 180)
            Effects.ring(ev.x, ev.y, 50, GOLD)
            local own = player and ev.team == player.team
            Sound.play("deliver", ev.x, ev.y, own and 1 or 0.6)
            local n = tonumber(ev.n) or 0
            if ev.id == localId and n > 0 then
                Scoreboard.flash("Flower home! " .. n .. " of " .. World.DOZER_FLOWERS .. " for a bulldozer", { 1, 0.75, 0.85 })
            end
        elseif ev.kind == "dozer" then
            Effects.ring(ev.x, ev.y, 70, { 1, 0.8, 0.1 })
            Effects.sparks(ev.x, ev.y, 14, GOLD, 220)
            Sound.play("dozerStart", ev.x, ev.y)
            if ev.id == localId then
                Scoreboard.flash("You get the bulldozer!", GOLD)
            elseif player and ev.team == player.team then
                Scoreboard.flash("Your team has a bulldozer!", GOLD)
            elseif player then
                local c = teamColor(ev.team)
                Scoreboard.flash(teamName(ev.team):gsub("^%l", string.upper) .. " has a bulldozer!", { c[1], c[2], c[3] })
            end
        elseif ev.kind == "dozerGone" then
            Effects.poof(ev.x, ev.y)
            if ev.id == localId then Scoreboard.flash("Your bulldozer rolled away", { 1, 0.82, 0.4 }) end
        elseif ev.kind == "fenceDown" then -- planks fly
            Effects.burst(ev.x, ev.y, { 0.97, 0.96, 0.9 }, 14)
            Effects.clods(ev.x, ev.y, 12, 70, { 0.6, 0.42, 0.25 })
            Effects.ring(ev.x, ev.y, 90, { 1, 0.85, 0.3 })
            if player then
                local d = math.sqrt((player.x - ev.x) ^ 2 + (player.y - ev.y) ^ 2)
                if d < 500 then Camera.shake(6 * (1 - d / 500)) end
            end
            Sound.play("fence", ev.x, ev.y)
            Sound.play("fence", nil, nil, 0.35) -- (everybody hears that one)
            if player and ev.team == player.team then
                Scoreboard.flash("Your fence is down!", { 1, 0.45, 0.45 })
            elseif player then
                local c = teamColor(ev.team)
                local name = teamName(ev.team)
                Scoreboard.flash(ev.by == localId and ("You knocked down " .. name .. "'s fence!")
                    or (name:gsub("^%l", string.upper) .. "'s fence is down"), { c[1], c[2], c[3] })
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
    Controls.hasSuper = player.super ~= nil and not world.mode.hideseek -- (no supers there,
        and not player.driving                                          -- nor in a bulldozer)
    Controls.superCharge = player.charge or 0
    local target = world:nearestOpponent(player, true)
    -- Yardball: carrying, the attack kicks (a tap: at the middle of the opponents' goal)
    Controls.kick = player.carrying and { min = World.KICK_MIN, max = World.KICK_MAX } or nil
    if player.carrying and Arena.goals then
        local g = Arena.goals[player.team == World.TEAM_BLUE and World.TEAM_RED or World.TEAM_BLUE]
        target = { id = "goal", x = g.x, y = (g.y1 + g.y2) / 2, kick = true }
    end
    input = Controls.get(player, target)
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
            fire = pendingFire, super = pendingSuper, hold = input.hold } }
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
    Updater.where = state .. ((state == "game" and world) and (": " .. (world.mode.name or "?")
        .. (role ~= "local" and (" (" .. tostring(role) .. ")") or "")) or "")
    Updater.update(dt)
    Menu.status = Updater.status
    -- A downloaded update is used right away if nobody is busy in the lobby. Not on
    -- Android: the moto g67 marked build 71 bad after such a restart (the restarted build
    -- never ran 3 s), there it waits for the next start.
    if versionPress and not versionPress.done and state == "menu"
        and love.timer.getTime() - versionPress.t > INFO_HOLD then
        versionPress.done = true
        openInfo()
    end
    if Updater.ready and state == "menu" and not Menu.modesOpen
        and love.system.getOS() ~= "Android" then
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
    if world and world.flowerGame and player then -- the nearest bulldozer's engine
        dozerSound = dozerSound - dt
        if dozerSound <= 0 then
            dozerSound = 0.3
            local best, bestD2
            for _, e in ipairs(world.entities) do
                local d2 = (e.x - player.x) ^ 2 + (e.y - player.y) ^ 2
                if e.driving and not e.dead and (not bestD2 or d2 < bestD2) then best, bestD2 = e, d2 end
            end
            if best then Sound.play("dozer", best.x, best.y, best.id == localId and 0.7 or 0.9) end
        end
    end
    if player and world then watchMatch() end
    if player then
        local f = focus()
        Camera.update(dt, f.x, f.y, Arena.width, Arena.height)
        Sound.setListener(f.x, f.y)
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
    for team, g in ipairs(world.ball and Arena.goals or {}) do -- Yardball: goals + ball
        local c = (team == player.team) and TEAMMATE_COLOR or ENEMY_TEAM_COLOR
        love.graphics.setColor(c)
        love.graphics.rectangle("fill", x0 + (g.dir < 0 and 0 or mw - 4), y0 + g.y1 * s, 4, (g.y2 - g.y1) * s)
    end
    love.graphics.setLineWidth(2) -- the Officer's barriers
    for _, w in ipairs(world.barriers or {}) do
        local pts = {}
        for i, v in ipairs(w.points) do pts[i] = (i % 2 == 1 and x0 or y0) + v * s end
        love.graphics.setColor(1, 0.85, 0.15, 1)
        love.graphics.line(pts)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 0.8, 0.15, 1)
    for _, b in ipairs(world.boxes) do
        love.graphics.rectangle("fill", x0 + b.x * s - 3.5, y0 + b.y * s - 3.5, 7, 7)
    end
    if world.mode.king then King.drawMinimap(world, x0, y0, s, mw, mh, uiScale(), teamColor) end
    if world.flowerGame then Flowers.drawMinimap(world, x0, y0, s, teamColor) end
    if world.hide then HideSeek.drawMinimap(world.hide, x0, y0, s) end
    -- (Hide and seek: the seeker's minimap never shows the hiders, except a shimmering hint)
    local hiders = world.hide and player.team ~= World.TEAM_HIDERS
    local hint = hiders and world.hide.hintUntil and world.hide.hintUntil > world.time
    for _, e in ipairs(world.entities) do
        if hiders and e.team == World.TEAM_HIDERS then
            if hint and not e.dead then
                love.graphics.setColor(1, 0.95, 0.6, 0.6 + 0.4 * math.sin(love.timer.getTime() * 20))
                love.graphics.circle("fill", x0 + e.x * s, y0 + e.y * s, 4.5)
            end
        elseif e ~= player and not e.dead and not hidden(e) then
            if fourTeams() then love.graphics.setColor(teamColor(e.team))
            elseif world:isOpponent(e, player) then love.graphics.setColor(0.95, 0.25, 0.25, 1)
            else love.graphics.setColor(TEAMMATE_COLOR) end
            love.graphics.circle("fill", x0 + e.x * s, y0 + e.y * s, 3.5)
        end
    end
    if not player.dead then
        love.graphics.setColor(0.3, 0.7, 1, 1)
        love.graphics.circle("fill", x0 + player.x * s, y0 + player.y * s, 3.5)
    end
    if world.ball then
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.circle("fill", x0 + world.ball.x * s, y0 + world.ball.y * s, 4.5)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.circle("fill", x0 + world.ball.x * s, y0 + world.ball.y * s, 3)
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

-- A scoreboard line's numbers: "3 knockouts   out 1 time" (Yardball: goals first, Flower
-- Gardens: flowers brought home first)
local function score(e)
    local goals = world.mode.yardball and (count(e.goals or 0, "goal") .. "   ") or ""
    if world.mode.flowers then goals = count(e.delivered or 0, "flower") .. "   " end
    return goals .. count(e.kills, "knockout") .. "   out " .. count(e.deaths, "time")
end

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
    if world.mode.hideseek then -- the seeker first, then the hiders: not found, then
        local h = world.hide or { placed = 0, pieces = {} } -- found last to found first
        local order, hiders = {}, {}
        for _, e in ipairs(world.entities) do
            if e.team == World.TEAM_HIDERS then
                hiders[#hiders + 1] = e
                if e.foundAt then order[#order + 1] = e end
            end
        end
        table.sort(order, function(a, b) return a.foundAt < b.foundAt end)
        local nth = {}
        for i, e in ipairs(order) do nth[e.id] = i end
        table.sort(hiders, function(a, b)
            local fa, fb = nth[a.id] or 99, nth[b.id] or 99
            if fa ~= fb then return fa > fb end
            return a.id < b.id
        end)
        local ord = { "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th" }
        lines = {}
        local seeker = world:get(h.seekerId)
        if seeker then
            lines[#lines + 1] = { string.format("[Seeker]  %s (%s)   found %d of %d", fullName(seeker),
                seeker.def and seeker.def.name or "?", #order, #hiders), seeker.id == localId,
                Cosmetics.get(seeker.badge, "badge") and seeker.badge }
        end
        local left = 0
        for _, e in ipairs(hiders) do
            if not nth[e.id] then left = left + 1 end
            local placed = (e.placed or 0) > 0 and ("   " .. count(e.placed, "piece") .. " placed") or ""
            lines[#lines + 1] = { string.format("[Hider]  %s (%s)   %s%s", fullName(e), e.def and e.def.name or "?",
                nth[e.id] and ("found " .. ord[nth[e.id]]) or "never found!", placed), e.id == localId,
                Cosmetics.get(e.badge, "badge") and e.badge }
        end
        info.lines = lines
        local seekerWon = m.winnerTeam == World.TEAM_SEEKER
        info.title = seekerWon and "Seeker wins!" or "Hiders win!"
        info.color = (m.winnerTeam == player.team) and { 1, 0.82, 0.1 } or { 1, 0.55, 0.3 }
        info.subtitle = (seekerWon and "All hiders found" or ("Time is up - " .. count(left, "hider")
            .. " stayed hidden")) .. "   -   picture pieces placed: "
            .. (h.placed or 0) .. " of " .. #h.pieces
    elseif world.mode.teams then
        -- scoreboard: own team first
        table.sort(list, function(a, b)
            local ma, mb = a.team == player.team, b.team == player.team
            if ma ~= mb then return ma end
            if (a.goals or 0) ~= (b.goals or 0) then return (a.goals or 0) > (b.goals or 0) end
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
        local fg = world.flowerGame
        if fourTeams() then -- teams by place: the own one rowdy by rowdy, the others
            local place = m.place or {}  -- in one line each (12 lines wouldn't fit)
            local nth = { "1st", "2nd", "3rd", "4th" }
            local teams = {}
            for t = 1, World.KING_TEAMS do teams[t] = t end
            table.sort(teams, function(a, b)
                local pa, pb = place[a] or 9, place[b] or 9
                if pa ~= pb then return pa < pb end
                return a < b
            end)
            lines = {}
            for _, t in ipairs(teams) do
                local where = nth[place[t]] and (nth[place[t]] .. " place") or "?"
                if t == player.team then
                    for _, e in ipairs(list) do
                        if e.team == t then
                            lines[#lines + 1] = { string.format("[Your team, %s]  %s (%s)   %s", where,
                                fullName(e), e.def and e.def.name or "?", score(e)), e.id == localId,
                                Cosmetics.get(e.badge, "badge") and e.badge }
                        end
                    end
                else
                    local kills, names = 0, {}
                    for _, e in ipairs(list) do
                        if e.team == t then
                            kills = kills + e.kills
                            names[#names + 1] = e.isBot and e.def.name or (nameOf(e) .. ": " .. e.def.name)
                        end
                    end
                    local name = teamName(t)
                    local what = count(kills, "knockout")
                    if fg then -- (Flower Gardens: the flowers and the fence)
                        what = count(fg.teams[t].delivered, "flower") .. (fg.fences[t] and "" or ", fence down")
                    end
                    lines[#lines + 1] = { string.format("[%s, %s]  %s   (%s)", name:sub(1, 1):upper() .. name:sub(2),
                        where, what, table.concat(names, ", ")), false }
                end
            end
            info.lines = lines
        end
        if fg then -- Flower Gardens: by place; the time is up = the most flowers won
            local own = m.place and m.place[player.team]
            local nth = { "1st", "2nd", "3rd", "4th" }
            local timeUp = m.timeLeft and m.timeLeft <= 0
            local function flowersOf(t) return fg.teams[t] and fg.teams[t].delivered or 0 end
            if not m.winnerTeam then
                local most = 0
                for t = 1, World.KING_TEAMS do most = math.max(most, flowersOf(t)) end
                info.title, info.color = "Draw", { 1, 1, 1 }
                info.subtitle = "Time is up - the best teams brought " .. count(most, "flower") .. " home each"
            elseif m.winnerTeam == player.team then
                info.title, info.color = "Victory!", { 1, 0.82, 0.1 }
                info.subtitle = timeUp and ("Time is up - your team brought the most flowers home ("
                    .. flowersOf(player.team) .. ")") or "Your team is the last team standing!"
            else
                info.title, info.color = (nth[own] or "?") .. " place", own == 2 and { 0.8, 0.85, 0.95 } or { 1, 0.55, 0.3 }
                local winner = teamName(m.winnerTeam):gsub("^%l", string.upper)
                info.subtitle = "Your team came " .. (nth[own] or "?") .. " of " .. World.KING_TEAMS .. "   -   "
                    .. winner .. (timeUp and (" brought the most flowers home (" .. flowersOf(m.winnerTeam) .. ")")
                    or " is the last team standing")
            end
        elseif world.mode.king and m.winnerTeam ~= player.team then
            local own = m.place and m.place[player.team]
            local nth = { "1st", "2nd", "3rd", "4th" }
            if not m.winnerTeam then
                info.title, info.color = "Draw", { 1, 1, 1 }
            else
                info.title, info.color = (nth[own] or "?") .. " place", own == 2 and { 0.8, 0.85, 0.95 } or { 1, 0.55, 0.3 }
            end
            info.subtitle = "Your team came " .. (nth[own] or "?") .. " of " .. World.KING_TEAMS
                .. (m.winnerTeam and ("   -   " .. teamName(m.winnerTeam):gsub("^%l", string.upper) .. " is King of the Yard") or "")
        elseif world.mode.king then
            info.title, info.color = "Victory!", { 1, 0.82, 0.1 }
            info.subtitle = "Your team is King of the Yard - the last team standing!"
        elseif not m.winnerTeam then
            info.title, info.color = "Draw", { 1, 1, 1 }
        elseif m.winnerTeam == player.team then
            info.title, info.color = "Victory!", { 1, 0.82, 0.1 }
        else
            info.title, info.color = "Defeat", { 1, 0.35, 0.3 }
        end
        if fourTeams() then -- (subtitle: above)
        elseif world.mode.yardball then -- (always a winner: no time limit)
            local g = m.goals or { 0, 0 }
            local own = g[player.team] or 0
            info.subtitle = (m.winnerTeam == player.team and "Your team scored " or "The enemies scored ")
                .. World.YARDBALL_GOALS .. " goals   -   Your team " .. own .. " : "
                .. ((g[1] or 0) + (g[2] or 0) - own) .. " Enemies"
        else
            local s = world:teamScores()
            local own, other = s[player.team] or 0, 0
            for team, k in pairs(s) do if team ~= player.team then other = other + k end end
            info.subtitle = ((m.timeLeft and m.timeLeft <= 0) and "Time is up" or "Knockout target reached")
                .. "   -   Your team " .. own .. " : " .. other .. " Enemies"
        end
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
    if world.hide then -- Hide and seek: hiders left, the clock, the picture
        local h = world.hide
        local left, all = 0, 0
        for _, e in ipairs(world.entities) do
            if e.team == World.TEAM_HIDERS then
                all = all + 1
                if not e.out then left = left + 1 end
            end
        end
        local hiding = h.phase == "hide" and math.max(0, h.hideUntil - world.time) or nil
        return { kind = "hide", hiding = hiding, timeLeft = math.max(0, h.endAt - world.time),
                 left = left, hiders = all, placed = h.placed or 0, pieces = #h.pieces,
                 seeker = h.seekerId == localId }
    end
    local fg = world.flowerGame
    if fg then -- Flower Gardens: the teams (own first) with their flowers and fences, the clock
        local up = {}
        for _, e in ipairs(world.entities) do
            if not e.out then up[e.team] = true end
        end
        local function entry(t, name, color)
            local tm = fg.teams[t] or { count = 0, delivered = 0 }
            return { name = name, color = color, delivered = tm.delivered, count = tm.count,
                     fence = fg.fences[t], out = not up[t] }
        end
        local teams = { entry(player.team, "YOURS", TEAMMATE_COLOR) }
        for t = 1, World.KING_TEAMS do
            if t ~= player.team then teams[#teams + 1] = entry(t, teamName(t):sub(6):upper(), teamColor(t)) end
        end
        return { kind = "flowers", teams = teams, timeLeft = math.max(0, (fg.endAt or 0) - world.time),
                 need = World.DOZER_FLOWERS }
    end
    if world.mode.king then -- the teams (own first) and the fog
        local up = {}
        for _, e in ipairs(world.entities) do
            if not e.out then up[e.team] = (up[e.team] or 0) + 1 end
        end
        local teams = { { name = "YOURS", color = TEAMMATE_COLOR, up = up[player.team] or 0 } }
        for t = 1, World.KING_TEAMS do
            if t ~= player.team then
                teams[#teams + 1] = { name = teamName(t):sub(6):upper(), color = teamColor(t), up = up[t] or 0 }
            end
        end
        local z = world.zone
        local fogIn = z and z.startAt and world.time < z.startAt and (z.startAt - world.time) or nil
        if not z then fogIn = World.ZONE_WAIT end
        return { kind = "king", teams = teams, fogIn = fogIn,
                 closed = z and z.r and z.r <= 0 }
    end
    local info = { kind = "versus", timeLeft = m.timeLeft }
    if world.mode.yardball then -- goals, no timer
        local g = m.goals or { 0, 0 }
        local own = g[player.team] or 0
        info.left = { name = "YOUR TEAM", score = own, color = TEAMMATE_COLOR }
        info.right = { name = "ENEMIES", score = (g[1] or 0) + (g[2] or 0) - own, color = ENEMY_TEAM_COLOR }
        info.target, info.goals = World.YARDBALL_GOALS, true
        return info
    end
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
    elseif world.hide then -- Hide and seek: the countdown ticks, time marks
        local info = scoreboardInfo()
        now.count = info.hiding and math.ceil(info.hiding)
        if now.count and now.count ~= watch.count and now.count <= 5 and now.count > 0 then Sound.play("tick") end
        now.time = not info.hiding and info.timeLeft or nil
        for _, mark in ipairs({ { 60, "1 minute left" }, { 30, "30 seconds left!" }, { 10, "10 seconds!" } }) do
            if watch.time and now.time and watch.time > mark[1] and now.time <= mark[1] then
                Scoreboard.flash(mark[2], mark[1] <= 30 and { 1, 0.45, 0.45 } or nil)
            end
        end
    elseif world.flowerGame then -- Flower Gardens: teams out, the last two, time marks
        now.left, now.out = 0, {}
        for t = 1, World.KING_TEAMS do
            now.out[t] = not world:teamUp(t)
            if not now.out[t] then now.left = now.left + 1 end
        end
        if watch.out then
            for t = 1, World.KING_TEAMS do
                if now.out[t] and not watch.out[t] and now.left >= 1 then
                    if t == player.team then Scoreboard.flash("Your team is out", { 1, 0.45, 0.45 })
                    else
                        local c = teamColor(t)
                        Scoreboard.flash(teamName(t):gsub("^%l", string.upper) .. " is out", { c[1], c[2], c[3] })
                    end
                end
            end
            if now.left == 2 and watch.left > 2 and not now.out[player.team] then
                Scoreboard.flash("Last two teams!", { 1, 0.82, 0.1 })
            end
        end
        now.time = math.max(0, (world.flowerGame.endAt or 0) - world.time)
        for _, mark in ipairs({ { 60, "1 minute left" }, { 30, "30 seconds left!" }, { 10, "10 seconds!" } }) do
            if watch.time and watch.time > mark[1] and now.time <= mark[1] then
                Scoreboard.flash(mark[2], mark[1] <= 30 and { 1, 0.45, 0.45 } or nil)
            end
        end
    elseif world.mode.king then
        local info = scoreboardInfo()
        now.left, now.out = 0, {}
        for t = 1, World.KING_TEAMS do
            now.out[t] = not world:teamUp(t)
            if not now.out[t] then now.left = now.left + 1 end
        end
        if watch.out then
            for t = 1, World.KING_TEAMS do
                if now.out[t] and not watch.out[t] and now.left >= 1 then
                    if t == player.team then Scoreboard.flash("Your team is out", { 1, 0.45, 0.45 })
                    else
                        local c = teamColor(t)
                        Scoreboard.flash(teamName(t):gsub("^%l", string.upper) .. " is out", { c[1], c[2], c[3] })
                    end
                end
            end
            if now.left == 2 and watch.left > 2 and not now.out[player.team] then
                Scoreboard.flash("Last two teams!", { 1, 0.82, 0.1 })
            end
        end
        now.closing = info.fogIn == nil
        if now.closing and watch.closing == false then
            Scoreboard.flash("The fog is closing in!", { 0.85, 0.88, 0.95 })
            Sound.play("fog")
        end
    elseif world.mode.yardball then
        local info = scoreboardInfo()
        now.left, now.right = info.left.score, info.right.score
        local need = info.target - now.left
        if watch.left and now.left > watch.left then
            Scoreboard.flash(need == 1 and "GOAL! 1 more to win!" or "GOAL!", { 0.5, 1, 0.5 })
        elseif watch.right and now.right > watch.right then
            Scoreboard.flash(info.target - now.right == 1 and "The enemies scored - they need 1 more"
                or "The enemies scored", { 1, 0.45, 0.45 })
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
    if player.super and not Controls.touchMode and not world.mode.hideseek then
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
    local hide = world.hide
    if world.match.over then
        -- the result screen says it all
    elseif hide then -- Hide and seek
        local text
        local seeker = hide.seekerId == localId
        if player.out then
            text = "Found! Watching the others"
        elseif hide.phase == "hide" then
            text = not seeker and string.format("Hide! The seeker comes in %d - stand still to turn into a bush",
                math.max(0, math.ceil(hide.hideUntil - world.time))) or nil
        elseif seeker then
            text = (Controls.touchMode and "You seek! Use the attack stick to tag the hiders"
                or "You seek! Click to tag the hiders") .. " - look for bushes where none belong"
        elseif player.carryingPiece then
            text = "Bring the piece to the picture frame in the middle!"
        elseif player.disguised then
            text = "You're a bush - don't move!"
        else
            text = "Stand still to turn into a bush - or bring a picture piece to the frame"
        end
        if text then love.graphics.printf(text, 0, y, sw, "center") end
    elseif world.flowerGame then -- Flower Gardens
        local fg = world.flowerGame
        local text
        if player.out then
            text = world:teamUp(player.team) and "You're out - your fence is down. Watching your team"
                or "Your team is out - watching the others"
        elseif player.dead then
            text = string.format("You're out - back in your garden in %.1f", math.max(0, player.respawnTimer))
        elseif player.driving then
            text = string.format("You drive the bulldozer - knock down a fence! (%d)",
                math.max(0, math.ceil((player.driving.expires or world.time) - world.time)))
        elseif player.carryingFlower then
            text = "Bring the flower home to your garden!"
        elseif not fg.fences[player.team] then
            text = "Your fence is down - no more respawns"
        elseif (fg.endAt or 0) - world.time > World.FLOWER_TIME - 12 then
            text = "Pick flowers in the middle and bring them home - " .. World.DOZER_FLOWERS .. " = a bulldozer"
        end
        if text then love.graphics.printf(text, 0, y, sw, "center") end
    elseif player.out and world.mode.king then
        local heart
        for _, h in ipairs(world.beacons or {}) do
            if h.owner == localId then heart = h end
        end
        love.graphics.printf(heart and string.format("You're out - a team mate can bring you back at your heart (%d)",
            math.max(0, math.ceil(heart.expires - world.time)))
            or (world:teamUp(player.team) and "Watching your team" or "Your team is out - watching the others"),
            0, y, sw, "center")
    elseif player.out then
        love.graphics.printf("Out of lives - watching your team", 0, y, sw, "center")
    elseif player.dead then
        love.graphics.printf(string.format("You're out - back in %.1f",
            math.max(0, player.respawnTimer)), 0, y, sw, "center")
    elseif world.ball and (world.kickoff or 0) > 0 then
        love.graphics.printf("Kick-off!", 0, y, sw, "center")
    elseif player.carrying then
        love.graphics.printf(Controls.touchMode and "You have the ball - the attack stick kicks it"
            or "You have the ball - click to kick it", 0, y, sw, "center")
    elseif world.mode.king and world.zone and not world:inZone(player.x, player.y) then
        love.graphics.printf("You're in the fog - get back into the clear circle!", 0, y, sw, "center")
    elseif world.mode.king and #(world.beacons or {}) > 0 then -- a team mate is out
        for _, h in ipairs(world.beacons) do
            if h.team == player.team then
                love.graphics.printf("Stand on your team mate's heart to bring them back", 0, y, sw, "center")
                break
            end
        end
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
        elseif e.boss or e.isBot then e.hudColor = BOT_COLOR -- its rowdy's own bar may be green
        else e.hudColor = OPPONENT_COLOR end
        e.teamColor = world.mode.teams and (ally and TEAMMATE_COLOR or ENEMY_TEAM_COLOR) or nil
        if fourTeams() and e ~= player then e.hudColor, e.teamColor = teamColor(e.team), teamColor(e.team) end
        e.noBars = world.mode.hideseek or nil -- (no HP, ammo or super there)
    end
    local hide = world.hide -- (Hide and seek)

    -- World (moves with the camera)
    Camera.attach()
    Arena.drawBelow()
    if hide then HideSeek.drawFrame(hide, world.time, World.pieceSlot) end
    local fg = world.flowerGame -- (Flower Gardens)
    for t, g in ipairs(fg and Arena.gardens or {}) do
        Flowers.drawGarden(g, teamColor(t), fg.teams[t] and fg.teams[t].delivered or 0)
    end
    local ball = world.ball -- (Yardball)
    if ball then
        Ball.drawGoals({ [player.team] = TEAMMATE_COLOR,
            [player.team == World.TEAM_BLUE and World.TEAM_RED or World.TEAM_BLUE] = ENEMY_TEAM_COLOR })
    end
    if hide then -- only the seeker aims: its tag swing
        if input and input.aiming and not player.dead and hide.seekerId == localId and hide.phase == "seek" then
            HideSeek.drawTagAim(player, World.TAG)
        end
    elseif input and not player.dead and not player.driving then
        if input.aimingSuper and player.super then player:drawAim(true)
        elseif input.aiming and player.carrying then Ball.drawKickAim(player, input.aimDist)
        elseif input.aiming then player:drawAim() end
    end
    for _, m in ipairs(world.medpacks) do Medpack.draw(m, world.time) end
    for _, c in ipairs(world.coins) do Loot.drawGroundCoin(c, world.time) end
    for _, b in ipairs(world.boxes) do Loot.drawBox(b, world.time) end
    for _, w in ipairs(world.barriers or {}) do Barrier.draw(w, world.time, teamColor(w.team)) end
    for _, h in ipairs(world.beacons or {}) do King.drawBeacon(h, world.time, teamColor(h.team)) end
    for _, p in ipairs(hide and hide.pieces or {}) do
        if not p.placed and not p.carrier then HideSeek.drawGroundPiece(p, world.time) end
    end
    for t, g in ipairs(fg and Arena.gardens or {}) do Flowers.drawFence(g, teamColor(t), fg.fences[t]) end
    for _, f in ipairs(fg and fg.flowers or {}) do
        if not f.carrier then Flowers.drawFlower(f, world.time) end
    end
    Effects.drawBelow()
    if ball and not ball.carrier then Ball.draw(ball, world.kickoff) end -- (rowdies walk over it)
    for _, b in ipairs(world.bullets) do b:draw() end
    for _, e in ipairs(world.entities) do
        -- (underground opponents are hidden, but their dirt mound shows; a disguised
        -- hider is a bush for the seeker, its team mates see it with a leaf)
        if e ~= player and (not hidden(e) or e.burrowed) then
            if e.disguised and world:isOpponent(e, player) then HideSeek.drawDisguise(e, 1)
            else
                if e.driving and not e.dead then Flowers.drawDozer(e, teamColor(e.team), world.time) end
                e:draw()
                if e.disguised then HideSeek.drawLeaf(e) end
            end
        end
    end
    if player.driving and not player.dead then Flowers.drawDozer(player, TEAMMATE_COLOR, world.time) end
    player:draw() -- own rowdy on top
    if player.disguised and not player.dead then HideSeek.drawDisguise(player, 0.6) end
    if ball and ball.carrier then Ball.draw(ball) end -- in the carrier's hands
    for _, p in ipairs(hide and hide.pieces or {}) do -- held up over the carrier's head
        local c = p.carrier and world:get(p.carrier)
        if c and not c.dead then HideSeek.drawCarriedPiece(p, c) end
    end
    for _, f in ipairs(fg and fg.flowers or {}) do
        local c = f.carrier and world:get(f.carrier)
        if c and not c.dead and (c == player or not hidden(c)) then Flowers.drawCarried(f, c, world.time) end
    end
    Effects.drawAbove()
    Arena.drawBushes(player)
    if hide and hide.hintUntil and hide.hintUntil > world.time then -- the hint: through bushes too
        for _, e in ipairs(world.entities) do
            if e.team == World.TEAM_HIDERS and not e.dead then HideSeek.drawShimmer(e, love.timer.getTime()) end
        end
    end
    local seeker = hide and world:get(hide.seekerId)
    if seeker and hide.phase == "hide" and not seeker.dead then
        HideSeek.drawCounting(seeker, math.max(0, math.ceil(hide.hideUntil - world.time)), boardFonts.big)
    end
    if world.zone then King.drawFog(world.zone, love.timer.getTime()) end
    Camera.detach()

    -- Virtual sticks + super button (touch only)
    if playing() then Controls.draw() end
    if not world.match.over then drawHud() end -- the result screen shows the scores
    if seeker and seeker.id == localId and hide.phase == "hide" and not world.match.over then
        local ui = uiScale() -- the seeker's eyes are closed while the hiders hide
        love.graphics.push()
        love.graphics.scale(ui)
        HideSeek.drawCover(menuFonts, love.graphics.getWidth() / ui, love.graphics.getHeight() / ui,
            hide.hideUntil - world.time, love.timer.getTime())
        love.graphics.pop()
    end
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
        if state == "menu" or state == "info" then Menu.draw(menuFonts, Controls.touchMode) end
        if state == "menu" then -- (drawn above)
        elseif state == "info" then InfoView.draw(menuFonts)
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

local drawnOnce = false
function love.draw()
    drawScreen()
    drawMuteButton()
    if not drawnOnce then
        drawnOnce = true
        Updater.step("first frame")
    end
end

-- Menus, rowdy choice, join screen, result screen: taps and clicks
local function press(x, y)
    if state == "menu" then
        menuAction(Menu.hit(x, y))
    elseif state == "info" then
        if InfoView.hit(x, y) == "back" then closeInfo() end
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
    if state == "info" then InfoView.touchStart() end
    if state == "menu" and Menu.hit(x, y) == "version" then versionPress = { t = love.timer.getTime() } end
    if playing() then Controls.touchpressed(id, x, y) end
end
function love.touchmoved(id, x, y, dx, dy)
    if id == muteTouch then return end
    if state == "pick" then Picker.drag(dy) end
    if state == "pass" then PassView.drag(dx) end
    if state == "info" then InfoView.drag(dy) end
    if playing() then Controls.touchmoved(id, x, y) end
end
function love.touchreleased(id, x, y)
    if id == muteTouch then muteTouch = nil return end
    local held = versionPress and versionPress.done
    versionPress = nil
    if playing() then Controls.touchreleased(id, x, y)
    elseif held then Controls.touchMode = true -- the long press opened the info screen
    elseif state == "info" and InfoView.dragged then Controls.touchMode = true
    elseif state == "pick" and Picker.dragged then Controls.touchMode = true -- scrolled
    elseif state == "pass" and PassView.dragged then Controls.touchMode = true
    else Controls.touchMode = true; press(x, y) end
end

-- Mouse (touches also arrive here as emulated mouse events: skip those)
function love.mousepressed(x, y, button, istouch)
    if state == "menu" and button == 1 and not istouch and Menu.hit(x, y) == "version" then
        versionPress = { t = love.timer.getTime() }
    end
end
function love.mousereleased(x, y, button, istouch)
    if istouch then return end
    local held = versionPress and versionPress.done
    versionPress = nil
    if not playing() and button == 1 and not held then press(x, y) end
end
function love.mousemoved(x, y, dx, dy, istouch)
    if state == "menu" and not istouch then
        Menu.mousemoved(x, y)
    end
end

function love.wheelmoved(x, y)
    if state == "pick" then Picker.wheel(y) end
    if state == "pass" then PassView.wheel(x, y) end
    if state == "info" then InfoView.wheel(y) end
end

function love.textinput(t)
    if state == "join" then Join.textinput(t) end
end

-- M: sound on/off. Escape (= Android back button): game/join -> menu, rowdy choice, pass
-- and style screens -> back, menu -> quit
function love.keypressed(key)
    if key == "m" and state ~= "join" then Sound.toggleMute() return end
    if state == "info" then
        if InfoView.keypressed(key) == "back" then closeInfo() end
        return
    end
    if state == "menu" and key == "i" and not (Menu.modesOpen or Menu.bossOpen) then
        openInfo()
        return
    end
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
    Updater.quit()
end
