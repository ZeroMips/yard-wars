-- The simulation: all rowdies (players + bots) with ids and teams, bullets, hits,
-- scores and the game mode (duel / waves). It runs in fixed steps of World.TICK.
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

-- Rounds. Duel: first to KILL_TARGET kills wins, or most kills when the time is up.
-- Team fight: the same with the kills of each team (TEAM_KILL_TARGET).
-- Waves: every player has LIVES; the round ends when all players are out.
World.KILL_TARGET = 10
World.TEAM_KILL_TARGET = 15
World.TIME_LIMIT  = 180 -- seconds
World.LIVES       = 3

local WAVE_DELAY     = 2   -- seconds between clearing a wave and the next one
local SPAWN_MIN_DIST = 600 -- bots never spawn closer than this to a player
local IDLE = { dx = 0, dy = 0 } -- input of a player that sent nothing

-- mode: entry of MODES in main.lua ({ waves = bool, ... })
function World.new(mode)
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
        nextTeam = 3, -- free-for-all: every player gets a team of their own
        time = 0,     -- simulated seconds since the start
        wave = 0, waveSize = 0,
        waveTimer = 0, -- countdown to the next wave once all bots are dead
        match = World.newMatch(mode),
    }, World)
end

-- Round state: { over = bool, timeLeft (duel), winner = entity id or nil (draw),
-- wave = wave reached (waves) }
function World.newMatch(mode)
    return { over = false, timeLeft = (not mode.waves) and World.TIME_LIMIT or nil }
end

-- Events: { kind, t = world time, x, y, ... }
--   spawn {id}  death {id, color}  step {id}  bullet {see newBullets}
--   impact {bullet, owner, color} (wall/crate)  hit {bullet, owner, victim}
--   heal {id, amount} (picked up a medpack)  super {id} (fired a super, at the muzzle)
--   matchOver {winner}  matchStart  shot {id} (normal attack, at the muzzle)
--   superReady {id} (super meter just filled up)
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
    e.kills, e.deaths = 0, 0
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
-- World:newTeam() gives a team of its own (free-for-all).
function World:addPlayer(def, x, y, team)
    return self:add(Player.new(x, y, Assets.look(def), def.stats),
        team or World.TEAM_PLAYERS, def)
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

-- Switch a player to another rowdy (resets HP and ammo)
function World:setRowdy(p, def)
    p.def = def
    p:setRowdy(Assets.look(def), def.stats)
end

-- Rebuild all looks after Assets.style changed (HP, ammo etc. stay)
function World:restyle()
    for _, e in ipairs(self.entities) do e.look = Assets.look(e.def) end
end

function World:isOpponent(a, b) return a.team ~= b.team end

function World:countBots()
    local n = 0
    for _, e in ipairs(self.entities) do
        if e.isBot then n = n + 1 end
    end
    return n
end

-- Is `e` hidden from `viewer`? (an opponent in a bush, farther than HIDE_REVEAL)
function World:isHiddenFrom(e, viewer)
    if e.dead or not self:isOpponent(e, viewer) or not Arena.inBush(e.x, e.y) then
        return false
    end
    local dx, dy = e.x - viewer.x, e.y - viewer.y
    return dx * dx + dy * dy > World.HIDE_REVEAL * World.HIDE_REVEAL
end

-- Nearest opponent of `e`. Living ones first; if all are dead, the nearest dead one
-- (bots still roam towards it). With visibleOnly, only living ones not hidden in a bush.
function World:nearestOpponent(e, visibleOnly)
    local best, bestD2, bestAlive
    for _, o in ipairs(self.entities) do
        if self:isOpponent(e, o) and not (visibleOnly and (o.dead or self:isHiddenFrom(o, e))) then
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

-- Team fight: the three spawn spots of a team (blue = left, red = mirrored right)
local function teamSpots(team)
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

local function addBot(self, team, x, y)
    local def = Rowdies.bot
    local e = self:add(Enemy.new(x, y, Assets.look(def), def.stats), team, def)
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

-- Team fight: a player joins the team with fewer players and takes a bot's place
function World:addTeamPlayer(def)
    local n = self:playersPerTeam()
    local team = ((n[World.TEAM_RED] or 0) < (n[World.TEAM_BLUE] or 0)) and World.TEAM_RED
        or World.TEAM_BLUE
    local x, y
    for _, e in ipairs(self.entities) do
        if e.isBot and e.team == team then
            x, y = e.spawnX, e.spawnY
            self:remove(e)
            break
        end
    end
    if not x then x, y = freeSpot(self, team) end
    return self:addPlayer(def, x, y, team)
end

-- A player leaves; in a team fight a bot takes over the empty place
function World:removePlayer(p)
    self:remove(p)
    if self.mode.teams then addBot(self, p.team, p.spawnX, p.spawnY) end
end

-- Kills per team
function World:teamScores()
    local s = {}
    for _, e in ipairs(self.entities) do s[e.team] = (s[e.team] or 0) + e.kills end
    return s
end

function World:spawnBots(count)
    local def = Rowdies.bot
    for i = 1, count do
        local x, y = botSpawnPoint(self, i)
        local e = self:add(Enemy.new(x, y, Assets.look(def), def.stats), World.TEAM_BOTS, def)
        e:respawn() -- pop-in animation + spawn event
    end
end

-- Every wave has one bot more than the one before.
function World:startWave()
    self.wave = self.wave + 1
    self.waveSize = math.min(self.waveSize + 1, World.MAX_BOTS)
    self:spawnBots(self.waveSize)
end

-- Call after the players were added.
function World:start()
    if self.mode.teams then -- fill both teams with bots
        for _, team in ipairs({ World.TEAM_BLUE, World.TEAM_RED }) do
            local members = 0
            for _, e in ipairs(self.entities) do
                if e.team == team then members = members + 1 end
            end
            for _ = members + 1, World.TEAM_SIZE do addBot(self, team, freeSpot(self, team)) end
        end
    elseif self.mode.waves then
        self:startWave()
    else
        self:spawnBots(1)
    end
end

local function bulletHits(b, victim)
    if victim.dead then return false end
    local dx, dy = victim.x - b.x, victim.y - b.y
    local r = victim.radius + b.radius
    return dx * dx + dy * dy < r * r
end

local function updateBullets(self, dt)
    local bullets = self.bullets
    for i = #bullets, 1, -1 do
        local b = bullets[i]
        -- Move in small sub-steps so fast bullets can't skip through targets
        local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
        local steps = math.max(1, math.ceil(speed * dt / 10))
        local remove = false

        for _ = 1, steps do
            b:update(dt / steps)
            if Arena.hitsSolid(b.x, b.y, b.wallRadius or b.radius) then
                self:emit("impact", { x = b.x, y = b.y, color = b.color, -- wall / crate
                    bullet = b.id, owner = b.owner.id })
                remove = true
                break
            elseif b.life <= 0 then
                remove = true
                break
            end
            -- Bullets hit any rowdy of another team; piercing ones each rowdy once
            local victim
            for _, e in ipairs(self.entities) do
                if e.team ~= b.team and not (b.hitIds and b.hitIds[e.id]) and bulletHits(b, e) then
                    victim = e
                    break
                end
            end
            if victim then
                self:emit("hit", { x = b.x, y = b.y, victim = victim.id,
                    bullet = b.id, owner = b.owner.id, pierce = b.pierce })
                local shooter = self.byId[b.owner.id]
                if shooter and not b.super then shooter:addCharge(b.damage) end
                if victim:takeDamage(b.damage) then
                    victim.deaths = victim.deaths + 1
                    if shooter then shooter.kills = shooter.kills + 1 end
                    if shooter and not shooter.isBot then self:dropMedpack(victim.x, victim.y) end
                    -- Waves: out of lives = no more respawns
                    if self.mode.waves and not victim.isBot and victim.deaths >= World.LIVES then
                        victim.out = true
                    end
                end
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

-- Give bullets fired in this step an id and announce them. A bullet flies in a straight
-- line, so a client can draw it from this alone: position(t) = x0 + vx * (t - t0).
local function newBullets(self)
    for _, b in ipairs(self.bullets) do
        if not b.id then
            b.id, b.t0 = self.nextBulletId, self.time
            self.nextBulletId = self.nextBulletId + 1
            self:emit("bullet", { id = b.id, owner = b.owner.id, x = b.x, y = b.y,
                vx = b.vx, vy = b.vy, life = b.life, radius = b.radius, super = b.super })
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
    self:emit("matchOver", { winner = self.match.winner, winnerTeam = winnerTeam })
end

-- Has the round been decided?
local function checkMatch(self, dt)
    local m = self.match
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
    self.bullets, self.medpacks = {}, {}
    self.wave, self.waveSize, self.waveTimer = 0, 0, 0
    for _, e in ipairs(self.entities) do
        e.kills, e.deaths, e.out, e.charge = 0, 0, false, 0
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
    for _, e in ipairs(self.entities) do
        if e.isBot then
            e:update(dt, self)
        else
            e:update(dt, inputs[e.id] or IDLE, self.bullets)
        end
    end
    newBullets(self)
    updateBullets(self, dt)
    updateMedpacks(self)
    if self.mode.waves then updateWaves(self, dt) end
    checkMatch(self, dt)
    self.time = self.time + dt
end

return World
