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

-- Finding games: a joining device sends DISCOVER_QUERY to UDP DISCOVERY_PORT (broadcast
-- + every address of its /24 network, since some phones/routers drop broadcasts); hosts
-- answer with { game = "yard-wars", mode, players, port }. See Net.newFinder.
local Net = {}
Net.PORT = 27015
Net.DISCOVERY_PORT = 27016
local DISCOVER_QUERY = "yard-wars?1"
local FIND_INTERVAL = 2  -- seconds between queries
local FOUND_TIMEOUT = 5  -- a game disappears from the list after this long without answer
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

-- Discovery sockets are explicitly IPv4. socket.udp() leaves the address family open
-- until binding, and binding "*" gives an IPv6 socket on Android, which then can't
-- send to IPv4 addresses ("hostname nor servname provided, or not known").
local function udp4()
    return (socket.udp4 or socket.udp)()
end

-- This device's address in the local network (for "join me at ..."), or nil.
-- Connecting a UDP socket sends nothing; it only picks the outgoing interface.
function Net.localAddress()
    local udp = udp4()
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
    -- Answer discovery queries (optional: without it, joining by address still works)
    local udp = udp4()
    if udp and not udp:setsockname("0.0.0.0", Net.DISCOVERY_PORT) then udp:close(); udp = nil end
    if udp then udp:settimeout(0) end
    return setmetatable({ host = host, world = world, clients = {}, steps = 0, events = {},
        discovery = udp }, Server)
end

local function answerQueries(self)
    while true do
        local data, ip, port = self.discovery:receivefrom()
        if not data then break end
        if data == DISCOVER_QUERY then
            self.queries, self.lastQueryFrom = (self.queries or 0) + 1, ip -- shown in the HUD
            local mode = self.world.mode
            self.discovery:sendto(Codec.encode({ game = "yard-wars", mode = mode.name,
                waves = mode.waves, players = self:playerCount() + 1, port = Net.PORT }), ip, port)
        end
    end
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
    if self.discovery then answerQueries(self) end
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
    local packs = {}
    for _, m in ipairs(world.medpacks) do
        packs[#packs + 1] = { m.id, round(m.x, 10), round(m.y, 10), m.born, m.expires }
    end
    return { type = "snap", t = world.time, wave = world.wave, waveSize = world.waveSize,
        waveTimer = world.waveTimer, e = ents, m = packs }
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
    if self.discovery then self.discovery:close() end
end

---------------------------------------------------------------------------- finder

local Finder = {}
Finder.__index = Finder

-- A query to an address where no device exists waits in the socket's send buffer until
-- the network gives up on that address (~3 s). One socket for a whole /24 sweep fills
-- its buffer and further sends fail, so the sweep is split over short-lived sockets.
local CHUNK = 32        -- addresses per socket
local SOCKET_LIFE = 4   -- seconds a query socket is kept (answers come within ms)

-- Looks for hosts in the local network while it is updated. finder.games is a list of
-- { address, mode, waves, players, seen } sorted by address.
-- hints: addresses to ask first (e.g. the last joined host)
function Net.newFinder(hints)
    local probe = udp4()
    if not probe then return nil end
    probe:close()
    return setmetatable({ sockets = {}, hints = hints or {}, games = {}, byAddress = {},
        timer = 0, sent = 0, sendErrors = 0, answers = 0, lastError = nil }, Finder)
end

local function newSocket(self)
    local udp = udp4()
    if not udp then return nil end
    udp:settimeout(0)
    udp:setsockname("0.0.0.0", 0)
    udp:setoption("broadcast", true)
    self.sockets[#self.sockets + 1] = { udp = udp, created = love.timer.getTime() }
    return udp
end

local function sendAll(self, addresses)
    local udp = newSocket(self)
    if not udp then return end
    for _, ip in ipairs(addresses) do
        local ok, res, err = pcall(udp.sendto, udp, DISCOVER_QUERY, ip, Net.DISCOVERY_PORT)
        if ok and res then self.sent = self.sent + 1
        else self.sendErrors, self.lastError = self.sendErrors + 1, tostring(ok and err or res) end
    end
end

local function sendQueries(self)
    local own = Net.localAddress()
    local prefix = own and own:match("^(%d+%.%d+%.%d+)%.%d+$")
    self.network = prefix and (prefix .. ".x") -- shown on the join screen

    -- Likely hosts first: hints, games already found, broadcasts
    local first, done = {}, {}
    local function add(list, ip)
        if ip and ip ~= "" and not done[ip] then done[ip] = true; list[#list + 1] = ip end
    end
    for _, ip in ipairs(self.hints) do add(first, ip) end
    for ip in pairs(self.byAddress) do add(first, ip) end
    add(first, "255.255.255.255")
    add(first, prefix and (prefix .. ".255") or "127.0.0.1")
    sendAll(self, first)

    -- Then every address of the /24 network, CHUNK per socket
    if not prefix then return end
    local chunk = {}
    for i = 1, 254 do
        add(chunk, prefix .. "." .. i)
        if #chunk == CHUNK then sendAll(self, chunk); chunk = {} end
    end
    if #chunk > 0 then sendAll(self, chunk) end
end

local function receive(self, udp, now)
    while true do
        local data, ip = udp:receivefrom()
        if not data then break end
        local info = Codec.decode(data)
        self.answers = self.answers + 1
        if type(info) == "table" and info.game == "yard-wars" and type(ip) == "string" then
            local g = self.byAddress[ip] or { address = ip }
            g.mode = tostring(info.mode or "?")
            g.waves = info.waves == true
            g.players = tonumber(info.players) or 1
            g.seen = now
            self.byAddress[ip] = g
        end
    end
end

function Finder:update(dt)
    self.timer = self.timer - dt
    if self.timer <= 0 then
        self.timer = FIND_INTERVAL
        sendQueries(self)
    end
    local now = love.timer.getTime()
    for i = #self.sockets, 1, -1 do
        local s = self.sockets[i]
        receive(self, s.udp, now)
        if now - s.created > SOCKET_LIFE then
            s.udp:close()
            table.remove(self.sockets, i)
        end
    end
    local games = {}
    for ip, g in pairs(self.byAddress) do
        if now - g.seen > FOUND_TIMEOUT then self.byAddress[ip] = nil
        else games[#games + 1] = g end
    end
    table.sort(games, function(a, b) return a.address < b.address end)
    self.games = games
end

-- Counters for the join screen (to see where discovery fails)
function Finder:stats()
    return string.format("queries sent %d, failed %d%s, answers %d", self.sent, self.sendErrors,
        self.lastError and (" (" .. self.lastError .. ")") or "", self.answers)
end

function Finder:close()
    for _, sock in ipairs(self.sockets) do sock.udp:close() end
    self.sockets = {}
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
