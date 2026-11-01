-- Client side of a network game: rebuilds a World (src/world.lua) from what the host
-- sends, for drawing only (World:update is never called here).
--
-- Other rowdies are shown REMOTE_DELAY behind the host's newest snapshot and
-- interpolated between two snapshots, so they move smoothly despite 30 Hz updates and
-- network jitter. The own rowdy (and its bullets and effects) uses the shorter
-- OWN_DELAY: it reacts faster to the own input.
local Assets   = require("src.assets")
local Rowdy  = require("src.rowdy")
local Rowdies = require("src.rowdies")
local Bullet   = require("src.bullet")
local Net      = require("src.net")
local World    = require("src.world")

local Replica = {}
Replica.__index = Replica

local REMOTE_DELAY = 0.1
local OWN_DELAY    = 0.05
local LERPED = { "x", "y", "ammoTimer", "respawnTimer", "walkPhase", "walkBlend", "recoil",
    "flashTimer", "hitFlash", "spawnAnim", "frozen", "air", "rooted" }

function Replica.new()
    return setmetatable({
        snaps = {},    -- received snapshots, oldest first (entities keyed by id)
        pending = {},  -- world events waiting for their time
        bullets = {},  -- bullet id -> spawn record
        proxies = {},  -- entity id -> Rowdy used for drawing
        offset = nil,  -- host world time minus local clock
    }, Replica)
end

local function decodeSnap(msg)
    local ents = {}
    if type(msg.e) ~= "table" then return nil end
    for _, s in pairs(msg.e) do
        if type(s) == "table" then
            local e = {}
            for i, f in ipairs(Net.FIELDS) do e[f] = s[i] end
            if type(e.id) == "number" and Rowdies.byKey(e.key) then ents[e.id] = e end
        end
    end
    local packs = {}
    for _, m in pairs(type(msg.m) == "table" and msg.m or {}) do
        if type(m) == "table" and tonumber(m[2]) and tonumber(m[3]) then
            packs[#packs + 1] = { id = m[1], x = m[2], y = m[3],
                born = tonumber(m[4]) or 0, expires = tonumber(m[5]) or 0 }
        end
    end
    local boxes, coins = {}, {}
    for _, x in pairs(type(msg.b) == "table" and msg.b or {}) do
        if type(x) == "table" and tonumber(x[2]) and tonumber(x[3]) then
            boxes[#boxes + 1] = { id = x[1], x = x[2], y = x[3], hp = tonumber(x[4]) or 1,
                born = tonumber(x[5]) or 0, hitAt = tonumber(x[6]) }
        end
    end
    for _, c in pairs(type(msg.c) == "table" and msg.c or {}) do
        if type(c) == "table" and tonumber(c[2]) and tonumber(c[3]) then
            coins[#coins + 1] = { id = c[1], x = c[2], y = c[3], ox = tonumber(c[4]) or c[2],
                oy = tonumber(c[5]) or c[3], born = tonumber(c[6]) or 0,
                expires = tonumber(c[7]) or 0 }
        end
    end
    local walls = {} -- the Officer's barriers
    for _, w in pairs(type(msg.w) == "table" and msg.w or {}) do
        if type(w) == "table" and tonumber(w[1]) and tonumber(w[3]) and #w >= 7 then
            local pts = {}
            for i = 4, #w do pts[#pts + 1] = tonumber(w[i]) or 0 end
            walls[#walls + 1] = { id = w[1], team = tonumber(w[2]), expires = tonumber(w[3]), points = pts }
        end
    end
    local ball -- (Yardball)
    local y = msg.y
    if type(y) == "table" and tonumber(y[1]) and tonumber(y[2]) then
        ball = { x = y[1], y = y[2], carrier = tonumber(y[3]) ~= 0 and tonumber(y[3]) or nil,
            vx = tonumber(y[4]) or 0, vy = tonumber(y[5]) or 0, kickoff = tonumber(y[6]) or 0 }
    end
    local zone -- (King of the Yard: the fog's circle; its radius follows from the time)
    local z = msg.z
    if type(z) == "table" and #z >= 8 then
        local ok = true
        for i = 1, 8 do ok = ok and tonumber(z[i]) ~= nil end
        if ok then
            zone = { x = z[1], y = z[2], r0 = z[3], r1 = z[4], startAt = z[5], endAt = z[6],
                finalAt = z[7], finalEnd = z[8] }
        end
    end
    local hearts = {}
    for _, h in pairs(type(msg.h) == "table" and msg.h or {}) do
        if type(h) == "table" and tonumber(h[4]) and tonumber(h[5]) then
            hearts[#hearts + 1] = { id = h[1], team = tonumber(h[2]), owner = tonumber(h[3]),
                x = h[4], y = h[5], expires = tonumber(h[6]) or 0, progress = tonumber(h[7]) or 0 }
        end
    end
    local hide -- (Hide and seek)
    local k = msg.k
    if type(k) == "table" and tonumber(k[1]) and tonumber(k[3]) and tonumber(k[4]) then
        hide = { seekerId = tonumber(k[1]), phase = tonumber(k[2]) == 2 and "seek" or "hide",
            hideUntil = tonumber(k[3]), endAt = tonumber(k[4]), hintUntil = tonumber(k[5]) or 0,
            placed = tonumber(k[6]) or 0, pieces = {} }
        for _, p in pairs(type(k[7]) == "table" and k[7] or {}) do
            if type(p) == "table" and tonumber(p[1]) and tonumber(p[2]) and tonumber(p[3]) then
                hide.pieces[#hide.pieces + 1] = { id = tonumber(p[1]), x = p[2], y = p[3],
                    carrier = tonumber(p[4]) ~= 0 and tonumber(p[4]) or nil, placed = tonumber(p[5]) == 1 }
            end
        end
    end
    local flowerGame -- (Flower Gardens)
    local f = msg.f
    if type(f) == "table" and tonumber(f[1]) and type(f[2]) == "table" and type(f[3]) == "table" then
        flowerGame = { endAt = tonumber(f[1]), fences = {}, teams = {}, flowers = {} }
        for t = 1, World.KING_TEAMS do
            flowerGame.fences[t] = tonumber(f[2][t]) == 1
            flowerGame.teams[t] = { count = tonumber(f[3][2 * t - 1]) or 0,
                delivered = tonumber(f[3][2 * t]) or 0 }
        end
        for _, x in pairs(type(f[4]) == "table" and f[4] or {}) do
            if type(x) == "table" and tonumber(x[1]) and tonumber(x[2]) and tonumber(x[3]) then
                flowerGame.flowers[#flowerGame.flowers + 1] = { id = tonumber(x[1]), x = x[2], y = x[3],
                    carrier = tonumber(x[4]) ~= 0 and tonumber(x[4]) or nil, kind = tonumber(x[5]) or 1 }
            end
        end
    end
    local m = type(msg.match) == "table" and msg.match or {}
    local place
    if type(m.place) == "table" then
        place = {}
        for i = 1, World.KING_TEAMS do
            local v = tonumber(m.place[i])
            place[i] = v and v > 0 and v or nil
        end
    end
    local goals = type(m.goals) == "table"
        and { tonumber(m.goals[1]) or 0, tonumber(m.goals[2]) or 0 } or nil
    return { t = tonumber(msg.t) or 0, wave = msg.wave, waveSize = msg.waveSize,
        waveTimer = msg.waveTimer, ents = ents, medpacks = packs, boxes = boxes, coins = coins,
        ball = ball, barriers = walls, zone = zone, beacons = hearts, hide = hide, flowerGame = flowerGame,
        match = { over = m.over == true, timeLeft = tonumber(m.timeLeft),
                  winner = tonumber(m.winner), winnerTeam = tonumber(m.winnerTeam),
                  wave = tonumber(m.wave), goals = goals, place = place,
                  teamsLeft = tonumber(m.teamsLeft) } }
end

-- Feed the messages from Client:takeInbox()
function Replica:receive(messages)
    for _, msg in ipairs(messages) do
        if msg.type == "welcome" then
            self.localId = msg.id
            self.world = World.new(type(msg.mode) == "table" and msg.mode or {})
        elseif msg.type == "snap" then
            local snap = decodeSnap(msg)
            local last = self.snaps[#self.snaps]
            if snap and (not last or snap.t > last.t) then
                self.snaps[#self.snaps + 1] = snap
                -- Clock sync: a snapshot that arrives "early" means less delay, so jump
                -- to it; a late one pulls the estimate back within a few snapshots
                -- (network delay only ever adds; the host's clock also falls behind
                -- when it has a hitch, see MAX_STEPS in main.lua)
                local o = snap.t - love.timer.getTime()
                if not self.offset or o > self.offset then self.offset = o
                else self.offset = self.offset + (o - self.offset) * 0.1 end
            end
        elseif msg.type == "events" and type(msg.list) == "table" then
            for _, ev in ipairs(msg.list) do
                if type(ev) == "table" and tonumber(ev.t) then self:addEvent(ev) end
            end
        end
    end
end

function Replica:addEvent(ev)
    if ev.kind == "bullet" then
        -- legs: straight pieces of the flight (a boomerang gets a second one at its turn)
        self.bullets[ev.id] = { owner = ev.owner, t0 = ev.t,
            legs = { { t0 = ev.t, x0 = ev.x, y0 = ev.y, vx = ev.vx, vy = ev.vy } },
            tEnd = ev.t + (ev.life or 1), radius = ev.radius, super = ev.super,
            lob = ev.lob == true, flight = tonumber(ev.life) or 1,
            projectile = type(ev.projectile) == "string" and ev.projectile or nil }
        return
    end
    local turned = ev.kind == "turn" and self.bullets[ev.bullet]
    if turned and tonumber(ev.x) and tonumber(ev.vx) and tonumber(ev.vy) then
        local legs = turned.legs
        legs[#legs + 1] = { t0 = ev.t, x0 = ev.x, y0 = ev.y, vx = ev.vx, vy = ev.vy }
        turned.tEnd = ev.t + (tonumber(ev.life) or 0)
    end
    -- A hit ends the bullet, unless it pierces (flies on through rowdies and boxes);
    -- a bomb ends with its blast
    local hit = ev.kind == "hit" or ev.kind == "boxHit"
    if (ev.kind == "impact" or ev.kind == "blast" or (hit and not ev.pierce)) and self.bullets[ev.bullet] then
        local b = self.bullets[ev.bullet]
        b.tEnd = math.min(b.tEnd, ev.t)
    end
    self.pending[#self.pending + 1] = ev
end

-- Does this concern the own rowdy? Then it runs on the own (shorter) delay.
function Replica:isOwn(ev)
    local id = self.localId
    return ev.id == id or ev.owner == id or ev.victim == id
end

local function lerpAngle(a, b, k)
    local d = (b - a + math.pi) % (2 * math.pi) - math.pi
    return a + d * k
end

-- State of entity `id` at time t (interpolated), or nil if it doesn't exist then
function Replica:sample(id, t)
    local snaps = self.snaps
    local i = #snaps
    while i > 1 and snaps[i - 1].t >= t do i = i - 1 end
    local s1 = snaps[i]
    local s0 = snaps[i - 1]
    local e1 = s1.ents[id]
    if not e1 then return nil end
    local e0 = s0 and s0.ents[id]
    if not e0 or t >= s1.t then return e1 end
    local k = math.max(0, (t - s0.t) / (s1.t - s0.t))
    local e = {}
    for f, v in pairs(e0) do e[f] = v end -- discrete values: from the older snapshot
    for _, f in ipairs(LERPED) do
        if e0[f] and e1[f] then e[f] = e0[f] + (e1[f] - e0[f]) * k end
    end
    e.aim = lerpAngle(e0.aim, e1.aim, k)
    return e
end

-- The ball at time t: interpolated between two snapshots (a jump - a goal, a kick-off -
-- is not smoothed); a carried one sits in front of its carrier's proxy (see update)
function Replica:sampleBall(t)
    local snaps = self.snaps
    local i = #snaps
    while i > 1 and snaps[i - 1].t >= t do i = i - 1 end
    local b1, s0 = snaps[i].ball, snaps[i - 1]
    local b0 = s0 and s0.ball
    if not b1 then return nil end
    local ball = { x = b1.x, y = b1.y, vx = b1.vx, vy = b1.vy, carrier = b1.carrier,
        kickoff = b1.kickoff }
    if b0 and t < snaps[i].t and not b0.carrier and not b1.carrier
        and (b1.x - b0.x) ^ 2 + (b1.y - b0.y) ^ 2 < 200 * 200 then
        local k = math.max(0, (t - s0.t) / (snaps[i].t - s0.t))
        ball.x, ball.y = b0.x + (b1.x - b0.x) * k, b0.y + (b1.y - b0.y) * k
    end
    return ball
end

local function proxyFor(self, s)
    local def = Rowdies.byKey(s.key)
    local p = self.proxies[s.id]
    if not p then
        p = setmetatable({}, Rowdy)
        p:init(s.x, s.y, Assets.look(def, s.skin), def.stats)
        p.def = def
        if s.boss == true then -- as big and strong as on the host (addBoss in src/world.lua)
            p.look = World.bossLook(def)
            p.maxHp = p.maxHp * World.BOSS_HP
            p.radius = p.radius * World.BOSS_SIZE
        end
        self.proxies[s.id] = p
    elseif p.def ~= def or p.skin ~= s.skin then
        p.def = def
        p:setRowdy(Assets.look(def, s.skin), def.stats)
    end
    for f, v in pairs(s) do p[f] = v end
    p.dead = s.dead == true
    p.isBot = s.isBot == true
    p.out = s.out == true
    p.boss = s.boss == true
    p.frozen = tonumber(s.frozen) or 0
    p.air = tonumber(s.air) or 0
    p.burrowed = s.burrowed == true or nil -- (Rowdy:untouchable checks for nil)
    p.beamLen = tonumber(s.beam) or 0
    p.grabbing = s.grabbing == true
    p.heldBy = s.held == true or nil
    p.vanished = s.vanished == true or nil
    p.skin, p.trail, p.title, p.badge = s.skin, s.trail, s.title, s.badge -- nil = none
    p.goals = tonumber(s.goals) or 0
    p.rooted = tonumber(s.rooted) or 0
    p.goo = s.goo == true or nil
    p.disguised = s.disguised == true or nil
    p.placed = tonumber(s.placed) or 0
    p.foundAt = tonumber(s.foundAt)
    p.carryingFlower = tonumber(s.carryingFlower)
    p.driving = tonumber(s.driving) and { expires = tonumber(s.driving) } or nil
    p.delivered = tonumber(s.delivered) or 0
    return p
end

-- Rebuild self.world for this frame. Returns the events that are due (to be turned
-- into effects), or nil while nothing has arrived yet.
function Replica:update()
    local world, newest = self.world, self.snaps[#self.snaps]
    if not world or not newest or not self.localId then return nil end

    local now = love.timer.getTime() + self.offset
    local remoteT, ownT = now - REMOTE_DELAY, now - OWN_DELAY

    -- Rowdies: everybody in the newest snapshot, sampled at their own time
    world.entities, world.byId = {}, {}
    for id in pairs(newest.ents) do
        local s = self:sample(id, id == self.localId and ownT or remoteT)
        if s then
            local p = proxyFor(self, s)
            p.world = world
            world.entities[#world.entities + 1] = p
            world.byId[id] = p
        end
    end
    for id in pairs(self.proxies) do
        if not newest.ents[id] then self.proxies[id] = nil end
    end
    table.sort(world.entities, function(a, b) return a.id < b.id end)
    world.wave, world.waveSize, world.waveTimer = newest.wave, newest.waveSize, newest.waveTimer
    world.match = newest.match

    -- The ball (Yardball): as of the remote time; carried = in front of the carrier
    local ball = newest.ball and self:sampleBall(remoteT)
    world.ball, world.kickoff = ball, ball and ball.kickoff or 0
    for _, p in ipairs(world.entities) do p.carrying = nil end
    local carrier = ball and ball.carrier and world.byId[ball.carrier]
    if carrier then
        carrier.carrying = true
        ball.x, ball.y = World.carrySpot(carrier)
    elseif ball then
        ball.carrier = nil
    end

    -- Medpacks, loot boxes and coins as of the remote time (the newest snapshot not
    -- newer than that)
    local at = self.snaps[1]
    for _, s in ipairs(self.snaps) do
        if s.t <= remoteT then at = s end
    end
    world.medpacks, world.boxes, world.coins, world.time = at.medpacks, at.boxes, at.coins, remoteT
    world.barriers = at.barriers or {}
    world.beacons = at.beacons or {}
    world.zone = newest.zone
    if world.zone then world.zone.r = World.zoneRadius(world.zone, remoteT) end
    -- Hide and seek: as of the remote time; a carried piece sits on its carrier's proxy
    world.hide = at.hide or newest.hide
    for _, p in ipairs(world.entities) do p.carryingPiece = nil end
    for _, piece in ipairs(world.hide and world.hide.pieces or {}) do
        local c = piece.carrier and world.byId[piece.carrier]
        if c then piece.x, piece.y, c.carryingPiece = c.x, c.y, piece.id end
    end
    -- Flower Gardens: as of the remote time; a carried flower sits on its carrier's proxy
    world.flowerGame = at.flowerGame or newest.flowerGame
    for _, f in ipairs(world.flowerGame and world.flowerGame.flowers or {}) do
        local c = f.carrier and world.byId[f.carrier]
        if c then f.x, f.y = c.x, c.y end
    end

    -- Bullets: straight lines from their spawn record
    world.bullets = {}
    for id, b in pairs(self.bullets) do
        local t = (b.owner == self.localId) and ownT or remoteT
        if t >= b.t0 and t < b.tEnd then
            local owner = world.byId[b.owner]
            local leg = b.legs[1]
            for _, l in ipairs(b.legs) do
                if l.t0 <= t then leg = l end
            end
            world.bullets[#world.bullets + 1] = setmetatable({
                x = leg.x0 + leg.vx * (t - leg.t0), y = leg.y0 + leg.vy * (t - leg.t0),
                vx = leg.vx, vy = leg.vy, radius = b.radius, super = b.super,
                color = owner and owner.bulletColor or { 1, 0.85, 0.2 },
                trail = owner and owner.trail, projectile = b.projectile,
                lob = b.lob, flight = b.flight, life = b.t0 + b.flight - t,
            }, Bullet)
        elseif remoteT > b.tEnd and ownT > b.tEnd then
            self.bullets[id] = nil
        end
    end

    -- Events whose time has come
    local due, keep = {}, {}
    for _, ev in ipairs(self.pending) do
        if ev.t <= (self:isOwn(ev) and ownT or remoteT) then due[#due + 1] = ev
        else keep[#keep + 1] = ev end
    end
    self.pending = keep

    -- Drop snapshots nobody needs any more
    local oldest = math.min(remoteT, ownT)
    while #self.snaps > 2 and self.snaps[2].t < oldest do table.remove(self.snaps, 1) end

    return due
end

-- The own rowdy (proxy), or nil
function Replica:player()
    return self.world and self.world.byId[self.localId]
end

return Replica
