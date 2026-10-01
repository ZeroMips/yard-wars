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
    "flashTimer", "hitFlash", "spawnAnim" }

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
    return { t = tonumber(msg.t) or 0, wave = msg.wave, waveSize = msg.waveSize,
        waveTimer = msg.waveTimer, ents = ents, medpacks = packs }
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
        self.bullets[ev.id] = { owner = ev.owner, x0 = ev.x, y0 = ev.y, vx = ev.vx, vy = ev.vy,
            t0 = ev.t, tEnd = ev.t + (ev.life or 1), radius = ev.radius, super = ev.super }
        return
    end
    -- A hit ends the bullet, unless it pierces (flies on through rowdies)
    if (ev.kind == "impact" or (ev.kind == "hit" and not ev.pierce)) and self.bullets[ev.bullet] then
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

local function proxyFor(self, s)
    local def = Rowdies.byKey(s.key)
    local p = self.proxies[s.id]
    if not p then
        p = setmetatable({}, Rowdy)
        p:init(s.x, s.y, Assets.look(def), def.stats)
        p.def = def
        self.proxies[s.id] = p
    elseif p.def ~= def then
        p.def = def
        p:setRowdy(Assets.look(def), def.stats)
    end
    for f, v in pairs(s) do p[f] = v end
    p.dead = s.dead == true
    p.isBot = s.isBot == true
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

    -- Medpacks as of the remote time (the newest snapshot not newer than that)
    local at = self.snaps[1]
    for _, s in ipairs(self.snaps) do
        if s.t <= remoteT then at = s end
    end
    world.medpacks, world.time = at.medpacks, remoteT

    -- Bullets: straight lines from their spawn record
    world.bullets = {}
    for id, b in pairs(self.bullets) do
        local t = (b.owner == self.localId) and ownT or remoteT
        if t >= b.t0 and t < b.tEnd then
            local owner = world.byId[b.owner]
            world.bullets[#world.bullets + 1] = setmetatable({
                x = b.x0 + b.vx * (t - b.t0), y = b.y0 + b.vy * (t - b.t0),
                vx = b.vx, vy = b.vy, radius = b.radius, super = b.super,
                color = owner and owner.bulletColor or { 1, 0.85, 0.2 },
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
