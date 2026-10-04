-- Self-update over plain http (LÖVE has no https) with an RSA signature check.
--
-- Published builds (tools/publish.sh) live in URL: yard-wars-<build>.love plus latest.txt,
-- a signed manifest (build, version, file, size, sha256, sig = RSA signature over all
-- bytes before the "sig" line). On every start a thread (src/updater_thread.lua) fetches
-- latest.txt, checks the signature and, for a newer build, downloads the .love into the
-- save folder as update-<build>.love and checks size + sha256.
--
-- update.txt in the save folder says which downloaded build to use:
--   build 40 / file update-40.love / state ok|trying / bad <builds that crashed>
-- On the next start (or right away via love.event.quit("restart") when it arrives in the
-- lobby) Updater.boot(), the first line of main.lua, mounts that file over the game source
-- and runs its main.lua instead. state "trying" is written before that and set back to
-- "ok" once the build has run for a moment: a start that finds "trying" knows the build
-- crashed, marks it bad and runs the built-in game.
--
-- IMPORTANT: boot() of the build installed by hand on a device runs on every start, before
-- any update - keep it simple and keep update.txt compatible.
--
-- Only builds made by tools/build.sh have a build.txt; without one (git checkout) nothing
-- happens. Testing: --update-url <url> (with the trailing /), --no-update.
local Updater = {}

Updater.URL = "http://yardwars.zeromips.org/updates/"
-- Modulus (hex) of the publishing key (tools/publish.sh --init-key prints it)
Updater.PUBLIC_KEY = "9B7BBD3C86C5D362FEEBF58706BA5EA012B91D4DCA074FB91DFA8D2B3784E163A3A822276A2F4AD46C717AC8F29DE6754ED224143BBFF3FA6C9C0AF836E12FAADD2291D7083CC0C2373A766DEAB5EA1A7144771475CFF73AD0014B643CB9DFE811A57FF90840819159B7745235528A9B5FB1AF62086C266AFE7F06AD803C2FE7C874FC44D6D65D9C777911C222F1EF2FE8EE064DE1986C9F1D566B4841CF59B5F1CEDF84125D1E5987DE9B0DEF0F4E067C018456C80799D8DDF917CE636769DC05E61F4BA38E43A7C0BD092E231A1B98428BFE72DB5A911CA70D313F9CBE5FBD58E41BFE126F8619591CA5A2CD6C7B990ADB00E40CC2D8BD03C4ACFD08437823"

local STATE_FILE = "update.txt"
local CONFIRM_AFTER = 3 -- seconds a mounted build has to run before it counts as working

Updater.status = nil -- short text for the lobby ("up to date", ...)
Updater.ready = nil  -- build number downloaded and ready to use (restart to switch)

local channel, thread
local runTime = 0
local confirmed = false

-- Build number of the running game (build.txt, the mounted update's wins), nil = dev
function Updater.build()
    local s = love.filesystem.getInfo("build.txt") and love.filesystem.read("build.txt")
    return s and tonumber(s:match("%d+"))
end

local function hasArg(name, args)
    for i, a in ipairs(args or arg or {}) do
        if a == name then return true, (args or arg)[i + 1] end
    end
    return false
end

local function readState()
    local st = { bad = {} }
    local s = love.filesystem.getInfo(STATE_FILE) and love.filesystem.read(STATE_FILE) or ""
    for line in s:gmatch("[^\n]+") do
        local key, value = line:match("^(%a+) *(.-)%s*$")
        if key == "build" then st.build = tonumber(value)
        elseif key == "file" then st.file = value:match("^update%-%d+%.love$")
        elseif key == "state" then st.state = value
        elseif key == "bad" then
            for b in value:gmatch("%d+") do st.bad[tonumber(b)] = true end
        end
    end
    return st
end

local function writeState(st)
    local bad = {}
    for b in pairs(st.bad) do bad[#bad + 1] = b end
    table.sort(bad)
    local lines = {}
    if st.build and st.file then
        lines[#lines + 1] = "build " .. st.build
        lines[#lines + 1] = "file " .. st.file
        lines[#lines + 1] = "state " .. (st.state or "ok")
    end
    if #bad > 0 then lines[#lines + 1] = "bad " .. table.concat(bad, " ") end
    love.filesystem.write(STATE_FILE, table.concat(lines, "\n") .. "\n")
end

-- Delete downloaded builds in the save folder except `keep`
local function cleanup(keep)
    local save = love.filesystem.getSaveDirectory()
    for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
        if name ~= keep and name:match("^update%-%d+%.love$")
            and love.filesystem.getRealDirectory(name) == save then
            love.filesystem.remove(name)
        end
    end
end

-- First line of main.lua: runs a downloaded newer build instead of this one if there is
-- one. Returns true if it did (main.lua must return right away then).
function Updater.boot()
    if YARD_WARS_UPDATE then return false end -- we are the mounted build: already booted
    local own = Updater.build()
    if not own or hasArg("--no-update") then return false end
    local st = readState()
    local usable = st.build and st.file and st.build > own and not st.bad[st.build]
        and love.filesystem.getInfo(st.file)
    if usable and st.state == "trying" then -- the last start of this build never got going
        st.bad[st.build] = true
        usable = false
    end
    if not usable then
        if st.build then
            st.build, st.file, st.state = nil, nil, nil
            writeState(st)
        end
        cleanup(nil)
        return false
    end
    cleanup(st.file)
    st.state = "trying"
    writeState(st)
    if not love.filesystem.mount(st.file, "/") then return false end -- "trying": bad next time
    -- Modules of this build already loaded (this one) must come from the update
    for name in pairs(package.loaded) do
        if name:match("^src%.") then package.loaded[name] = nil end
    end
    YARD_WARS_UPDATE = st.build
    assert(love.filesystem.load("main.lua"))()
    return true
end

-- Start the check in the background (from love.load)
function Updater.start(args)
    local own = Updater.build()
    if not own or hasArg("--no-update", args) then return end
    local _, url = hasArg("--update-url", args)
    local bad = {}
    for b in pairs(readState().bad) do bad[#bad + 1] = b end
    channel = love.thread.getChannel("updater")
    channel:clear()
    thread = love.thread.newThread("src/updater_thread.lua")
    thread:start(url or Updater.URL, own, table.concat(bad, " "), Updater.PUBLIC_KEY)
    Updater.status = "checking for updates"
end

-- Every frame: confirms a mounted build after a few seconds, reads the check's progress
function Updater.update(dt)
    runTime = runTime + dt
    if YARD_WARS_UPDATE and not confirmed and runTime > CONFIRM_AFTER then
        confirmed = true
        local st = readState()
        if st.build == YARD_WARS_UPDATE and st.state == "trying" then
            st.state = "ok"
            writeState(st)
        end
    end
    if not channel then return end
    local msg = channel:pop()
    while msg do
        local what, rest = msg:match("^(%S+) ?(.*)$")
        if what == "uptodate" then
            Updater.status = "up to date"
        elseif what == "bad" then
            Updater.status = "build " .. rest .. " crashed - skipped"
        elseif what == "downloading" then
            Updater.status = "downloading build " .. rest .. " ..."
        elseif what == "failed" then
            Updater.status = "update failed: " .. rest
        elseif what == "ready" then
            local build, file = rest:match("^(%d+) (%S+)$")
            local st = readState()
            st.build, st.file, st.state = tonumber(build), file, "ok"
            writeState(st)
            Updater.ready = st.build
            Updater.status = "build " .. build .. " ready - used at the next start"
        end
        msg = channel:pop()
    end
    if thread and thread:getError() then
        Updater.status = "update failed: " .. thread:getError():gsub("\n.*", "")
        thread = nil
    end
end

return Updater
