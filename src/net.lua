-- LAN multiplayer over enet (built into LÖVE). The host runs the World (src/world.lua)
-- and a Net server next to it; clients only send their input and draw what the host
-- sends (see src/replica.lua).
--
-- Messages (tables, encoded with src/codec.lua):
--   client -> host   hello {rowdy}          reliable, once after connecting
--                    input {dx, dy, aim, fire} unreliable, every frame; fire is a
--                                             counter, so a lost packet loses no shot
--                    rowdy {index}          reliable
--   host -> client   welcome {id, mode}       reliable
--                    events {list}            reliable, world events (with world time t)
--                    snap {t, wave, ..., e}   unreliable, SNAPSHOT_EVERY steps
local enet     = require("enet")
local socket   = require("socket")
local Codec    = require("src.codec")
local Rowdies = require("src.rowdies")

local Net = {}
Net.PORT = 27015
Net.MAX_CLIENTS = 7
Net.SNAPSHOT_EVERY = 2 -- simulation steps per snapshot (30 Hz)
Net.CONNECT_TIMEOUT = 5

local CH_RELIABLE, CH_FAST = 0, 1

-- Entity fields in a snapshot (sent as an array in this order)
Net.FIELDS = { "id", "team", "key", "x", "y", "aim", "hp", "ammo", "ammoTimer", "dead",
    "respawnTimer", "walkPhase", "walkBlend", "recoil", "flashTimer", "flashSize",
    "hitFlash", "spawnAnim", "kills", "deaths", "isBot" }

local function send(peer, msg, reliable)
    peer:send(Codec.encode(msg), reliable and CH_RELIABLE or CH_FAST,
        reliable and "reliable" or "unreliable")
end

-- Notice a dead connection within a few seconds (enet's default is up to 30 s)
local function setTimeout(peer) peer:timeout(32, 2000, 6000) end

-- This device's address in the local network (for "join me at ..."), or nil.
-- Connecting a UDP socket sends nothing; it only picks the outgoing interface.
function Net.localAddress()
    local udp = socket.udp()
    if not udp then return nil end
    udp:setpeername("8.8.8.8", 80)
    local ip = udp:getsockname()
    udp:close()
    if not ip or ip == "0.0.0.0" then return nil end
    return ip
end

local function clampAxis(v)
    v = tonumber(v) or 0
    return math.max(-1, math.min(1, v))
end

---------------------------------------------------------------------------- server

local Server = {}
Server.__index = Server

-- Returns the server, or nil + error message (e.g. port already in use)
function Net.newServer(world)
    local host = enet.host_create("*:" .. Net.PORT, Net.MAX_CLIENTS, 2)
    if not host then return nil, "Port " .. Net.PORT .. " is in use" end
    return setmetatable({ host = host, world = world, clients = {}, steps = 0, events = {} },
        Server)
end

function Server:playerCount()
    local n = 0
    for _, c in pairs(self.clients) do
        if c.id then n = n + 1 end
    end
    return n
end

local function receive(self, peer, msg)
    local c, world = self.clients[peer], self.world
    if not c or type(msg) ~= "table" then return end
    if msg.type == "hello" and not c.id then
        local def = Rowdies[tonumber(msg.rowdy)] or Rowdies[1]
        -- Waves: everybody against the bots; duel: free-for-all
        local team = (not world.mode.waves) and world:newTeam() or nil
        local x, y = world:playerSpawn()
        local p = world:addPlayer(def, x, y, team)
        p:respawn() -- pop-in + spawn event
        c.id, c.fireSeen = p.id, 0
        send(peer, { type = "welcome", id = p.id,
            mode = { name = world.mode.name, waves = world.mode.waves } }, true)
    elseif msg.type == "input" and c.id then
        c.input = msg
    elseif msg.type == "rowdy" and c.id then
        local def, p = Rowdies[tonumber(msg.index)], world:get(c.id)
        if def and p then world:setRowdy(p, def) end
    end
end

-- Call once per frame before stepping the world
function Server:service()
    while true do
        local ev = self.host:service(0)
        if not ev then break end
        if ev.type == "connect" then
            setTimeout(ev.peer)
            self.clients[ev.peer] = {}
        elseif ev.type == "receive" then
            receive(self, ev.peer, Codec.decode(ev.data))
        elseif ev.type == "disconnect" then
            local c = self.clients[ev.peer]
            local p = c and c.id and self.world:get(c.id)
            if p then self.world:remove(p) end
            self.clients[ev.peer] = nil
        end
    end
end

-- Add the remote players' commands for the next step to `inputs`
function Server:addInputs(inputs)
    for _, c in pairs(self.clients) do
        local i = c.input
        if c.id and i then
            local fire = tonumber(i.fire) or 0
            inputs[c.id] = { dx = clampAxis(i.dx), dy = clampAxis(i.dy),
                aim = tonumber(i.aim), fire = fire ~= c.fireSeen }
            c.fireSeen = fire
        end
    end
end

local function round(v, k) return math.floor(v * k + 0.5) / k end

local function snapshot(world)
    local ents = {}
    for _, e in ipairs(world.entities) do
        local s = {}
        for i, f in ipairs(Net.FIELDS) do s[i] = e[f] end
        s[3] = Rowdies.key(e.def)
        s[4], s[5], s[6] = round(e.x, 10), round(e.y, 10), round(e.aim, 1000)
        s[21] = e.isBot or false
        ents[#ents + 1] = s
    end
    return { type = "snap", t = world.time, wave = world.wave, waveSize = world.waveSize,
        waveTimer = world.waveTimer, e = ents }
end

-- Call after every world step with the events of that step
function Server:afterStep(events)
    for _, ev in ipairs(events) do self.events[#self.events + 1] = ev end
    self.steps = self.steps + 1
    if self.steps % Net.SNAPSHOT_EVERY ~= 0 then return end

    local snap = Codec.encode(snapshot(self.world))
    local evs = #self.events > 0 and Codec.encode({ type = "events", list = self.events })
    self.events = {}
    for peer, c in pairs(self.clients) do
        if c.id then
            if evs then peer:send(evs, CH_RELIABLE, "reliable") end
            peer:send(snap, CH_FAST, "unreliable")
        end
    end
    self.host:flush() -- send now, not at the next service() call
end

function Server:close()
    for peer in pairs(self.clients) do peer:disconnect_now() end
    self.host:flush()
    self.host:destroy()
end

---------------------------------------------------------------------------- client

local Client = {}
Client.__index = Client

-- state: "connecting" -> "joined" (after welcome) -> "closed" (see .error)
function Net.newClient(address, rowdyIndex)
    local host = enet.host_create()
    if not host then return nil, "Network not available" end
    local ok, peer = pcall(host.connect, host, address .. ":" .. Net.PORT, 2)
    if not ok or not peer then
        host:destroy()
        return nil, "Bad address: " .. address
    end
    return setmetatable({ host = host, peer = peer, state = "connecting",
        started = love.timer.getTime(), rowdy = rowdyIndex, fire = 0,
        inbox = {} }, Client)
end

-- Handles network traffic; received welcome/events/snap messages are appended to
-- self.inbox for the replica.
function Client:service()
    if self.state == "closed" then return end
    while true do
        local ok, ev = pcall(self.host.service, self.host, 0)
        if not ok then self:fail("Network error") return end
        if not ev then break end
        if ev.type == "connect" then
            setTimeout(self.peer)
            send(self.peer, { type = "hello", rowdy = self.rowdy }, true)
        elseif ev.type == "receive" then
            local msg = Codec.decode(ev.data)
            if type(msg) == "table" then
                if msg.type == "welcome" then
                    self.state, self.id, self.mode = "joined", msg.id, msg.mode
                end
                self.inbox[#self.inbox + 1] = msg
            end
        elseif ev.type == "disconnect" then
            self:fail(self.state == "connecting" and "Could not connect" or "Connection lost")
            return
        end
    end
    if self.state == "connecting"
        and love.timer.getTime() - self.started > Net.CONNECT_TIMEOUT then
        self:fail("Could not connect (no answer)")
    end
end

function Client:fail(message)
    self.error = self.error or message
    self:close()
end

-- Returns the received messages since the last call
function Client:takeInbox()
    local inbox = self.inbox
    self.inbox = {}
    return inbox
end

-- input: from Controls.get (fire = a new shot this frame)
function Client:sendInput(input)
    if self.state ~= "joined" then return end
    if input.fire then self.fire = self.fire + 1 end
    send(self.peer, { type = "input", dx = input.dx, dy = input.dy, aim = input.aim,
        fire = self.fire })
    self.host:flush()
end

function Client:selectRowdy(index)
    self.rowdy = index
    if self.state == "joined" then send(self.peer, { type = "rowdy", index = index }, true) end
end

-- Round-trip time in ms
function Client:ping() return self.peer:round_trip_time() end

function Client:close()
    if self.state == "closed" then return end
    self.state = "closed"
    self.peer:disconnect_now()
    self.host:flush()
    self.host:destroy()
end

return Net
