-- The simulation: all rowdies (players + bots) with ids and teams, bullets, hits,
-- scores and the game mode (duel / team fight / waves / boss fight / Yardball / King of
-- the Yard / Hide and seek / Flower Gardens). It runs in fixed steps of World.TICK.
--
-- No input devices, rendering, camera or particles in here: players are driven by
-- input tables (src/controls.lua format), and everything worth showing is pushed as
-- an event to world.events (see World:emit). The same code can later run headless on
-- a server, with clients only drawing what it sends.
local Arena    = require("src.arena")
local Assets   = require("src.assets")
local Rowdies = require("src.rowdies")
local Bullet   = require("src.bullet")
local Enemy    = require("src.enemy")
local Player   = require("src.player")

local World = {}
World.__index = World

World.TICK        = 1 / 60 -- seconds per simulation step
World.MAX_BOTS    = 64     -- safety cap for the wave size
World.HIDE_REVEAL = 150    -- an opponent in a bush is only visible this close
World.TEAM_PLAYERS, World.TEAM_BOTS = 1, 2
-- Team fight: blue (left side) against red (right side); bots fill both teams
World.TEAM_BLUE, World.TEAM_RED = 1, 2
World.TEAM_SIZE = 3

-- Medpacks: a rowdy defeated by a player drops one (a reward for the winner - bots
-- can't pick them up, so their kills drop nothing); a hurt player walking over it heals
World.MEDPACK_HEAL   = 0.4 -- share of the picker's max HP
World.MEDPACK_LIFE   = 15  -- seconds until it disappears (blinks before, see main.lua)
local MEDPACK_REACH  = 24  -- picked up within rowdy radius + this
local MAX_MEDPACKS   = 24

-- Loot boxes: one appears at a random free spot every BOX_EVERY seconds (BOX_FIRST
-- after the round starts, at most MAX_BOXES at a time). They block bullets and rowdies;
-- anybody's bullets break them (bots' too), and a broken box scatters BOX_COINS coins
-- that only players pick up. The world doesn't keep anybody's money: a "coin" event
-- tells that player's device to add it (src/profile.lua).
World.BOX_HP     = 120
World.BOX_HALF   = 22   -- half the side of the (square) box, px
World.BOX_FIRST  = 8    -- seconds
World.BOX_EVERY  = 20
World.BOX_COINS  = 4
World.COIN_VALUE = 5
World.COIN_LIFE  = 12   -- seconds until a coin disappears (blinks before)
local MAX_BOXES  = 3
local COIN_REACH = 20   -- picked up within rowdy radius + this
local BOX_MIN_DIST = 160 -- a box never appears this close to a rowdy (or 2x to a box)

-- Rounds. Duel: first to KILL_TARGET kills wins, or most kills when the time is up.
-- Team fight: the same with the kills of each team (TEAM_KILL_TARGET).
-- Waves: every player has LIVES; the round ends when all players are out.
World.KILL_TARGET = 10
World.TEAM_KILL_TARGET = 15
World.TIME_LIMIT  = 180 -- seconds
World.LIVES       = 3

-- Boss fight (mode.boss = index of a rowdy in src/rowdies.lua): the players (together)
-- against one big bot with that rowdy's look, attacks and super and BOSS_HP times its
-- HP. Nobody can lose (CHARTER.md): players pop back in as often as they need, the
-- boss never heals or respawns, there is no time limit; the round ends when it is out.
World.BOSS_HP   = 3
World.BOSS_SIZE = 1.4 -- drawn and hit this much bigger

-- Yardball (mode.yardball, a team fight with a ball on the "pitch" layout, see
-- src/arena.lua): the ball starts in the middle; a rowdy that walks over it carries it
-- (in front of it) and kicks it with the attack button (no attacks while carrying, the
-- super still works) - as far as it aims (KICK_MIN..KICK_MAX from its body centre).
-- A rolling ball bounces off walls, crates, chests and the border, except at the goal
-- mouths: reaching the back of a goal (rolling or carried) scores for the other team
-- (own goals count). Anybody who touches a free ball takes it (passes, interceptions,
-- goalkeeping); the kicker only after PICKUP_DELAY. A carrier that is knocked out,
-- frozen, grabbed, digs in or vanishes drops it. After a goal everybody goes back to
-- their spot and the ball to the middle (nobody can take it for KICKOFF_DELAY). First
-- team to YARDBALL_GOALS goals wins; no time limit.
World.YARDBALL_GOALS = 2
World.BALL_RADIUS    = 14
World.BALL_FRICTION  = 620 -- px/s^2: how fast a rolling ball slows down
World.KICK_MIN, World.KICK_MAX = 120, 650
World.KICKOFF_DELAY  = 1.5
local PICKUP_DELAY   = 0.4
local BALL_BOUNCE    = 0.6 -- share of the speed a ball keeps when it bounces
local CARRIER_BONUS  = 700 -- px: bots go after the ball carrier as if it were this much nearer
local BOT_SHOT_RANGE = 520 -- px: a bot with the ball shoots at the goal from this close
local BOT_THREAT     = 120 -- px: ...or from farther when an opponent is this close

-- King of the Yard (mode.king, also `teams`; on the big "kingdom" layout, see
-- src/arena.lua): KING_TEAMS teams of TEAM_SIZE start in the corners (bots fill them).
-- Nobody pops back in by themselves: a knocked-out rowdy is `out` and leaves a heart
-- beacon; a team mate standing on it for REVIVE_TIME brings it back there (with
-- REVIVE_HP of its HP) - within BEACON_LIFE seconds, after that it stays out. A team is
-- eliminated when none of it is up; the last team with somebody up wins. A fog (harmless
-- grey cloud, CHARTER.md) closes in to keep the rounds short: the whole map is clear for
-- ZONE_WAIT s, then the clear circle shrinks to ZONE_MIN over ZONE_SHRINK s, stays
-- ZONE_HOLD s and then closes completely over ZONE_FINAL s (so every round ends).
-- Outside it a rowdy loses ZONE_DAMAGE HP per second (a knockout there counts for nobody).
World.KING_TEAMS   = 4
World.REVIVE_TIME  = 2
World.REVIVE_HP    = 0.5
World.BEACON_LIFE  = 20
World.BEACON_REACH = 34  -- px: a team mate within its radius + this stands on the heart
World.ZONE_WAIT    = 15
World.ZONE_SHRINK  = 90
World.ZONE_MIN     = 350
World.ZONE_HOLD    = 20
World.ZONE_FINAL   = 30
World.ZONE_DAMAGE  = 12
local ZONE_TICK    = 0.5 -- s between two fog nibbles
local ZONE_SHIFT   = 250 -- px: the circle's final centre is up to this far from the middle

-- Hide and seek (mode.hideseek, also `teams`; on the "hideout" layout, see
-- src/arena.lua): HIDE_PLAYERS rowdies (bots fill the free places); one of them, picked
-- at random every round, seeks (team TEAM_SEEKER), the others hide (TEAM_HIDERS). The
-- rowdies' stats don't matter: everybody walks at HIDER_SPEED / SEEKER_SPEED, nobody
-- attacks or uses a super. The hiders get HIDE_TIME s while the seeker stands in the
-- middle with its screen covered, then it has SEEK_TIME s to find them all: its attack
-- button swings TAG (like a shovel swing, every TAG_COOLDOWN s); one hit = found (a
-- "poof", out for the rest of the round - CHARTER.md: a cartoon tag game). A hider that
-- stands still for DISGUISE_TIME turns into a bush (drawn as one for the seeker; moving
-- ends it). From HINT_AFTER s of seeking on, all hiders shimmer for HINT_LENGTH s every
-- HINT_EVERY s, so rounds don't drag. The picture puzzle: the pieces lie on the map
-- (Arena.pieceSpots); a hider that walks over one while the seeker seeks carries it
-- (no disguise then, and a bush doesn't hide it) to the frame in the middle: PIECE_TIME s
-- off the clock, PICTURE_BONUS s more when all are placed. Found while carrying = the
-- piece drops there. All found = the seeker wins; the clock runs out = the hiders win.
World.TEAM_SEEKER, World.TEAM_HIDERS = 1, 2
World.HIDE_PLAYERS  = 6
World.HIDE_TIME     = 15
World.SEEK_TIME     = 180
World.HINT_AFTER    = 120
World.HINT_EVERY    = 20
World.HINT_LENGTH   = 1
World.DISGUISE_TIME = 2
World.HIDER_SPEED   = 240
World.SEEKER_SPEED  = 255
World.PIECE_TIME    = 20
World.PICTURE_BONUS = 20
World.PIECE_REACH   = 24  -- px: a hider within its radius + this picks a piece up
World.FRAME_REACH   = 30  -- px: ...and places it this close to the frame
World.TAG_COOLDOWN  = 0.6
World.TAG = { damage = 0, range = 70, radius = 30, wallRadius = 8, pierce = true,
    bulletSpeed = 750, projectile = "swing" }
local HIDE_SPAWN_R  = 260  -- px: the hiders start on a circle this big around the frame
-- Hide and seek bots (World:hidePlan)
local FLEE_DIST     = 400  -- px: a hider runs from a seeker in sight this close...
local BOLT_DIST     = 130  -- px: ...a disguised one only when it comes this close
local FETCH_SAFE    = 900  -- px: a hider fetches a piece only when the seeker is farther (or out of sight)
local FETCH_SHARE   = 0.5  -- share of the hider bots that fetch pieces at all
local SEEK_SIGHT    = 650  -- px: the seeker bot sees an undisguised hider this far
local NOTICE_DIST   = 230  -- px: ...notices a "bush" that is a hider this close
local NOTICE_RATE   = 1.2  -- ...with this chance per second
local TAG_REACH     = 95   -- px: the seeker bot swings at a hider this close
local GIVE_UP       = 4    -- s: a bot that got no closer to where it walks picks another goal

-- Flower Gardens (mode.flowers, also `teams`; on the "gardens" layout, see
-- src/arena.lua): KING_TEAMS teams of TEAM_SIZE, each with a fenced garden in a corner
-- (Arena.gardens) where it starts and pops back in. The fence lets the own team through
-- (walking and shooting); other teams are pushed out, their shots and beams stop at it
-- and their bombs and blasts don't reach anybody inside (a safe spawn). Flowers grow in
-- the middle: up to FLOWER_MAX, one every FLOWER_EVERY s within FLOWER_FIELD px of the
-- centre. A rowdy that walks over one carries it (one at a time; knocked out = it drops
-- there), walking into the own garden delivers it. Every DOZER_FLOWERS delivered flowers
-- the one who brought the last drives a toy bulldozer: can't be hurt or pushed, no
-- attacks, DOZER_SPEED; driving into another team's fence knocks it down (the bulldozer
-- is gone then; unused it rolls away after DOZER_TIME s - CHARTER.md: no endless
-- invulnerability). Knocked out while the own fence is down = out for the round. A team
-- is out when its fence is down and nobody of it is up; the last team wins, or after
-- FLOWER_TIME s the team (still up) with the most flowers delivered - a tie between the
-- leaders is a draw.
World.FLOWER_TIME   = 240
World.FLOWER_MAX    = 8
World.FLOWER_EVERY  = 6
World.FLOWER_START  = 4    -- flowers already there when the round starts
World.FLOWER_FIELD  = 600
World.FLOWER_REACH  = 20   -- px: picked up within the rowdy's radius + this
World.DOZER_FLOWERS = 5
World.DOZER_SPEED   = 150
World.DOZER_TIME    = 40
World.FENCE_HALF    = 8    -- px: half the fence's thickness
local FLOWER_GAP    = 70   -- px: a new flower doesn't grow closer than this to another
local FLOWER_NOTICE = 900  -- px: a hunting bot goes after an opponent's flower carrier this close
local FLOWER_FIGHT  = 300  -- px: a fetching bot first fights an opponent in sight this close
local FLOWER_CARRIER_BONUS = 400 -- px: bots go after a flower carrier as if it were this much nearer
local DOZER_AIM     = 400  -- px: a bot's bulldozer heads for the fence's corner until this close

World.PULL_SPEED = 900 -- px/s: a rowdy hit by a pull attack flies to the puller
World.GOO_TIME   = 2   -- s: sticky goo (attack.goo) does its extra damage over this long
local GOO_TICK   = 0.5 -- s between two goo stings

-- Barriers (attack kind "barrier", the Officer): a curved fence in front of the rowdy
-- for `duration` seconds. Opponents can't walk or shoot through it (bombs fly over,
-- beams stop at it); the own team passes.
World.BARRIER_DIST   = 130  -- px from the rowdy to the middle of the fence
World.BARRIER_ANGLE  = 1.5  -- radians the arc spans
World.BARRIER_HALF   = 9    -- px: half its thickness
local BARRIER_POINTS = 7

-- Bots (duel opponent, team fight bots, waves) are random rowdies of src/rowdies.lua,
-- picked when they are created (they keep it for the round, respawns too), a bit
-- weaker than a player's rowdy - fair for young players. Bosses are not handicapped.
World.BOT_DAMAGE = 0.75 -- share of the damage a bot deals (super charge too)
World.BOT_SPEED  = 0.8  -- share of its rowdy's walking speed
World.BOT_CHARGE = 0.6  -- its super meter fills this much slower
local TARGET_CROWD = 250 -- px: a bot prefers an opponent fewer other bots are after
local TARGET_KEEP  = 60  -- px: ...and keeps its current one unless another is clearly better
local KING_NOTICE  = 800  -- px: King of the Yard - a bot only goes after opponents this close

local WAVE_DELAY     = 2   -- seconds between clearing a wave and the next one
local SPAWN_MIN_DIST = 600 -- bots never spawn closer than this to a player
local IDLE = { dx = 0, dy = 0 } -- input of a player that sent nothing

-- mode: entry of MODES in main.lua ({ waves = bool, ... })
function World.new(mode)
    Arena.setLayout(mode.king and "kingdom" or mode.yardball and "pitch"
        or mode.hideseek and "hideout" or mode.flowers and "gardens" or "yard")
    return setmetatable({
        mode = mode,
        entities = {}, -- every rowdy, in insertion order (players and bots)
        byId = {},
        bullets = {},
        events = {},
        nextId = 1,
        nextBulletId = 1,
        medpacks = {}, -- { id, x, y, born, expires }
        nextMedpackId = 1,
        boxes = {},    -- { id, x, y, hp, born, hitAt }
        barriers = {}, -- { id, team, owner, points = { x1, y1, x2, y2, ... }, born, expires }
        coins = {},    -- { id, x, y, ox, oy (flies out from there), born, expires }
        nextLootId = 1,
        boxTimer = World.BOX_FIRST,
        nextTeam = 3, -- free-for-all: every player gets a team of their own
        time = 0,     -- simulated seconds since the start
        wave = 0, waveSize = 0,
        waveTimer = 0, -- countdown to the next wave once all bots are dead
        match = World.newMatch(mode),
        ball = nil,    -- Yardball: { x, y, vx, vy, carrier = id, lastKick = id, noPick }
        kickoff = 0,   -- Yardball: seconds until the ball can be taken
        beacons = {},  -- King of the Yard: { id, team, owner, x, y, born, expires, progress }
        zone = nil,    -- King of the Yard: the fog's clear circle, see newZone
        hide = nil,    -- Hide and seek: the round's state, see startHideSeek
        flowerGame = nil, -- Flower Gardens: the round's state, see startFlowers
    }, World)
end

-- Round state: { over = bool, timeLeft (duel), winner = entity id or nil (draw),
-- wave = wave reached (waves), goals = { [team] = n } (Yardball), place = { [team] =
-- 1..KING_TEAMS } (King of the Yard, Flower Gardens: the winner 1, the first team out
-- last) }
function World.newMatch(mode)
    return { over = false, goals = mode.yardball and { 0, 0 } or nil,
        place = (mode.king or mode.flowers) and {} or nil,
        timeLeft = not (mode.waves or mode.boss or mode.yardball or mode.king or mode.hideseek
            or mode.flowers) and World.TIME_LIMIT or nil } -- (Hide and seek, Flower Gardens:
                                                           -- set from their clock every step)
end

-- The boss's look: the rowdy's own, BOSS_SIZE bigger (also used by src/replica.lua)
function World.bossLook(def)
    local look = Assets.look(def)
    look.scale = look.scale * World.BOSS_SIZE
    look.muzzle = { look.muzzle[1] * World.BOSS_SIZE, look.muzzle[2] * World.BOSS_SIZE }
    return look
end

-- The boss of a boss fight (entity), or nil
function World:boss()
    for _, e in ipairs(self.entities) do
        if e.boss then return e end
    end
end

-- Events: { kind, t = world time, x, y, ... }
--   spawn {id}  death {id, color, killer}  step {id}  bullet {see newBullets}
--   impact {bullet, owner, color} (wall/crate)  hit {bullet, owner, victim}
--   heal {id, amount} (picked up a medpack)  super {id} (fired a super, at the muzzle)
--   matchOver {winner}  matchStart  shot {id} (normal attack, at the muzzle)
--   superReady {id} (super meter just filled up)
--   box {box} (a loot box appeared)  boxHit {box, bullet, owner, pierce}
--   blast {radius, bullet, owner, super} (a bomb exploded)
--   boxBreak {box, by (who broke it)}  coin {id, value} (player `id` picked up a coin)
--   blast also carries the bomb's projectile (how it looks: "book", "snowball", ...)
--   turn {bullet, owner, x, y, vx, vy, life, wall} (a boomerang flies back from x, y;
--         wall = it bounced off a wall or chest)
--   freeze {id, time} (a rowdy was frozen for `time` seconds)
--   pull {id, by} (rowdy `id` is pulled to rowdy `by`)  punch {id} (dashes forward)
--   leap {id, toX, toY} (jumps; lands with a blast)  burrow {id} (digs in; pops out
--         with a blast)  blink {id, toX, toY} (teleports from x, y; a blast there)
--   vanish {id}  appear {id} (invisible / visible again)  grab {id, victim (nil: missed)}
--   fling {id, by} (a grabbed rowdy is thrown)  bonk {id} (a flung rowdy crashes)
--   cuff {id, time} (handcuffed: can't walk)  heal also for a healing super
--   gust {id, toX, toY} (dashes there on a gust of wind)  barrier {id, barrier}
--   Yardball: pickup {id}  kick {id}  ballDrop {id}  goal {team (that scored), by}
--         bounce (the ball hit a wall)
--   King of the Yard: beacon {id (the one out), team, beacon}  revive {id, by}
--         beaconGone {id, beacon} (nobody came in time)  fog {id} (the fog nibbled it)
--         teamOut {team}
--   Hide and seek: seek {id (the seeker)} (the hide phase is over)  tag {id} (a swing)
--         found {id, by} (after its death event)  disguise {id} (turned into a bush)
--         pieceUp {id, piece}  pieceDrop {id, piece}  piece {id, piece, n (placed now)}
--         picture (all pieces placed)  hint (the hiders shimmer)
--   Flower Gardens: flower {flower} (one grew)  flowerUp {id, flower}  flowerDrop {id,
--         flower}  deliver {id, team, flower, n (towards the bulldozer), total}
--         dozer {id, team} (drives a bulldozer now)  dozerGone {id} (it rolled away)
--         fenceDown {team, by}  teamOut {team} (as in King of the Yard)
function World:emit(kind, data)
    data.kind = kind
    data.t = self.time
    self.events[#self.events + 1] = data
end

-- Returns the events since the last call (the caller turns them into effects/sounds)
function World:takeEvents()
    local events = self.events
    self.events = {}
    return events
end

function World:add(e, team, def)
    e.id, e.team, e.def, e.world = self.nextId, team, def, self
    e.kills, e.deaths, e.goals = 0, 0, 0
    self.nextId = self.nextId + 1
    self.entities[#self.entities + 1] = e
    self.byId[e.id] = e
    return e
end

function World:remove(e)
    for i, other in ipairs(self.entities) do
        if other == e then table.remove(self.entities, i) break end
    end
    self.byId[e.id] = nil
end

function World:get(id) return self.byId[id] end

-- def: an entry of src/rowdies.lua. team: default TEAM_PLAYERS (all players together);
-- World:newTeam() gives a team of its own (free-for-all). style: the player's Yard Pass
-- cosmetics { skin, trail, title, badge } (ids from src/cosmetics.lua, see setStyle).
function World:addPlayer(def, x, y, team, style)
    local p = self:add(Player.new(x, y, Assets.look(def), def.stats),
        team or World.TEAM_PLAYERS, def)
    self:setStyle(p, style)
    return p
end

-- Cosmetics of a player: only for drawing (the skin is part of its look, the trail
-- colours its bullets) and the scoreboards; the simulation ignores them. They travel
-- to LAN clients with the entity (Net.FIELDS).
function World:setStyle(p, style)
    style = style or {}
    p.skin, p.trail, p.title, p.badge = style.skin, style.trail, style.title, style.badge
    p.look = Assets.look(p.def, p.skin)
end

function World:newTeam()
    self.nextTeam = self.nextTeam + 1
    return self.nextTeam - 1
end

-- Spawn point for another player: the regular spawn for the first one, otherwise the
-- free spot farthest from everybody else (out of a few random tries).
function World:playerSpawn()
    if #self.entities == 0 then return Arena.spawn.x, Arena.spawn.y end
    local bx, by, bestD2
    for _ = 1, 30 do
        local x, y = Arena.randomOpenPoint()
        local d2 = math.huge
        for _, e in ipairs(self.entities) do
            d2 = math.min(d2, (e.x - x) ^ 2 + (e.y - y) ^ 2)
        end
        if not bestD2 or d2 > bestD2 then bx, by, bestD2 = x, y, d2 end
    end
    return bx, by
end

-- Switch a player to another rowdy (resets HP and ammo); style: as in addPlayer
function World:setRowdy(p, def, style)
    p.def = def
    p:setRowdy(Assets.look(def), def.stats)
    if style then self:setStyle(p, style) else p.look = Assets.look(def, p.skin) end
end

function World:isOpponent(a, b) return a.team ~= b.team end

function World:countBots()
    local n = 0
    for _, e in ipairs(self.entities) do
        if e.isBot then n = n + 1 end
    end
    return n
end

-- Is `e` hidden from `viewer`? (an opponent in a bush, farther than HIDE_REVEAL, or
-- underground - its dirt mound is drawn anyway)
function World:isHiddenFrom(e, viewer)
    if e.dead or not self:isOpponent(e, viewer) then return false end
    if e.carrying or e.carryingPiece or e.carryingFlower or e.driving then -- the ball, a picture
        return false                                                    -- piece, a flower or a
    end                                                                 -- bulldozer gives it away
    if e.burrowed then return true end
    if not Arena.inBush(e.x, e.y) and not e.vanished then return false end
    local dx, dy = e.x - viewer.x, e.y - viewer.y
    return dx * dx + dy * dy > World.HIDE_REVEAL * World.HIDE_REVEAL
end

-- Nearest opponent of `e`. Living ones first; if all are dead, the nearest dead one
-- (bots still roam towards it). With visibleOnly, only living ones not hidden in a bush.
function World:nearestOpponent(e, visibleOnly)
    local best, bestD2, bestAlive
    for _, o in ipairs(self.entities) do
        if self:isOpponent(e, o) and not (visibleOnly and (o.dead or o.disguised or self:isHiddenFrom(o, e))) then
            local dx, dy = o.x - e.x, o.y - e.y
            local d2 = dx * dx + dy * dy
            local alive = not o.dead
            if not best or (alive and not bestAlive) or (alive == bestAlive and d2 < bestD2) then
                best, bestD2, bestAlive = o, d2, alive
            end
        end
    end
    return best
end

-- The opponent a bot goes after: the nearest one, but every other bot of its team
-- already after an opponent makes that one TARGET_CROWD px "farther" - so bots split
-- up between the players instead of all chasing one. Living ones first (as above).
function World:botTarget(e)
    local crowd = {}
    for _, o in ipairs(self.entities) do
        if o ~= e and o.isBot and o.team == e.team and o.targetId and not o.dead then
            crowd[o.targetId] = (crowd[o.targetId] or 0) + 1
        end
    end
    local best, bestScore, bestAlive
    local notice = (self.mode.king or self.mode.flowers) and KING_NOTICE or math.huge -- (the big
    for _, o in ipairs(self.entities) do                                              -- map: roams first)
        local d = math.sqrt((o.x - e.x) ^ 2 + (o.y - e.y) ^ 2)
        -- (Flower Gardens: not a bulldozer driver, nobody behind its fence - no use)
        if self:isOpponent(e, o) and d <= notice and not o.out and not o.driving
            and not self:sheltered(o) then
            local score = d + TARGET_CROWD * (crowd[o.id] or 0)
            if o.id == e.targetId then score = score - TARGET_KEEP end
            if o.carrying then score = score - CARRIER_BONUS end -- (Yardball)
            if o.carryingFlower then score = score - FLOWER_CARRIER_BONUS end
            local alive = not o.dead
            if not best or (alive and not bestAlive) or (alive == bestAlive and score < bestScore) then
                best, bestScore, bestAlive = o, score, alive
            end
        end
    end
    e.targetId = best and best.id
    return best
end

local function farFromPlayers(self, x, y)
    for _, e in ipairs(self.entities) do
        if not e.isBot then
            local dx, dy = x - e.x, y - e.y
            if dx * dx + dy * dy < SPAWN_MIN_DIST * SPAWN_MIN_DIST then return false end
        end
    end
    return true
end

-- The first bot uses the regular enemy spawn, the rest a random free spot.
-- Either way it has to be far enough from every player.
local function botSpawnPoint(self, i)
    local sx, sy = Arena.enemySpawn.x, Arena.enemySpawn.y
    if i == 1 and farFromPlayers(self, sx, sy) then return sx, sy end
    for _ = 1, 20 do
        local x, y = Arena.randomOpenPoint()
        if farFromPlayers(self, x, y) then return x, y end
    end
    return sx, sy
end

-- Team fight: the three spawn spots of a team (blue = left, red = mirrored right);
-- King of the Yard: the team's corner
local function teamSpots(team)
    if Arena.teamSpawns then return Arena.teamSpawns[team] or Arena.teamSpawns[1] end
    local x, y = Arena.spawn.x, Arena.spawn.y
    if team == World.TEAM_RED then x = Arena.width - x end
    return { { x, y }, { x, y - 128 }, { x, y + 128 } }
end

-- A spawn spot of `team` nobody of that team uses yet (or the first one if all are)
local function freeSpot(self, team)
    local spots = teamSpots(team)
    for _, s in ipairs(spots) do
        local taken = false
        for _, e in ipairs(self.entities) do
            if e.team == team and e.spawnX == s[1] and e.spawnY == s[2] then taken = true end
        end
        if not taken then return s[1], s[2] end
    end
    return spots[1][1], spots[1][2]
end

-- A random rowdy for a new bot, if possible one nobody in the world uses right now
function World:randomBotDef()
    local used, free = {}, {}
    for _, e in ipairs(self.entities) do used[e.def] = true end
    for _, def in ipairs(Rowdies) do
        if not used[def] then free[#free + 1] = def end
    end
    if #free == 0 then return Rowdies[math.random(#Rowdies)] end
    return free[math.random(#free)]
end

-- A new bot (random rowdy, handicapped, see BOT_DAMAGE) at x, y
local function newBot(self, team, x, y)
    local def = self:randomBotDef()
    local e = self:add(Enemy.new(x, y, Assets.look(def), def.stats), team, def)
    e.speed = e.speed * World.BOT_SPEED
    e.damageScale = World.BOT_DAMAGE
    e.chargeScale = World.BOT_CHARGE
    e:respawn() -- pop-in animation + spawn event
    return e
end

-- Number of players (not bots) per team
function World:playersPerTeam()
    local n = {}
    for _, e in ipairs(self.entities) do
        if not e.isBot then n[e.team] = (n[e.team] or 0) + 1 end
    end
    return n
end

local handOver -- (Flower Gardens: below)

-- King of the Yard, Flower Gardens: a player takes the place of a bot of the first team
-- that has one (host + first two joiners = team 1, the next three = team 2, ...) - where
-- the bot is right now (its spot if it waits to pop back in), or out (with its heart) if
-- it was out
local function addKingPlayer(self, def, style)
    local n = self:playersPerTeam()
    local team = World.KING_TEAMS
    for t = 1, World.KING_TEAMS do
        if (n[t] or 0) < World.TEAM_SIZE then team = t break end
    end
    local bot
    for _, e in ipairs(self.entities) do
        if e.isBot and e.team == team and (not bot or (bot.out and not e.out)) then bot = e end
    end
    if not bot then
        local x, y = freeSpot(self, team)
        return self:addPlayer(def, x, y, team, style)
    end
    self:remove(bot)
    local p = self:addPlayer(def, bot.spawnX, bot.spawnY, team, style)
    p.kills, p.deaths = bot.kills, bot.deaths
    if bot.out then
        p.dead, p.out, p.hp = true, true, 0
        for _, b in ipairs(self.beacons) do
            if b.owner == bot.id then b.owner = p.id end
        end
    else
        if not bot.dead then p.x, p.y = bot.x, bot.y end
        p.spawnAnim = 0.35
        self:emit("spawn", { x = p.x, y = p.y, id = p.id })
    end
    if self.flowerGame then handOver(self, bot, p) end
    return p
end

-- Hide and seek: everybody walks at the same speed and can't attack (the seeker swings
-- its tag instead, World:tag)
local function prepareHide(e)
    e.noAttacks = true
    e.speed = e.team == World.TEAM_SEEKER and World.SEEKER_SPEED or World.HIDER_SPEED
    e.disguised, e.stillTime, e.carryingPiece, e.tagCooldown, e.tagBuffer = nil, 0, nil, 0, nil
    e.hs = nil -- (a bot's plans, see World:hidePlan)
end

-- Hide and seek: where hider i (1..) starts - on a circle around the frame
local function hideSpawn(i)
    local a = (i - 1) / (World.HIDE_PLAYERS - 1) * math.pi * 2 + 0.3
    return Arena.nearestOpen(Arena.center.x + math.cos(a) * HIDE_SPAWN_R,
        Arena.center.y + math.sin(a) * HIDE_SPAWN_R, 24)
end

-- Hide and seek: `to` (a player that joined, or the bot of one that left) takes over
-- from `from` as it is - its side, where it is, found or not, the piece it carries
local function takeOver(self, from, to)
    to.team = from.team
    to.kills, to.deaths, to.placed, to.foundAt = from.kills, from.deaths, from.placed, from.foundAt
    prepareHide(to)
    if from.out then
        to.dead, to.out, to.hp = true, true, 0
    else
        to.x, to.y = from.x, from.y
        to.spawnAnim = 0.35
        self:emit("spawn", { x = to.x, y = to.y, id = to.id })
    end
    local h = self.hide
    if not h then return end
    if h.seekerId == from.id then h.seekerId = to.id end
    for _, piece in ipairs(h.pieces) do
        if piece.carrier == from.id then piece.carrier, to.carryingPiece = to.id, piece.id end
    end
end

-- Hide and seek: a player takes the place of a bot (a hider that isn't found yet if
-- there is one, else any hider, else the seeker bot); with no bot left a new hider
local function addHidePlayer(self, def, style)
    local bot
    local function better(e)
        if not bot then return true end
        local hider, bHider = e.team == World.TEAM_HIDERS, bot.team == World.TEAM_HIDERS
        if hider ~= bHider then return hider end
        return bot.out and not e.out
    end
    for _, e in ipairs(self.entities) do
        if e.isBot and better(e) then bot = e end
    end
    if not bot then
        local x, y = hideSpawn(#self.entities)
        local p = self:addPlayer(def, x, y, World.TEAM_HIDERS, style)
        prepareHide(p)
        return p
    end
    self:remove(bot)
    local p = self:addPlayer(def, bot.spawnX, bot.spawnY, bot.team, style)
    takeOver(self, bot, p)
    return p
end

-- Team fight: the humans play together against the bots - a player joins blue and
-- takes a bot's place (red only once blue has no bots left)
function World:addTeamPlayer(def, style)
    if self.mode.king or self.mode.flowers then return addKingPlayer(self, def, style) end
    if self.mode.hideseek then return addHidePlayer(self, def, style) end
    local n = self:playersPerTeam()
    local team = ((n[World.TEAM_BLUE] or 0) < World.TEAM_SIZE) and World.TEAM_BLUE
        or World.TEAM_RED
    local x, y
    for _, e in ipairs(self.entities) do
        if e.isBot and e.team == team then
            x, y = e.spawnX, e.spawnY
            self:remove(e)
            break
        end
    end
    if not x then x, y = freeSpot(self, team) end
    return self:addPlayer(def, x, y, team, style)
end

-- A player leaves; in a team fight a bot takes over the empty place (King of the Yard,
-- Flower Gardens: where the player was, or out with its heart)
function World:removePlayer(p)
    self:remove(p)
    if not self.mode.teams then return end
    local bot = newBot(self, p.team, p.spawnX, p.spawnY)
    if self.mode.hideseek then takeOver(self, p, bot) return end
    if not (self.mode.king or self.mode.flowers) then return end
    bot.kills, bot.deaths = p.kills, p.deaths
    if p.out then
        bot.dead, bot.out, bot.hp = true, true, 0
        for _, b in ipairs(self.beacons) do
            if b.owner == p.id then b.owner = bot.id end
        end
    elseif not p.dead then
        bot.x, bot.y = p.x, p.y
    end
    if self.flowerGame then handOver(self, p, bot) end
end

-- Kills per team
function World:teamScores()
    local s = {}
    for _, e in ipairs(self.entities) do s[e.team] = (s[e.team] or 0) + e.kills end
    return s
end

local function addBoss(self)
    local def = Rowdies[self.mode.boss]
    local x, y = Arena.enemySpawn.x, Arena.enemySpawn.y
    local e = self:add(Enemy.new(x, y, World.bossLook(def), def.stats), World.TEAM_BOTS, def)
    e.boss = true
    e.maxHp = e.maxHp * World.BOSS_HP
    e.radius = e.radius * World.BOSS_SIZE
    e:respawn() -- full (big) HP, pop-in animation + spawn event
end

function World:spawnBots(count)
    for i = 1, count do
        newBot(self, World.TEAM_BOTS, botSpawnPoint(self, i))
    end
end

-- Every wave has one bot more than the one before.
function World:startWave()
    self.wave = self.wave + 1
    self.waveSize = math.min(self.waveSize + 1, World.MAX_BOTS)
    self:spawnBots(self.waveSize)
end

-- Yardball: the ball back to the middle, nobody may take it for KICKOFF_DELAY
local function kickoff(self)
    self.ball = { x = Arena.center.x, y = Arena.center.y, vx = 0, vy = 0, noPick = {} }
    self.kickoff = World.KICKOFF_DELAY
end

-- King of the Yard: the fog's clear circle. It starts around the whole map and ends
-- around a spot near the middle; World.zoneRadius gives its size at a time.
local function newZone(self)
    local a, d = math.random() * math.pi * 2, math.random() * ZONE_SHIFT
    local x = Arena.width / 2 + math.cos(a) * d
    local y = Arena.height / 2 + math.sin(a) * d
    local far = 0 -- (the farthest corner: everything is clear at first)
    for _, c in ipairs({ { 0, 0 }, { Arena.width, 0 }, { 0, Arena.height }, { Arena.width, Arena.height } }) do
        far = math.max(far, math.sqrt((c[1] - x) ^ 2 + (c[2] - y) ^ 2))
    end
    local t = self.time + World.ZONE_WAIT
    self.zone = { x = x, y = y, r0 = far + 64, r1 = World.ZONE_MIN,
        startAt = t, endAt = t + World.ZONE_SHRINK,
        finalAt = t + World.ZONE_SHRINK + World.ZONE_HOLD,
        finalEnd = t + World.ZONE_SHRINK + World.ZONE_HOLD + World.ZONE_FINAL }
    self.zone.r = self.zone.r0
    self.zoneTimer = ZONE_TICK
end

-- Radius of the clear circle at world time t (also used by src/replica.lua)
function World.zoneRadius(z, t)
    if t <= z.startAt then return z.r0 end
    if t <= z.endAt then return z.r0 + (z.r1 - z.r0) * (t - z.startAt) / (z.endAt - z.startAt) end
    if t <= z.finalAt then return z.r1 end
    if t <= z.finalEnd then return z.r1 * (1 - (t - z.finalAt) / (z.finalEnd - z.finalAt)) end
    return 0
end

-- Is x, y inside the clear circle? (margin: this far inside it)
function World:inZone(x, y, margin)
    local z = self.zone
    if not z then return true end
    local r = z.r - (margin or 0)
    return r > 0 and (x - z.x) ^ 2 + (y - z.y) ^ 2 <= r * r
end

-- Hide and seek: a new round - a random seeker in the middle, the hiders around it, the
-- pieces at their spots, the hide phase starts
local function startHideSeek(self)
    local seeker = self.entities[math.random(#self.entities)]
    local i = 0
    for _, e in ipairs(self.entities) do
        e.team = (e == seeker) and World.TEAM_SEEKER or World.TEAM_HIDERS
        prepareHide(e)
        if e == seeker then
            e.spawnX, e.spawnY = Arena.center.x, Arena.center.y
        else
            i = i + 1
            e.spawnX, e.spawnY = hideSpawn(i)
        end
        e.out, e.foundAt, e.placed = false, nil, 0
        e:respawn()
        e.aim = math.atan2(e.y - Arena.center.y, e.x - Arena.center.x)
        e.lastX, e.lastY = e.x, e.y
    end
    local h = { seekerId = seeker.id, phase = "hide", hideUntil = self.time + World.HIDE_TIME,
        pieces = {}, placed = 0, hintUntil = 0 }
    h.endAt = h.hideUntil + World.SEEK_TIME
    h.nextHint = h.hideUntil + World.HINT_AFTER
    for k, spot in ipairs(Arena.pieceSpots) do h.pieces[k] = { id = k, x = spot[1], y = spot[2] } end
    self.hide = h
    self.match.timeLeft = h.endAt - self.time
end

-- Call after the players were added.
function World:start()
    if self.mode.hideseek then -- bots fill the free places, then a random seeker
        for _ = #self.entities + 1, World.HIDE_PLAYERS do
            newBot(self, World.TEAM_HIDERS, Arena.center.x, Arena.center.y)
        end
        startHideSeek(self)
        return
    end
    if self.mode.yardball then
        for _, e in ipairs(self.entities) do e.carrying = nil end
        kickoff(self)
    end
    if self.mode.king then
        self.beacons = {}
        newZone(self)
    end
    if self.mode.teams then -- fill the teams with bots
        local teams = { World.TEAM_BLUE, World.TEAM_RED }
        if self.mode.king or self.mode.flowers then teams = { 1, 2, 3, 4 } end
        for _, team in ipairs(teams) do
            local members = 0
            for _, e in ipairs(self.entities) do
                if e.team == team then members = members + 1 end
            end
            for _ = members + 1, World.TEAM_SIZE do newBot(self, team, freeSpot(self, team)) end
        end
    elseif self.mode.waves then
        self:startWave()
    elseif self.mode.boss then
        addBoss(self)
    else
        self:spawnBots(1)
    end
    if self.mode.flowers then self:startFlowers() end
end

local function bulletHits(b, victim)
    if victim.dead then return false end
    local dx, dy = victim.x - b.x, victim.y - b.y
    local r = victim.radius + b.radius
    return dx * dx + dy * dy < r * r
end

-- A heart beacon where `e` was knocked out (King of the Yard)
local function addBeacon(self, e)
    local b = { id = self.nextLootId, team = e.team, owner = e.id, x = e.x, y = e.y,
        born = self.time, expires = self.time + World.BEACON_LIFE, progress = 0 }
    b.x, b.y = Arena.nearestOpen(b.x, b.y, 12) -- (a vanished one may be in a wall)
    self.nextLootId = self.nextLootId + 1
    self.beacons[#self.beacons + 1] = b
    self:emit("beacon", { id = e.id, team = e.team, beacon = b.id, x = b.x, y = b.y })
end

-- `victim` was just knocked out (by `shooter`, or nil: the fog): scores, medpack, lives
local function knockout(self, victim, shooter)
    victim.goo, victim.rooted = nil, 0
    victim.deaths = victim.deaths + 1
    if shooter and shooter ~= victim then shooter.kills = shooter.kills + 1 end
    if shooter and not shooter.isBot then self:dropMedpack(victim.x, victim.y) end
    -- Waves: out of lives = no more respawns
    if self.mode.waves and not victim.isBot and victim.deaths >= World.LIVES then
        victim.out = true
    end
    if victim.boss then victim.out = true end -- the boss fight is won
    if self.mode.king then -- out until a team mate brings it back
        victim.out = true
        addBeacon(self, victim)
    end
    local fg = self.flowerGame
    if fg and not fg.fences[victim.team] then victim.out = true end -- no fence: no way back
end

-- Hide and seek: the seeker's tag hit a hider - found: a poof, out for the round; a
-- piece it carried stays where it was
local function findHider(self, victim, seeker)
    local h = self.hide
    if not h or victim.team ~= World.TEAM_HIDERS or victim.out or victim.dead then return end
    victim.disguised = nil
    victim.deaths = victim.deaths + 1
    if seeker then seeker.kills = seeker.kills + 1 end
    victim.foundAt = self.time
    for _, piece in ipairs(h.pieces) do
        if piece.carrier == victim.id then
            piece.carrier = nil
            self:emit("pieceDrop", { id = victim.id, piece = piece.id, x = piece.x, y = piece.y })
        end
    end
    victim.carryingPiece = nil
    victim:takeDamage(victim.hp + 1, seeker and seeker.id) -- (the death event: the poof)
    victim.out = true
    self:emit("found", { id = victim.id, by = seeker and seeker.id, x = victim.x, y = victim.y })
end

-- Bullet (or bomb) b hits a rowdy at x, y: damage, super charge, kills, medpack, lives
local function damage(self, b, victim, x, y)
    if b.tag then return findHider(self, victim, b.owner) end
    self:emit("hit", { x = x, y = y, victim = victim.id,
        bullet = b.id, owner = b.owner.id, pierce = b.pierce or b.lob })
    local shooter = self.byId[b.owner.id]
    local amount = (b.damage or 0) * (b.owner.damageScale or 1) -- bots hit softer
    if shooter and not b.super then shooter:addCharge(b.chargeHit or amount) end
    local knockedOut = victim:takeDamage(amount, b.owner.id)
    if b.freeze and not victim.dead then
        victim.frozen = math.max(victim.frozen, b.freeze)
        victim.bursting = nil
        self:emit("freeze", { id = victim.id, x = victim.x, y = victim.y, time = b.freeze })
    end
    if b.hold and not victim.dead then -- handcuffs: stands still (may still attack)
        victim.rooted = math.max(victim.rooted or 0, b.hold)
        self:emit("cuff", { id = victim.id, x = victim.x, y = victim.y, time = b.hold })
    end
    if b.goo and not victim.dead then -- sticky goo: more damage over GOO_TIME
        local n = World.GOO_TIME / GOO_TICK
        local g = victim.goo
        if not g or g.left < n or g.per < b.goo / n then
            victim.goo = { by = b.owner.id, team = b.team, per = b.goo / n, left = n, timer = GOO_TICK }
        end
    end
    local puller = b.pull and shooter
    if puller and not victim.dead and not puller.dead then -- flies to the puller
        local dx, dy = puller.x - victim.x, puller.y - victim.y
        local d = math.sqrt(dx * dx + dy * dy)
        local gap = d - puller.radius - victim.radius - 6
        if gap > 1 then
            victim:pushBy(dx / d * World.PULL_SPEED, dy / d * World.PULL_SPEED, gap / World.PULL_SPEED)
            victim.bursting = nil
            self:emit("pull", { id = victim.id, by = puller.id, x = victim.x, y = victim.y })
        end
    end
    if knockedOut then knockout(self, victim, shooter) end
end

-- A bomb lands: every opponent and loot box within the blast radius takes its damage
-- once (walls don't shield - it's an explosion right there)
local function explode(self, b)
    local x, y, r = b.x, b.y, b.blast
    self:emit("blast", { x = x, y = y, radius = r, bullet = b.id, owner = b.owner.id,
        super = b.super, projectile = b.projectile })
    for _, e in ipairs(self.entities) do
        local reach = r + e.radius
        if e.team ~= b.team and not e.dead and not e:untouchable() and not self:sheltered(e)
            and (e.x - x) ^ 2 + (e.y - y) ^ 2 < reach * reach then
            damage(self, b, e, e.x, e.y)
        end
    end
    local boxes = {}
    for _, box in ipairs(self.boxes) do boxes[#boxes + 1] = box end
    local reach = r + World.BOX_HALF
    for _, box in ipairs(boxes) do
        if (box.x - x) ^ 2 + (box.y - y) ^ 2 < reach * reach then self:hitBox(box, b) end
    end
end

-- A boomerang turns (its range flown, or it bounced off a wall or chest; then it is
-- already back where it was before touching it) and flies back to where it was thrown;
-- on the way back it can hit everybody once more
local function turnBack(self, b, wall)
    local dx, dy = b.homeX - b.x, b.homeY - b.y
    local d = math.sqrt(dx * dx + dy * dy)
    local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
    if d < 1 then dx, dy, d = -b.vx, -b.vy, speed end
    b.vx, b.vy = dx / d * speed, dy / d * speed
    b.life = math.max(d, 1) / speed
    b.returning, b.hitIds, b.hitBoxes = true, nil, nil
    if b.id then
        self:emit("turn", { x = b.x, y = b.y, vx = b.vx, vy = b.vy, life = b.life,
            bullet = b.id, owner = b.owner.id, wall = wall })
    end
end

-- A rowdy's own attack hits everybody around x, y (a leap lands, a burrow pops out):
-- like a bomb of `attack` (its damage, blast radius, projectile) exploding there
function World:blastAt(owner, attack, x, y)
    explode(self, { x = x, y = y, blast = attack.blast or 60, damage = attack.damage or 0,
        owner = owner, team = owner.team, super = attack == owner.super,
        projectile = attack.projectile, freeze = attack.freeze })
end

-- One hit of a rowdy's own attack (a beam tick, a flung rowdy crashing) on `victim`
function World:hitWith(owner, attack, victim, x, y)
    if victim.dead or victim.team == owner.team or self:sheltered(victim) then return end
    damage(self, { owner = owner, team = owner.team, damage = attack.damage or 0,
        super = attack == owner.super, freeze = attack.freeze, pull = attack.pull,
        hold = attack.hold, goo = attack.goo }, victim, x, y)
end

-- A beam from `owner` along its aim: how long it is (up to range, the first wall or
-- crate), and the first opponent or chest on it
function World:traceBeam(owner, range)
    local c, s = math.cos(owner.aim), math.sin(owner.aim)
    local d = 0
    while d < range do
        d = math.min(range, d + 6)
        local x, y = owner.x + c * d, owner.y + s * d
        if Arena.hitsSolid(x, y, 3) or self:barrierAt(x, y, 3, owner.team) then return d end
        local box = self:boxAt(x, y, 4)
        if box then return d, nil, box end
        for _, e in ipairs(self.entities) do
            if e.team ~= owner.team and not e.dead and not e:untouchable()
                and (e.x - x) ^ 2 + (e.y - y) ^ 2 < e.radius * e.radius then
                return d, e
            end
        end
    end
    return range
end

local function updateBullets(self, dt)
    local bullets = self.bullets
    for i = #bullets, 1, -1 do
        local b = bullets[i]
        -- Move in small sub-steps so fast bullets can't skip through targets
        local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
        local steps = math.max(1, math.ceil(speed * dt / 10))
        local remove = false

        if b.lob then -- a bomb flies over everything and explodes where it lands
            b:update(math.min(dt, b.life))
            if b.life <= 1e-9 then
                explode(self, b)
                remove = true
            end
            steps = 0
        end

        for _ = 1, steps do
            local px, py = b.x, b.y
            b:update(dt / steps)
            local outbound = b.boomerang and not b.returning
            local box = self:boxAt(b.x, b.y, b.wallRadius or b.radius)
            if box and not (b.hitBoxes and b.hitBoxes[box.id]) and b.blast then
                explode(self, b) -- a firework rocket bursts on the chest
                remove = true
                break
            end
            if box and not (b.hitBoxes and b.hitBoxes[box.id]) then
                self:hitBox(box, b)
                if outbound then -- a boomerang bounces back off a chest
                    b.x, b.y = px, py
                    turnBack(self, b, true)
                elseif b.pierce and not b.boomerang then
                    b.hitBoxes = b.hitBoxes or {}
                    b.hitBoxes[box.id] = true
                else
                    remove = true
                    break
                end
            end
            local wall = Arena.hitsSolid(b.x, b.y, b.wallRadius or b.radius)
                or self:barrierAt(b.x, b.y, b.wallRadius or b.radius, b.team)
            if wall and b.blast then -- a rocket bursts at the wall
                b.x, b.y = px, py
                explode(self, b)
                remove = true
                break
            elseif wall then
                if outbound then -- ... and off a wall
                    b.x, b.y = px, py
                    turnBack(self, b, true)
                else
                    self:emit("impact", { x = b.x, y = b.y, color = b.color, -- wall / crate
                        bullet = b.id, owner = b.owner.id })
                    remove = true
                    break
                end
            elseif b.life <= 0 then
                if not outbound then
                    if b.blast then explode(self, b) end -- (a rocket bursts at its range)
                    remove = true
                    break
                end
                turnBack(self, b, false)
            end
            -- Bullets hit any rowdy of another team; piercing ones each rowdy once
            local victim
            for _, e in ipairs(self.entities) do
                if e.team ~= b.team and not (b.hitIds and b.hitIds[e.id]) and not e:untouchable()
                    and bulletHits(b, e) then
                    victim = e
                    break
                end
            end
            if victim and b.blast then -- a rocket bursts on the one it hits (and around)
                explode(self, b)
                remove = true
                break
            elseif victim then
                damage(self, b, victim, b.x, b.y)
                if b.pierce then
                    b.hitIds = b.hitIds or {}
                    b.hitIds[victim.id] = true
                else
                    remove = true
                    break
                end
            end
        end

        if remove then table.remove(bullets, i) end
    end
end

-- Sticky goo stings now and then (World.GOO_TIME, see damage)
local function updateGoo(self, dt)
    for _, e in ipairs(self.entities) do
        local g = e.goo
        if g and e.dead then e.goo = nil
        elseif g then
            g.timer = g.timer - dt
            if g.timer <= 0 then
                g.timer, g.left = g.timer + GOO_TICK, g.left - 1
                local owner = self.byId[g.by] or { id = g.by }
                if not e:untouchable() and not self:sheltered(e) then
                    damage(self, { owner = owner, team = g.team, damage = g.per }, e, e.x, e.y)
                end
                if e.goo == g and g.left <= 0 then e.goo = nil end
            end
        end
    end
end

---------------------------------------------------------------------------- barriers

-- Closest point of segment a-b to p: distance and the push-out direction
local function segmentPush(ax, ay, bx, by, px, py)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local t = len2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) or 0
    local cx, cy = ax + dx * t, ay + dy * t
    local ox, oy = px - cx, py - cy
    local d = math.sqrt(ox * ox + oy * oy)
    if d < 1e-6 then return 0, -dy, dx end -- on the line: out sideways
    return d, ox / d, oy / d
end

-- A barrier of another team than `team` that a circle at x, y (radius r) touches
-- (Flower Gardens: or the garden of another team with its fence up)
function World:barrierAt(x, y, r, team)
    if self.flowerGame then
        local g = self:fenceAt(x, y, r, team)
        if g then return g end
    end
    for _, w in ipairs(self.barriers) do
        if w.team ~= team then
            local p = w.points
            for i = 1, #p - 3, 2 do
                if segmentPush(p[i], p[i + 1], p[i + 2], p[i + 3], x, y) < r + World.BARRIER_HALF then
                    return w
                end
            end
        end
    end
end

-- The fence a barrier attack would put up now (points along an arc in front of `e`)
function World.barrierPoints(e)
    local pts = {}
    for i = 0, BARRIER_POINTS - 1 do
        local a = e.aim + (i / (BARRIER_POINTS - 1) - 0.5) * World.BARRIER_ANGLE
        pts[#pts + 1] = e.x + math.cos(a) * World.BARRIER_DIST
        pts[#pts + 1] = e.y + math.sin(a) * World.BARRIER_DIST
    end
    return pts
end

-- A barrier attack: the fence in front of `owner` for attack.duration seconds
function World:addBarrier(owner, attack)
    local w = { id = self.nextLootId, team = owner.team, owner = owner.id,
        points = World.barrierPoints(owner), born = self.time,
        expires = self.time + (attack.duration or 6) }
    self.nextLootId = self.nextLootId + 1
    self.barriers[#self.barriers + 1] = w
    self:emit("barrier", { id = owner.id, barrier = w.id, x = owner.x, y = owner.y })
end

-- Old barriers go; opponents are pushed out of the ones that stand
local function updateBarriers(self)
    local list = self.barriers
    for i = #list, 1, -1 do
        if self.time >= list[i].expires then table.remove(list, i) end
    end
    if #list == 0 then return end
    for _, e in ipairs(self.entities) do
        if not e.dead and not e.vanished and not e.leap and not e.burrowed and not e.driving then
            for _, w in ipairs(list) do
                if w.team ~= e.team then
                    local p = w.points
                    for i = 1, #p - 3, 2 do
                        local d, nx, ny = segmentPush(p[i], p[i + 1], p[i + 2], p[i + 3], e.x, e.y)
                        local reach = e.radius + World.BARRIER_HALF
                        if d < reach then
                            e.x, e.y = Arena.resolveCircle(e.x + nx * (reach - d), e.y + ny * (reach - d), e.radius)
                        end
                    end
                end
            end
        end
    end
end

----------------------------------------------------------------------------

-- Waves: killed bots stay dead (removed); once the wave is cleared the next one follows.
-- Otherwise dead bots stay in the world and respawn by themselves.
local function updateWaves(self, dt)
    for i = #self.entities, 1, -1 do
        local e = self.entities[i]
        if e.isBot and e.dead then
            self:remove(e)
            if self:countBots() == 0 then self.waveTimer = WAVE_DELAY end
        end
    end
    if self:countBots() == 0 then
        self.waveTimer = self.waveTimer - dt
        if self.waveTimer <= 0 then self:startWave() end
    end
end

function World:dropMedpack(x, y)
    if #self.medpacks >= MAX_MEDPACKS then table.remove(self.medpacks, 1) end -- oldest goes
    self.medpacks[#self.medpacks + 1] = { id = self.nextMedpackId, x = x, y = y,
        born = self.time, expires = self.time + World.MEDPACK_LIFE }
    self.nextMedpackId = self.nextMedpackId + 1
end

-- Hurt players (not bots) pick up medpacks they touch; old ones disappear
local function updateMedpacks(self)
    local packs = self.medpacks
    for i = #packs, 1, -1 do
        local m, taken = packs[i], false
        for _, e in ipairs(self.entities) do
            if not e.isBot and not e.dead and e.hp < e.maxHp then
                local r = e.radius + MEDPACK_REACH
                if (e.x - m.x) ^ 2 + (e.y - m.y) ^ 2 < r * r then
                    local amount = math.min(e.maxHp - e.hp, math.ceil(e.maxHp * World.MEDPACK_HEAL))
                    e.hp = e.hp + amount
                    self:emit("heal", { id = e.id, x = e.x, y = e.y, amount = amount })
                    taken = true
                    break
                end
            end
        end
        if taken or self.time >= m.expires then table.remove(packs, i) end
    end
end

-- Distance check of a circle against a box: returns the push-out direction and
-- overlap (dx, dy, depth) or nil
local function boxOverlap(box, x, y, r)
    local h = World.BOX_HALF
    local cx = math.max(box.x - h, math.min(x, box.x + h))
    local cy = math.max(box.y - h, math.min(y, box.y + h))
    local dx, dy = x - cx, y - cy
    local d2 = dx * dx + dy * dy
    if d2 >= r * r then return nil end
    if d2 == 0 then -- centre inside the box: out the nearest side
        local ox, oy = x - box.x, y - box.y
        if math.abs(ox) > math.abs(oy) then
            return (ox < 0 and -1 or 1), 0, h - math.abs(ox) + r
        end
        return 0, (oy < 0 and -1 or 1), h - math.abs(oy) + r
    end
    local d = math.sqrt(d2)
    return dx / d, dy / d, r - d
end

-- The box a circle touches, or nil
function World:boxAt(x, y, r)
    for _, box in ipairs(self.boxes) do
        if boxOverlap(box, x, y, r) then return box end
    end
end

-- A bullet hits a box: damage, and at 0 HP it breaks and scatters coins
function World:hitBox(box, b)
    box.hp, box.hitAt = box.hp - b.damage, self.time
    self:emit("boxHit", { x = b.x, y = b.y, box = box.id, bullet = b.id, owner = b.owner.id,
        pierce = b.pierce })
    if box.hp > 0 then return end
    for i, other in ipairs(self.boxes) do
        if other == box then table.remove(self.boxes, i) break end
    end
    self:emit("boxBreak", { x = box.x, y = box.y, box = box.id, by = b.owner.id })
    local turn = math.random() * math.pi * 2
    for i = 1, World.BOX_COINS do
        local a = turn + i / World.BOX_COINS * math.pi * 2
        local d = 34 + math.random() * 22
        local x, y = box.x + math.cos(a) * d, box.y + math.sin(a) * d
        if Arena.hitsSolid(x, y, 8) then x, y = box.x, box.y end
        self.coins[#self.coins + 1] = { id = self.nextLootId, x = x, y = y, ox = box.x,
            oy = box.y, born = self.time, expires = self.time + World.COIN_LIFE }
        self.nextLootId = self.nextLootId + 1
    end
end

-- A free spot for a new box: open ground, not in a bush, away from rowdies and boxes
local function boxSpot(self)
    for _ = 1, 30 do
        local x, y = Arena.randomOpenPoint()
        -- room for a rowdy to walk between the box and any wall (no getting squeezed)
        local ok = not Arena.hitsSolid(x, y, World.BOX_HALF * 1.42 + 48) and not Arena.inBush(x, y)
        for _, e in ipairs(self.entities) do
            if (e.x - x) ^ 2 + (e.y - y) ^ 2 < BOX_MIN_DIST ^ 2 then ok = false end
        end
        for _, box in ipairs(self.boxes) do
            if (box.x - x) ^ 2 + (box.y - y) ^ 2 < (2 * BOX_MIN_DIST) ^ 2 then ok = false end
        end
        local ball = self.ball -- (Yardball: not on the ball, not in front of a goal)
        if ball and (ball.x - x) ^ 2 + (ball.y - y) ^ 2 < BOX_MIN_DIST ^ 2 then ok = false end
        for _, g in ipairs(ball and Arena.goals or {}) do
            if (g.x - x) ^ 2 + ((g.y1 + g.y2) / 2 - y) ^ 2 < 400 ^ 2 then ok = false end
        end
        for _, g in ipairs(Arena.gardens or {}) do -- (Flower Gardens: not in a garden)
            if x > g.x1 - 100 and x < g.x2 + 100 and y > g.y1 - 100 and y < g.y2 + 100 then ok = false end
        end
        if ok then return x, y end
    end
end

-- New boxes now and then; rowdies can't walk through them; players collect coins
local function updateLoot(self, dt)
    self.boxTimer = self.boxTimer - dt
    if self.boxTimer <= 0 then
        self.boxTimer = World.BOX_EVERY
        local x, y
        if #self.boxes < MAX_BOXES and not self.mode.hideseek then x, y = boxSpot(self) end
        if x then
            self.boxes[#self.boxes + 1] = { id = self.nextLootId, x = x, y = y,
                hp = World.BOX_HP, born = self.time }
            self.nextLootId = self.nextLootId + 1
            self:emit("box", { x = x, y = y, box = self.nextLootId - 1 })
        end
    end
    for _, e in ipairs(self.entities) do
        if not e.dead then
            for _, box in ipairs(self.boxes) do
                local nx, ny, depth = boxOverlap(box, e.x, e.y, e.radius)
                if nx then
                    e.x, e.y = Arena.resolveCircle(e.x + nx * depth, e.y + ny * depth, e.radius)
                end
            end
        end
    end
    local coins = self.coins
    for i = #coins, 1, -1 do
        local c, taken = coins[i], false
        for _, e in ipairs(self.entities) do
            if not e.isBot and not e.dead then
                local r = e.radius + COIN_REACH
                if (e.x - c.x) ^ 2 + (e.y - c.y) ^ 2 < r * r then
                    self:emit("coin", { id = e.id, x = c.x, y = c.y, value = World.COIN_VALUE })
                    taken = true
                    break
                end
            end
        end
        if taken or self.time >= c.expires then table.remove(coins, i) end
    end
end

-- Give bullets fired in this step an id and announce them. A bullet flies in a straight
-- line, so a client can draw it from this alone: position(t) = x0 + vx * (t - t0).
local function newBullets(self)
    for _, b in ipairs(self.bullets) do
        if not b.id then
            b.id, b.t0 = self.nextBulletId, self.time
            self.nextBulletId = self.nextBulletId + 1
            self:emit("bullet", { id = b.id, owner = b.owner.id, x = b.x, y = b.y,
                vx = b.vx, vy = b.vy, life = b.life, radius = b.radius, super = b.super,
                lob = b.lob, projectile = b.projectile })
        end
    end
end

-- Lives left of a player in Waves
function World:livesLeft(e)
    return math.max(0, World.LIVES - e.deaths)
end

-- winner: entity (duel), winnerTeam: team id (team fight); both nil = draw
local function endMatch(self, winner, winnerTeam)
    self.match.over = true
    self.match.winner = winner and winner.id
    self.match.winnerTeam = winnerTeam
    self.match.wave = self.wave
    self:emit("matchOver", { winner = self.match.winner, winnerTeam = winnerTeam,
        wave = self.wave })
end

---------------------------------------------------------------------------- King of the Yard

-- Is anybody of `team` up (not out)?
function World:teamUp(team)
    for _, e in ipairs(self.entities) do
        if e.team == team and not e.out then return true end
    end
    return false
end

local function removeBeacon(self, i, gone)
    local b = table.remove(self.beacons, i)
    if gone then self:emit("beaconGone", { id = b.owner, beacon = b.id, x = b.x, y = b.y }) end
end

-- Team mates standing on a heart fill it up; full = the one out is back (at the
-- heart, with REVIVE_HP of its HP). Old hearts and those of eliminated teams go.
local function updateBeacons(self, dt)
    local list = self.beacons
    for i = #list, 1, -1 do
        local b = list[i]
        local owner = self.byId[b.owner]
        if not owner or not owner.out or owner.team ~= b.team then
            removeBeacon(self, i, false)
        elseif self.time >= b.expires or not self:teamUp(b.team) then
            removeBeacon(self, i, true)
        else
            local helper
            for _, e in ipairs(self.entities) do
                local r = e.radius + World.BEACON_REACH
                if e.team == b.team and not e.dead and not e.out and not e.burrowed
                    and (e.x - b.x) ^ 2 + (e.y - b.y) ^ 2 < r * r then
                    helper = e
                    break
                end
            end
            b.progress = helper and b.progress + dt or 0
            if helper and b.progress >= World.REVIVE_TIME then
                table.remove(list, i)
                local sx, sy = owner.spawnX, owner.spawnY
                owner.spawnX, owner.spawnY = b.x, b.y
                owner.out = false
                owner:respawn()
                owner.spawnX, owner.spawnY = sx, sy
                owner.hp = math.ceil(owner.maxHp * World.REVIVE_HP)
                self:emit("revive", { id = owner.id, by = helper.id, x = b.x, y = b.y })
            end
        end
    end
end

-- The fog closes in; it nibbles everybody outside the clear circle now and then
local function updateZone(self, dt)
    local z = self.zone
    z.r = World.zoneRadius(z, self.time)
    self.zoneTimer = self.zoneTimer - dt
    if self.zoneTimer > 0 then return end
    self.zoneTimer = self.zoneTimer + ZONE_TICK
    for _, e in ipairs(self.entities) do
        if not e.dead and not self:inZone(e.x, e.y) then
            self:emit("fog", { id = e.id, x = e.x, y = e.y })
            if e:takeDamage(World.ZONE_DAMAGE * ZONE_TICK) then knockout(self, e, nil) end
        end
    end
end

-- What bot `e` does in King of the Yard (src/enemy.lua), or nil = fight as usual:
-- { x, y } = walk there. Out of the fog first (always), then a team mate's heart close
-- by (unless an opponent is close and in sight: visible = its target is).
function World:kingPlan(e, visible, dist)
    local z = self.zone
    if not z or self.match.over then return nil end
    local dz = math.sqrt((e.x - z.x) ^ 2 + (e.y - z.y) ^ 2)
    if dz > z.r - 40 or (not visible and dz > z.r - 200) then -- (a bit inside is enough:
        local k = math.max(0, z.r - 350) / math.max(dz, 1)      -- no crowd in the middle)
        return { x = z.x + (e.x - z.x) * k, y = z.y + (e.y - z.y) * k, fog = true }
    end
    if visible and dist and dist < 250 then return nil end
    local best, bestD2
    for _, b in ipairs(self.beacons) do
        local d2 = (b.x - e.x) ^ 2 + (b.y - e.y) ^ 2
        if b.team == e.team and d2 < 900 * 900 and self:inZone(b.x, b.y, 20)
            and (not bestD2 or d2 < bestD2) then
            best, bestD2 = b, d2
        end
    end
    if best then return { x = best.x, y = best.y, beacon = true } end
end

---------------------------------------------------------------------------- Hide and seek

-- The seeker swings its tag (its attack button; bots call it too): a short wide swing
-- in front of it that finds every hider it touches (src/bullet.lua draws the swing).
-- Not while the hiders hide, not faster than TAG_COOLDOWN. Returns true if it swung.
function World:tag(e)
    local h = self.hide
    if not h or h.phase ~= "seek" or e.id ~= h.seekerId or e.dead or (e.tagCooldown or 0) > 0 then
        return false
    end
    e.tagCooldown = World.TAG_COOLDOWN
    local b = Bullet.new(e.x, e.y, e.aim, e, World.TAG)
    b.tag = true -- (a hit finds the hider, see damage)
    self.bullets[#self.bullets + 1] = b
    e.recoil = 1
    self:emit("tag", { id = e.id, x = e.x, y = e.y })
    return true
end

-- Where piece k sits in the frame once placed (k = the quarter of the picture:
-- 1 top left, 2 top right, 3 bottom left, 4 bottom right; also used for drawing)
function World.pieceSlot(k)
    local f = Arena.frame
    return f.x + f.w * (((k - 1) % 2) + 0.5) / 2, f.y + f.h * (math.floor((k - 1) / 2) + 0.5) / 2
end

local function placePiece(self, piece, e)
    local h = self.hide
    piece.carrier, piece.placed, e.carryingPiece = nil, true, nil
    piece.x, piece.y = World.pieceSlot(piece.id)
    h.placed = h.placed + 1
    e.placed = (e.placed or 0) + 1
    h.endAt = h.endAt - World.PIECE_TIME
    self:emit("piece", { id = e.id, piece = piece.id, n = h.placed, x = piece.x, y = piece.y })
    if h.placed == #h.pieces then -- the picture is complete
        h.endAt = h.endAt - World.PICTURE_BONUS
        self:emit("picture", { x = Arena.center.x, y = Arena.center.y })
    end
end

-- Every step: the seeking starts after the hide phase, hiders standing still turn into
-- bushes, pieces are picked up, carried and placed, the hints come
local function updateHide(self, dt)
    local h = self.hide
    if h.phase == "hide" and self.time >= h.hideUntil then
        h.phase = "seek"
        self:emit("seek", { id = h.seekerId })
    end
    for _, e in ipairs(self.entities) do
        if e.team == World.TEAM_HIDERS and not e.dead then
            local moved = (e.x - (e.lastX or e.x)) ^ 2 + (e.y - (e.lastY or e.y)) ^ 2 > 0.25
            if moved or e.carryingPiece then
                e.stillTime, e.disguised = 0, nil
            else
                e.stillTime = (e.stillTime or 0) + dt
                if not e.disguised and e.stillTime >= World.DISGUISE_TIME then
                    e.disguised = true
                    self:emit("disguise", { id = e.id, x = e.x, y = e.y })
                end
            end
        end
        e.lastX, e.lastY = e.x, e.y
    end
    local f = Arena.frame
    for _, piece in ipairs(h.pieces) do
        local c = piece.carrier and self.byId[piece.carrier]
        if piece.placed then -- (stays in the frame)
        elseif c and not c.dead then
            piece.x, piece.y = c.x, c.y
            local r = World.FRAME_REACH
            if c.x > f.x - r and c.x < f.x + f.w + r and c.y > f.y - r and c.y < f.y + f.h + r then
                placePiece(self, piece, c)
            end
        else
            piece.carrier = nil
            if h.phase == "seek" then
                for _, e in ipairs(self.entities) do
                    local reach = e.radius + World.PIECE_REACH
                    if e.team == World.TEAM_HIDERS and not e.dead and not e.carryingPiece
                        and (e.x - piece.x) ^ 2 + (e.y - piece.y) ^ 2 < reach * reach then
                        piece.carrier, e.carryingPiece = e.id, piece.id
                        e.disguised, e.stillTime = nil, 0
                        self:emit("pieceUp", { id = e.id, piece = piece.id, x = piece.x, y = piece.y })
                        break
                    end
                end
            end
        end
    end
    if h.phase == "seek" and self.time >= h.nextHint then
        h.nextHint = h.nextHint + World.HINT_EVERY
        h.hintUntil = self.time + World.HINT_LENGTH
        self:emit("hint", {})
    end
    self.match.timeLeft = math.max(0, h.endAt - self.time)
end

-- Places worth hiding in (and so worth checking for the seeker bot): the middle of
-- every bush and the open spots next to the corners of walls and crates, not near the
-- frame. Made once per world.
local function hideSpots(self)
    if self.hideSpots then return self.hideSpots end
    local list, T = {}, 64
    local function add(x, y)
        if Arena.hitsSolid(x, y, 26) then return end
        if (x - Arena.center.x) ^ 2 + (y - Arena.center.y) ^ 2 < 450 * 450 then return end
        list[#list + 1] = { x = x, y = y, bush = Arena.inBush(x, y) }
    end
    for _, b in ipairs(Arena.bushes) do
        for bx = 0, b.w / 2 - 1 do -- (a long hedge: one spot per block)
            for by = 0, b.h / 2 - 1 do add((b.x + bx * 2 + 1) * T, (b.y + by * 2 + 1) * T) end
        end
    end
    for _, w in ipairs(Arena.walls) do
        for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
            local x = (c[1] < 0) and (w.x * T - 34) or ((w.x + w.w) * T + 34)
            local y = (c[2] < 0) and (w.y * T - 34) or ((w.y + w.h) * T + 34)
            if not Arena.inBush(x, y) then add(x, y) end
        end
    end
    self.hideSpots = list
    return list
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

-- Does `e` see `o`? (in range, nothing solid between, not hidden in a bush)
local function sees(self, e, o, range)
    return not o.dead and dist(e, o) <= range and not self:isHiddenFrom(o, e)
        and Arena.hasLineOfSight(e.x, e.y, o.x, o.y)
end

-- A bot walking to a goal: true once it got no closer for GIVE_UP s (then it picks another)
local function stuckOn(mem, goal, d)
    if mem.goal ~= goal then mem.goal, mem.goalBest, mem.goalTime = goal, d, 0 end
    if d < mem.goalBest - 40 then mem.goalBest, mem.goalTime = d, 0 end
    mem.goalTime = mem.goalTime + World.TICK
    return mem.goalTime > GIVE_UP
end

-- A hiding place for hider bot `e`: far from the seeker (or the middle), not where
-- another hider bot hides, not too far to walk; `away`: only spots farther from the
-- seeker than from `e` (running away)
local function pickHideSpot(self, e, seeker, away)
    local from = seeker or Arena.center
    local best, bestScore
    for _, s in ipairs(hideSpots(self)) do
        local ds, de = dist(s, from), dist(s, e)
        if not away or ds > de + 100 then
            local score = math.min(ds, 1400) * (0.6 + 0.4 * math.random()) - de * 0.3
            for _, o in ipairs(self.entities) do
                local spot = o ~= e and o.hs and o.hs.spot
                if spot and dist(spot, s) < 250 then score = score - 700 end
            end
            if s == (e.hs and e.hs.badSpot) then score = score - 2000 end
            if not bestScore or score > bestScore then best, bestScore = s, score end
        end
    end
    return best or { x = e.x, y = e.y }
end

-- What the seeker bot does: after a hider it sees (a disguised one only once it noticed
-- the odd bush close by), to where it saw one last or where the hint showed one, else
-- from one hiding place to the nearest one it hasn't checked yet.
local function seekPlan(self, e, mem)
    local h = self.hide
    mem.noticed = mem.noticed or {}
    local hint = h.hintUntil > self.time and mem.hintSeen ~= h.hintUntil
    if hint then mem.hintSeen = h.hintUntil end
    local best, bestD, nearest, nearestD
    for _, o in ipairs(self.entities) do
        if o.team == World.TEAM_HIDERS and not o.dead then
            local d = dist(e, o)
            if not nearestD or d < nearestD then nearest, nearestD = o, d end
            if not o.disguised then mem.noticed[o.id] = nil end
            local seen = sees(self, e, o, SEEK_SIGHT)
            if seen and o.disguised and not mem.noticed[o.id] then
                seen = d < NOTICE_DIST and math.random() < NOTICE_RATE * World.TICK
                if seen then mem.noticed[o.id] = true end
            end
            if seen and (not bestD or d < bestD) then best, bestD = o, d end
        end
    end
    if hint and nearest then mem.lastX, mem.lastY = nearest.x, nearest.y end
    if best then
        mem.lastX, mem.lastY = best.x, best.y
        local plan = { x = best.x, y = best.y, state = "chase" }
        if bestD < TAG_REACH then plan.tag = math.atan2(best.y - e.y, best.x - e.x) end
        return plan
    end
    if mem.lastX then -- where one was seen (or the hint showed one)
        local d = math.sqrt((mem.lastX - e.x) ^ 2 + (mem.lastY - e.y) ^ 2)
        if d > 40 and not stuckOn(mem, "last", d) then
            return { x = mem.lastX, y = mem.lastY, state = "search" }
        end
        mem.lastX, mem.lastY = nil, nil
    end
    -- check the hiding places, the nearest unchecked one first
    local spots = hideSpots(self)
    mem.visited = mem.visited or {}
    local target, targetD
    for i, s in ipairs(spots) do
        if not mem.visited[i] then
            local d = dist(s, e)
            if d < 90 then
                mem.visited[i] = true
                if s.bush and (e.tagCooldown or 0) <= 0 then -- a swing into the bush
                    return { x = s.x, y = s.y, tag = math.random() * math.pi * 2, state = "check" }
                end
            elseif not targetD or d < targetD then
                target, targetD = i, d
            end
        end
    end
    if not target then mem.visited = {} return nil end -- all checked: once more
    if stuckOn(mem, target, targetD) then mem.visited[target] = true end
    return { x = spots[target].x, y = spots[target].y, state = "check" }
end

-- What Hide and seek bot `e` does (src/enemy.lua), or nil = stand still:
-- { x, y, state } = walk there; tag = an angle: swing the tag that way.
-- Hiders: to a hiding place far from the seeker and stand still (= a bush); away from
-- the seeker when it comes close in sight (a bush only when it is very close); some of
-- them fetch the pieces while the seeker is far or out of sight.
function World:hidePlan(e)
    local h = self.hide
    if not h or self.match.over then return nil end
    local mem = e.hs
    if not mem then
        mem = { fetcher = math.random() < FETCH_SHARE,
                fetchAt = h.hideUntil + 5 + math.random() * 50 }
        e.hs = mem
    end
    if e.team == World.TEAM_SEEKER then
        if h.phase ~= "seek" then return nil end
        return seekPlan(self, e, mem)
    end
    local seeker = self.byId[h.seekerId]
    local seen = h.phase == "seek" and seeker and sees(self, e, seeker, SEEK_SIGHT)
    local sd = seeker and dist(e, seeker) or math.huge
    if seen and (sd < BOLT_DIST or (sd < FLEE_DIST and not e.disguised)) then -- run!
        if not mem.fleeUntil or self.time >= mem.fleeUntil or not mem.spot then
            mem.spot = pickHideSpot(self, e, seeker, true)
            mem.fleeUntil = self.time + 1
        end
        return { x = mem.spot.x, y = mem.spot.y, state = "flee" }
    end
    if e.carryingPiece then -- to the frame
        return { x = Arena.center.x, y = Arena.center.y, state = "piece" }
    end
    local safe = not seen or sd > FETCH_SAFE
    if mem.fetcher and h.phase == "seek" and self.time >= mem.fetchAt and safe then
        local best, bestD
        for _, piece in ipairs(h.pieces) do
            if not piece.placed and not piece.carrier then
                local d = dist(piece, e)
                local taken = false -- (another fetcher goes for it already)
                for _, o in ipairs(self.entities) do
                    if o ~= e and o.hs and o.hs.piece == piece.id and not o.dead then taken = true end
                end
                if not taken and (not bestD or d < bestD) then best, bestD = piece, d end
            end
        end
        mem.piece = best and best.id
        if best then return { x = best.x, y = best.y, state = "fetch" } end
    end
    mem.piece = nil
    if not mem.spot then mem.spot = pickHideSpot(self, e, seeker and h.phase == "seek" and seeker or nil) end
    local d = dist(mem.spot, e)
    if d > 10 then
        if stuckOn(mem, mem.spot, d) then
            mem.badSpot, mem.spot = mem.spot, nil
            return nil
        end
        return { x = mem.spot.x, y = mem.spot.y, state = "hide" }
    end
    mem.goal = nil
    return nil -- there: stand still (a bush in 2 s)
end

---------------------------------------------------------------------------- Flower Gardens

-- Does a circle at x, y (radius r) touch garden g (Arena.gardens)?
local function gardenOverlap(g, x, y, r)
    local cx = math.max(g.x1, math.min(x, g.x2))
    local cy = math.max(g.y1, math.min(y, g.y2))
    return (x - cx) ^ 2 + (y - cy) ^ 2 < r * r
end

-- Is x, y in garden g? (margin: px around it count too)
function World.inGarden(g, x, y, margin)
    margin = margin or 0
    return x >= g.x1 - margin and x <= g.x2 + margin and y >= g.y1 - margin and y <= g.y2 + margin
end

-- Where a circle of radius r overlapping garden g gets out: the nearest spot beyond one
-- of its open sides (the map border closes the other two)
local function outOfGarden(g, x, y, r)
    local best, bx, by
    local function try(d, nx, ny)
        if not best or d < best then best, bx, by = d, nx, ny end
    end
    if g.x1 > 0 then try(x - (g.x1 - r), g.x1 - r, y) end
    if g.x2 < Arena.width then try(g.x2 + r - x, g.x2 + r, y) end
    if g.y1 > 0 then try(y - (g.y1 - r), x, g.y1 - r) end
    if g.y2 < Arena.height then try(g.y2 + r - y, x, g.y2 + r) end
    return bx or x, by or y
end

-- Is `e` in its own garden with the fence up? (no other team's shot, bomb or blast
-- reaches it there)
function World:sheltered(e)
    local fg = self.flowerGame
    if not fg or not fg.fences[e.team] then return false end
    local g = Arena.gardens and Arena.gardens[e.team]
    return g ~= nil and World.inGarden(g, e.x, e.y, World.FENCE_HALF)
end

-- The garden (of another team than `team`, fence up) a circle at x, y touches, or nil
function World:fenceAt(x, y, r, team)
    local fg = self.flowerGame
    for t, g in ipairs(Arena.gardens or {}) do
        if t ~= team and fg.fences[t] and gardenOverlap(g, x, y, r + World.FENCE_HALF) then return g end
    end
end

-- Reset what a rowdy has of a round of Flower Gardens
local function prepareFlowers(e)
    e.driving, e.carryingFlower, e.delivered, e.fl = nil, nil, 0, nil
end

-- `to` (a player that joined, or the bot of one that left) takes over from `from`: its
-- flowers delivered, the flower it carries, its bulldozer
function handOver(self, from, to)
    to.delivered, to.driving = from.delivered or 0, from.driving
    for _, f in ipairs(self.flowerGame.flowers) do
        if f.carrier == from.id then f.carrier, to.carryingFlower = to.id, f.id end
    end
end

-- A new flower at a random free spot in the flower field (if there is one)
local function addFlower(self)
    local fg = self.flowerGame
    for _ = 1, 30 do
        local a, d = math.random() * math.pi * 2, math.sqrt(math.random()) * World.FLOWER_FIELD
        local x, y = Arena.center.x + math.cos(a) * d, Arena.center.y + math.sin(a) * d
        local ok = not Arena.hitsSolid(x, y, 26) and not Arena.inBush(x, y) and not self:boxAt(x, y, 30)
        for _, f in ipairs(fg.flowers) do
            if (f.x - x) ^ 2 + (f.y - y) ^ 2 < FLOWER_GAP * FLOWER_GAP then ok = false end
        end
        if ok then
            local f = { id = self.nextLootId, x = x, y = y, kind = math.random(4), born = self.time }
            self.nextLootId = self.nextLootId + 1
            fg.flowers[#fg.flowers + 1] = f
            self:emit("flower", { flower = f.id, x = x, y = y })
            return
        end
    end
end

-- A new round: all fences up, no flowers delivered, the first flowers in the field
function World:startFlowers()
    local fg = { fences = {}, teams = {}, flowers = {}, endAt = self.time + World.FLOWER_TIME,
        nextFlower = self.time + World.FLOWER_EVERY }
    for t = 1, World.KING_TEAMS do
        fg.fences[t] = true
        fg.teams[t] = { count = 0, delivered = 0 } -- count: towards the next bulldozer
    end
    self.flowerGame = fg
    for _, e in ipairs(self.entities) do prepareFlowers(e) end
    for _ = 1, World.FLOWER_START do addFlower(self) end
    self.match.timeLeft = World.FLOWER_TIME
end

-- Is there a fence the bulldozer of `team` could knock down?
local function fenceToKnock(self, team)
    for t = 1, World.KING_TEAMS do
        if t ~= team and self.flowerGame.fences[t] then return true end
    end
    return false
end

-- A flower carried into the own garden: count it; every DOZER_FLOWERS the carrier gets
-- a bulldozer (if there is a fence left to knock down)
local function deliver(self, i, c)
    local fg = self.flowerGame
    local f = table.remove(fg.flowers, i)
    c.carryingFlower = nil
    c.delivered = (c.delivered or 0) + 1
    local tm = fg.teams[c.team]
    tm.delivered, tm.count = tm.delivered + 1, tm.count + 1
    self:emit("deliver", { id = c.id, team = c.team, flower = f.id, n = tm.count,
        total = tm.delivered, x = c.x, y = c.y })
    if tm.count >= World.DOZER_FLOWERS then
        tm.count = 0
        if fenceToKnock(self, c.team) then
            c:clearActions()
            c.driving = { expires = self.time + World.DOZER_TIME, speed = World.DOZER_SPEED }
            self:emit("dozer", { id = c.id, team = c.team, x = c.x, y = c.y })
        end
    end
end

-- Every step: new flowers grow, carried ones follow their carrier (dropped when it is
-- knocked out, delivered in its garden), free ones are picked up; old bulldozers go
local function updateFlowers(self, dt)
    local fg = self.flowerGame
    if self.time >= fg.nextFlower then
        fg.nextFlower = fg.nextFlower + World.FLOWER_EVERY
        if #fg.flowers < World.FLOWER_MAX then addFlower(self) end
    end
    for _, e in ipairs(self.entities) do
        if e.driving and self.time >= e.driving.expires then
            e.driving = nil
            self:emit("dozerGone", { id = e.id, x = e.x, y = e.y })
        end
    end
    for i = #fg.flowers, 1, -1 do
        local f = fg.flowers[i]
        local c = f.carrier and self.byId[f.carrier]
        if f.carrier and (not c or c.dead or c.driving or c.carryingFlower ~= f.id) then
            f.carrier = nil
            if c then
                if c.carryingFlower == f.id then c.carryingFlower = nil end
                f.x, f.y = Arena.nearestOpen(c.x, c.y, 12)
                self:emit("flowerDrop", { id = c.id, flower = f.id, x = f.x, y = f.y })
            end
        elseif c then
            f.x, f.y = c.x, c.y
            if World.inGarden(Arena.gardens[c.team], c.x, c.y) then deliver(self, i, c) end
        else
            local best, bestD2
            for _, e in ipairs(self.entities) do
                local r = e.radius + World.FLOWER_REACH
                local d2 = (e.x - f.x) ^ 2 + (e.y - f.y) ^ 2
                if not e.dead and not e.driving and not e.carryingFlower and not e.burrowed
                    and not e.leap and d2 < r * r and (not bestD2 or d2 < bestD2) then
                    best, bestD2 = e, d2
                end
            end
            if best then
                f.carrier, best.carryingFlower = best.id, f.id
                self:emit("flowerUp", { id = best.id, flower = f.id, x = f.x, y = f.y })
            end
        end
    end
    self.match.timeLeft = math.max(0, fg.endAt - self.time)
end

-- The fences: a bulldozer of another team that touches one knocks it down; everybody
-- else of another team is pushed out of the garden (whatever way they came in: walking,
-- a leap, a blink, a fling)
local function updateFences(self)
    local fg = self.flowerGame
    for _, e in ipairs(self.entities) do
        if not e.dead and not e.leap then
            for t, g in ipairs(Arena.gardens) do
                local reach = e.radius + World.FENCE_HALF
                if t ~= e.team and fg.fences[t] and gardenOverlap(g, e.x, e.y, reach + (e.driving and 4 or 0)) then
                    if e.driving then
                        fg.fences[t] = false
                        e.driving = nil
                        self:emit("fenceDown", { team = t, by = e.id, x = e.x, y = e.y })
                    else
                        local x, y = outOfGarden(g, e.x, e.y, reach)
                        e.x, e.y = Arena.resolveCircle(x, y, e.radius)
                    end
                end
            end
        end
    end
end

-- Has a team been knocked out of the round, is it over? (last team up, or the time is up:
-- the team still up with the most flowers delivered wins)
local function checkFlowers(self)
    local m, fg = self.match, self.flowerGame
    if not fg then return end
    local up, left = {}, 0
    for team = 1, World.KING_TEAMS do
        up[team] = self:teamUp(team)
        if up[team] then left = left + 1 end
    end
    for team = 1, World.KING_TEAMS do
        if not up[team] and not m.place[team] then -- just went out: shares the place with
            m.place[team] = left + 1                -- any team out in the same step
            self:emit("teamOut", { team = team })
        end
    end
    m.teamsLeft = left
    if left <= 1 then
        local winner
        for team = 1, World.KING_TEAMS do
            if up[team] then winner = team; m.place[team] = 1 end
        end
        endMatch(self, nil, winner)
    elseif self.time >= fg.endAt then
        m.timeLeft = 0
        local winner, best, tie
        for team = 1, World.KING_TEAMS do
            if up[team] then
                local n = fg.teams[team].delivered
                local ahead = 0 -- (place: 1 + the teams up with more flowers)
                for other = 1, World.KING_TEAMS do
                    if up[other] and fg.teams[other].delivered > n then ahead = ahead + 1 end
                end
                m.place[team] = ahead + 1
                if not best or n > best then winner, best, tie = team, n, false
                elseif n == best then tie = true end
            end
        end
        endMatch(self, nil, not tie and winner or nil)
    end
end

-- The team whose fence a bulldozer of `e` goes for: another one still up - the one with
-- the most flowers delivered, the nearest of those (it keeps its choice while it stands)
local function dozerTarget(self, e, mem)
    local fg = self.flowerGame
    if mem.dozer and fg.fences[mem.dozer] and mem.dozer ~= e.team then return mem.dozer end
    local best, bestScore
    for t, g in ipairs(Arena.gardens) do
        if t ~= e.team and fg.fences[t] then
            local score = fg.teams[t].delivered * 1000 - math.sqrt((g.cx - e.x) ^ 2 + (g.cy - e.y) ^ 2)
            if not bestScore or score > bestScore then best, bestScore = t, score end
        end
    end
    mem.dozer = best
    return best
end

-- Does bot `e` fetch flowers? Per team the first two bots (by id) that are up; one when
-- a player is in the team
local function isFetcher(self, e)
    local bots, humans = {}, 0
    for _, o in ipairs(self.entities) do
        if o.team == e.team and not o.out then
            if not o.isBot then humans = humans + 1
            elseif not o.driving then bots[#bots + 1] = o end
        end
    end
    table.sort(bots, function(a, b) return a.id < b.id end)
    for i = 1, math.min(humans > 0 and 1 or 2, #bots) do
        if bots[i] == e then return true end
    end
    return false
end

-- What Flower Gardens bot `e` does (src/enemy.lua), or nil = fight as usual:
-- { x, y, state } = walk there (shooting at its target goes on).
-- A bulldozer drives to its fence (the corner first, then the nearest point); a carrier
-- takes its flower home; fetchers go for the nearest free flower no team mate goes for;
-- the others go after an opponent carrying a flower, else they roam the flower field.
-- Opponents in sight and close come first (except for a bulldozer and a carrier).
function World:flowerPlan(e, visible, targetDist)
    local fg = self.flowerGame
    if not fg or self.match.over then return nil end
    local mem = e.fl
    if not mem then mem = {}; e.fl = mem end
    if e.driving then
        local t = dozerTarget(self, e, mem)
        if not t then return nil end
        local g = Arena.gardens[t]
        local x = math.max(g.x1, math.min(e.x, g.x2))
        local y = math.max(g.y1, math.min(e.y, g.y2))
        if (x - e.x) ^ 2 + (y - e.y) ^ 2 > DOZER_AIM * DOZER_AIM then
            x, y = g.fence[3], g.fence[4] -- (the inner corner: open ground in front of it)
        end
        return { x = x, y = y, state = "dozer" }
    end
    if e.carryingFlower then
        local g = Arena.gardens[e.team]
        return { x = g.cx, y = g.cy, state = "flower" }
    end
    mem.flower = nil
    if visible and targetDist and targetDist < FLOWER_FIGHT then return nil end
    if isFetcher(self, e) then
        local best, bestD
        for _, f in ipairs(fg.flowers) do
            if not f.carrier then
                local taken = false -- (a team mate goes for it already)
                for _, o in ipairs(self.entities) do
                    if o ~= e and o.team == e.team and o.fl and o.fl.flower == f.id and not o.dead then taken = true end
                end
                local d = dist(f, e)
                if not taken and (not bestD or d < bestD) then best, bestD = f, d end
            end
        end
        if best then
            mem.flower = best.id
            return { x = best.x, y = best.y, state = "fetch" }
        end
    end
    local carrier, carrierD
    for _, o in ipairs(self.entities) do
        if o.carryingFlower and o.team ~= e.team and sees(self, e, o, FLOWER_NOTICE) then
            local d = dist(o, e)
            if not carrierD or d < carrierD then carrier, carrierD = o, d end
        end
    end
    if carrier then return { x = carrier.x, y = carrier.y, state = "hunt" } end
    if visible then return nil end
    local p = mem.patrol
    if not p or dist(p, e) < 60 or self.time >= p.untilT then
        local x, y = Arena.randomOpenPoint(Arena.center.x, Arena.center.y, World.FLOWER_FIELD * 0.8)
        p = { x = x, y = y, untilT = self.time + 6 }
        mem.patrol = p
    end
    return { x = p.x, y = p.y, state = "patrol" }
end

---------------------------------------------------------------------------- Yardball

local BR = World.BALL_RADIUS

-- Where a rowdy carries the ball: just in front of it, along its aim
function World.carrySpot(e)
    local d = e.radius + BR + 2
    return e.x + math.cos(e.aim) * d, e.y + math.sin(e.aim) * d
end

local function otherTeam(team)
    return team == World.TEAM_BLUE and World.TEAM_RED or World.TEAM_BLUE
end

-- The goal (= index of the team defending it) whose back a ball at x, y touches, or nil
local function goalAt(x, y)
    for team, g in ipairs(Arena.goals or {}) do
        if y >= g.y1 and y <= g.y2
            and ((g.dir < 0 and x - BR <= 0) or (g.dir > 0 and x + BR >= Arena.width)) then
            return team
        end
    end
end

-- Does a ball at x, y overlap something it bounces off? (the border has the goal mouths)
local function ballBlocked(self, x, y)
    if y - BR < 0 or y + BR > Arena.height then return true end
    if x - BR < 0 or x + BR > Arena.width then
        local g = Arena.goals and Arena.goals[1]
        if not g or y < g.y1 or y > g.y2 then return true end
        return false
    end
    return Arena.hitsSolid(x, y, BR) or self:boxAt(x, y, BR) ~= nil
end

-- Can `e` keep the ball / take it? (not knocked out, frozen, grabbed, underground or
-- invisible)
local function canHold(e)
    return not e.dead and e.frozen <= 0 and not e.heldBy and not e.burrowed and not e.vanished
end

local function dropBall(self, e)
    local ball = self.ball
    ball.carrier, ball.vx, ball.vy = nil, 0, 0
    if e then
        e.carrying = nil
        self:emit("ballDrop", { id = e.id, x = ball.x, y = ball.y })
    end
end

-- `team` scored (at x, y): count it, end the round or kick off again
local function scoreGoal(self, team, x, y)
    local ball, m = self.ball, self.match
    local by = ball.carrier or ball.lastKick
    local scorer = by and self.byId[by]
    if scorer and scorer.team == team then scorer.goals = scorer.goals + 1 end
    if scorer then scorer.carrying = nil end
    ball.carrier, ball.x, ball.y, ball.vx, ball.vy = nil, x, y, 0, 0
    m.goals[team] = m.goals[team] + 1
    self:emit("goal", { team = team, by = by, x = x, y = y })
    if m.goals[team] >= World.YARDBALL_GOALS then
        endMatch(self, nil, team)
        return
    end
    self.bullets = {}
    for _, e in ipairs(self.entities) do
        e.carrying = nil
        e:respawn() -- back to its spot (not a knockout)
    end
    kickoff(self)
end

-- Kick the ball (only its carrier): towards `angle`, rolling to `dist` px from the
-- kicker's body centre (KICK_MIN..KICK_MAX; nil = KICK_MAX). Returns true if it kicked.
function World:kick(e, angle, dist)
    local ball = self.ball
    if not ball or ball.carrier ~= e.id or e.dead then return false end
    e.aim = angle or e.aim
    local x, y = World.carrySpot(e)
    if not goalAt(x, y) then x, y = Arena.resolveCircle(x, y, BR) end
    local d = math.max(World.KICK_MIN, math.min(World.KICK_MAX, tonumber(dist) or World.KICK_MAX))
    local roll = math.max(20, d - (e.radius + BR + 2))
    local v = math.sqrt(2 * World.BALL_FRICTION * roll) -- rolls exactly `roll` px
    ball.x, ball.y = x, y
    ball.vx, ball.vy = math.cos(e.aim) * v, math.sin(e.aim) * v
    ball.carrier, e.carrying = nil, nil
    ball.lastKick = e.id
    ball.noPick[e.id] = self.time + PICKUP_DELAY
    e.recoil = 1
    self:emit("kick", { id = e.id, x = x, y = y })
    return true
end

-- The ball each step: carried, rolling (bounces, goals) or picked up
local function updateBall(self, dt)
    local ball = self.ball
    if self.kickoff > 0 then
        self.kickoff = math.max(0, self.kickoff - dt)
        return
    end
    if ball.carrier then
        local c = self.byId[ball.carrier]
        if not c or not canHold(c) then
            dropBall(self, c)
        else
            local x, y = World.carrySpot(c)
            local g = goalAt(x, y)
            if g then return scoreGoal(self, otherTeam(g), x, y) end
            ball.x, ball.y = Arena.resolveCircle(x, y, BR)
            return
        end
    end

    -- Rolling: in small steps, each axis on its own (all solids are axis-aligned boxes)
    local speed = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
    if speed > 0 then
        local steps = math.max(1, math.ceil(speed * dt / 8))
        local h = dt / steps
        local bounced = false
        for _ = 1, steps do
            local nx = ball.x + ball.vx * h
            if ballBlocked(self, nx, ball.y) then ball.vx, bounced = -ball.vx * BALL_BOUNCE, true
            else ball.x = nx end
            local ny = ball.y + ball.vy * h
            if ballBlocked(self, ball.x, ny) then ball.vy, bounced = -ball.vy * BALL_BOUNCE, true
            else ball.y = ny end
            local g = goalAt(ball.x, ball.y)
            if g then return scoreGoal(self, otherTeam(g), ball.x, ball.y) end
        end
        if bounced and speed > 150 then self:emit("bounce", { x = ball.x, y = ball.y }) end
        local k = math.max(0, speed - World.BALL_FRICTION * dt) / speed
        ball.vx, ball.vy = ball.vx * k, ball.vy * k
        if k == 0 then ball.vx, ball.vy = 0, 0 end
    end

    -- Picked up by the nearest rowdy touching it
    local best, bestD2
    for _, e in ipairs(self.entities) do
        if canHold(e) and not e.leap and not (e.push and not e.push.own)
            and not ((ball.noPick[e.id] or 0) > self.time) then
            local r = e.radius + BR + 4
            local d2 = (e.x - ball.x) ^ 2 + (e.y - ball.y) ^ 2
            if d2 < r * r and (not bestD2 or d2 < bestD2) then best, bestD2 = e, d2 end
        end
    end
    if best then
        ball.carrier, ball.vx, ball.vy = best.id, 0, 0
        best.carrying = true
        if best.bursting and best.bursting.attack == best.attack then best.bursting = nil end
        best.beamHold = 0
        self:emit("pickup", { id = best.id, x = ball.x, y = ball.y })
    end
end

-- The nearest living bot of `team` to x, y
local function nearestBot(self, team, x, y)
    local best, bestD2
    for _, e in ipairs(self.entities) do
        if e.isBot and e.team == team and not e.dead then
            local d2 = (e.x - x) ^ 2 + (e.y - y) ^ 2
            if not bestD2 or d2 < bestD2 then best, bestD2 = e, d2 end
        end
    end
    return best
end

-- What bot `e` does about the ball (Yardball; src/enemy.lua), or nil = fight as usual:
--   { kick = true, angle, dist }: kick it now; { x, y }: walk there
function World:ballPlan(e)
    local ball = self.ball
    if not ball or self.match.over then return nil end
    if ball.carrier == e.id then -- to the opponents' goal, and shoot when it's clear
        local g = Arena.goals[otherTeam(e.team)]
        local gx, gy = g.x - g.dir * 2, (g.y1 + g.y2) / 2 + (e.aimOffset or 0)
        local dx, dy = gx - e.x, gy - e.y
        local d = math.sqrt(dx * dx + dy * dy)
        local angle = math.atan2(dy, dx)
        local clear = Arena.raycast(e.x, e.y, angle, d, BR) >= d - 1
        local threat = false
        for _, o in ipairs(self.entities) do
            if o.team ~= e.team and not o.dead
                and (o.x - e.x) ^ 2 + (o.y - e.y) ^ 2 < BOT_THREAT * BOT_THREAT then
                threat = true
            end
        end
        if clear and (d <= BOT_SHOT_RANGE or (threat and d <= World.KICK_MAX + 300)) then
            return { kick = true, angle = angle + (math.random() - 0.5) * 0.12, dist = d + 80 }
        end
        if Arena.hasLineOfSight(e.x, e.y, gx, gy) then return { x = gx, y = gy } end
        -- around the cover: through the open lane in the middle
        return { x = g.x - g.dir * 600, y = (g.y1 + g.y2) / 2 }
    end
    if ball.carrier then -- an opponent has it: the nearest bot goes straight for it
        local c = self.byId[ball.carrier]
        if c and c.team ~= e.team and nearestBot(self, e.team, c.x, c.y) == e then
            return { x = c.x, y = c.y }
        end
        return nil
    end
    -- free ball: the nearest bot of each team runs to where it will be
    if nearestBot(self, e.team, ball.x, ball.y) == e then
        return { x = ball.x + ball.vx * 0.3, y = ball.y + ball.vy * 0.3 }
    end
end

----------------------------------------------------------------------------

-- Has the round been decided?
local function checkMatch(self, dt)
    local m = self.match
    if self.mode.hideseek then -- all found: the seeker wins; the time is up: the hiders
        local h = self.hide
        if not h or h.phase ~= "seek" then return end
        if not self:teamUp(World.TEAM_HIDERS) then
            endMatch(self, nil, World.TEAM_SEEKER)
        elseif self.time >= h.endAt then
            m.timeLeft = 0
            endMatch(self, nil, World.TEAM_HIDERS)
        end
        return
    end
    if self.mode.yardball then return end -- (goals: scoreGoal; no time limit)
    if self.mode.flowers then return checkFlowers(self) end
    if self.mode.king then -- the last team with somebody up wins
        local up, left = {}, 0
        for team = 1, World.KING_TEAMS do
            up[team] = self:teamUp(team)
            if up[team] then left = left + 1 end
        end
        for team = 1, World.KING_TEAMS do
            if not up[team] and not m.place[team] then -- just went out: shares the place
                m.place[team] = left + 1                 -- with any team out in the same step
                self:emit("teamOut", { team = team })
            end
        end
        m.teamsLeft = left
        if left <= 1 then
            local winner
            for team = 1, World.KING_TEAMS do
                if up[team] then winner = team; m.place[team] = 1 end
            end
            endMatch(self, nil, winner) -- (nobody left: everybody out in the same step = draw)
        end
        return
    end
    if self.mode.waves then
        local players, out = 0, 0
        for _, e in ipairs(self.entities) do
            if not e.isBot then
                players = players + 1
                if e.out then out = out + 1 end
            end
        end
        if players > 0 and out == players then endMatch(self, nil) end
        return
    end
    if self.mode.boss then -- won once the boss is out (there is no losing)
        local boss = self:boss()
        if boss and boss.out then endMatch(self, nil, World.TEAM_PLAYERS) end
        return
    end
    if self.mode.teams then -- a team reached the target, or the time is up
        local s = self:teamScores()
        local blue, red = s[World.TEAM_BLUE] or 0, s[World.TEAM_RED] or 0
        if blue >= World.TEAM_KILL_TARGET then endMatch(self, nil, World.TEAM_BLUE) return end
        if red >= World.TEAM_KILL_TARGET then endMatch(self, nil, World.TEAM_RED) return end
        m.timeLeft = m.timeLeft - dt
        if m.timeLeft <= 0 then
            m.timeLeft = 0
            endMatch(self, nil, (blue > red and World.TEAM_BLUE) or (red > blue and World.TEAM_RED) or nil)
        end
        return
    end
    -- Duel: somebody reached the kill target, or the time is up (most kills wins)
    local best, tie
    for _, e in ipairs(self.entities) do
        if not best or e.kills > best.kills then best, tie = e, false
        elseif e.kills == best.kills then tie = true end
    end
    if best and best.kills >= World.KILL_TARGET then endMatch(self, best) return end
    m.timeLeft = m.timeLeft - dt
    if m.timeLeft <= 0 then
        m.timeLeft = 0
        endMatch(self, (best and not tie and best.kills > 0) and best or nil)
    end
end

-- Next round with the same players: scores, lives and bots start over
function World:restartMatch()
    for i = #self.entities, 1, -1 do
        local e = self.entities[i]
        if e.isBot then self:remove(e) end
    end
    self.bullets, self.medpacks, self.boxes, self.coins, self.barriers = {}, {}, {}, {}, {}
    self.beacons, self.hide, self.flowerGame = {}, nil, nil
    self.boxTimer = World.BOX_FIRST
    self.wave, self.waveSize, self.waveTimer = 0, 0, 0
    for _, e in ipairs(self.entities) do
        e.kills, e.deaths, e.goals, e.out, e.charge = 0, 0, 0, false, 0
        e.fireBuffer, e.superBuffer = nil, nil
        e:respawn()
    end
    self.match = World.newMatch(self.mode)
    self:emit("matchStart", {})
    self:start()
end

-- One simulation step. inputs[id] = input table for player `id` (missing = idle).
-- After the round is over the world stands still (until restartMatch).
function World:update(dt, inputs)
    if self.match.over then
        self.time = self.time + dt
        return
    end
    local hide = self.hide
    for _, e in ipairs(self.entities) do
        if hide then e.tagCooldown = math.max(0, (e.tagCooldown or 0) - dt) end
        if hide and hide.phase == "hide" and e.id == hide.seekerId then
            e:tick(dt) -- counting with its eyes closed
        elseif e.isBot then
            e:update(dt, self)
        else
            local input = inputs[e.id] or IDLE
            if hide and e.id == hide.seekerId then -- fire = the tag (kept for a moment)
                if input.fire then e.tagBuffer = 0.25 end
                if input.aim then e.aim = input.aim end
                if e.tagBuffer then
                    e.tagBuffer = e.tagBuffer - dt
                    if self:tag(e) or e.tagBuffer <= 0 then e.tagBuffer = nil end
                end
            end
            if input.fire and self.ball and self.ball.carrier == e.id then -- fire = kick
                self:kick(e, input.aim, input.aimDist)
                e.fireBuffer = nil
                input = { dx = input.dx, dy = input.dy, aim = input.aim,
                    aimDist = input.aimDist, super = input.super }
            end
            e:update(dt, input, self.bullets)
        end
    end
    updateBarriers(self)
    if self.flowerGame then updateFences(self) end
    newBullets(self)
    updateBullets(self, dt)
    updateGoo(self, dt)
    if self.ball and not self.match.over then updateBall(self, dt) end
    updateMedpacks(self)
    updateLoot(self, dt)
    if self.mode.waves then updateWaves(self, dt) end
    if self.mode.king then
        updateBeacons(self, dt)
        updateZone(self, dt)
    end
    if self.hide then updateHide(self, dt) end
    if self.flowerGame then updateFlowers(self, dt) end
    checkMatch(self, dt)
    self.time = self.time + dt
end

return World
