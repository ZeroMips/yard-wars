-- Self-update over plain http (LÖVE has no https) with an RSA signature check.
--
-- Published builds (tools/publish.sh) live in URL: yard-wars-<build>.love plus latest.txt,
-- a signed manifest (build, version, file, size, sha256, sig = RSA signature over all
-- bytes before the "sig" line). On every start a thread (src/updater_thread.lua) fetches
-- latest.txt, checks the signature and, for a newer build, downloads the .love into the
-- save folder as update-<build>.love and checks size + sha256.
--
-- update.txt in the save folder says which downloaded build to use:
--   build 40 / file update-40.love / state ok|trying|retry / crashed 40 /
--   bad <builds that crashed>
-- On the next start (or right away via love.event.quit("restart") when it arrives in the
-- lobby, not on Android) Updater.boot(), the first line of main.lua, mounts that file over
-- the game source and runs its main.lua instead. state "trying" is written before that and
-- set back to "ok" once the build has run for a moment. A start that finds "trying" gets
-- one more go ("retry": the app may only have been closed early) unless the build logged
-- an error then ("crashed"); a start that finds "retry" marks the build bad and runs the
-- built-in game. (Builds up to 71 mark it bad at the first "trying" already.)
--
-- Every Lua error (error screen) is written to crash.txt with its traceback; the lobby
-- shows "last crash (build N): ..." while that build or an older one runs.
--
-- update-log.txt (last LOG_LINES lines) tells what happened when: every start (which
-- build, update.txt then), check results, confirmations, boot decisions, crashes, the
-- steps of loading (Updater.step) and the first frame, so a native crash or a freeze
-- while starting shows the last step reached. While the game runs, alive.txt is
-- rewritten every HEARTBEAT seconds (time + Updater.where) and removed on a clean quit
-- (Updater.quit); found at the next start, it is logged as "previous session ended
-- without quitting" (closed from the app list, killed by the system or a native crash -
-- a Lua error is in crash.txt).
-- Updater.report() puts all three files together for the info screen (src/infoview.lua,
-- long press on the build line in the lobby); on Android the report is also copied to
-- the app's folder next to games/ (Updater.mirrorPath), which is reachable over USB -
-- the save folder is not.
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
local CRASH_FILE = "crash.txt"
local LOG_FILE = "update-log.txt"
local LOG_LINES = 160 -- (about 5 lines per start)
local INFO_FILE = "yard-wars-info.txt" -- the copy of the report (Android: next to games/)
local CONFIRM_AFTER = 3 -- seconds a mounted build has to run before it counts as working
local ALIVE_FILE = "alive.txt"
local HEARTBEAT = 30   -- seconds between two alive.txt writes

Updater.status = nil -- short text for the lobby ("up to date", ...)
Updater.ready = nil  -- build number downloaded and ready to use (restart to switch)
Updater.mirrorPath = nil  -- where the report copy was written (nil: none)
Updater.mirrorError = nil -- why it couldn't be written
Updater.where = nil       -- what the game is doing (main.lua), written to alive.txt

local channel, thread
local runTime = 0
local nextBeat = 0
local confirmed = false
local check = nil     -- the update check's status ("up to date", ...)
local lastCrash = nil -- "last crash (build N): ..." from crash.txt, see readCrash()

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
        elseif key == "crashed" then st.crashed = tonumber(value)
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
        if st.crashed == st.build then lines[#lines + 1] = "crashed " .. st.build end
    end
    if #bad > 0 then lines[#lines + 1] = "bad " .. table.concat(bad, " ") end
    love.filesystem.write(STATE_FILE, table.concat(lines, "\n") .. "\n")
end

-- One line in update-log.txt (date, running build, text); keeps the last LOG_LINES
local function log(text)
    pcall(function()
        local s = love.filesystem.getInfo(LOG_FILE) and love.filesystem.read(LOG_FILE) or ""
        local lines = {}
        for line in s:gmatch("[^\n]+") do lines[#lines + 1] = line end
        lines[#lines + 1] = os.date("%Y-%m-%d %H:%M:%S") .. "  [" .. tostring(Updater.build())
            .. "]  " .. text
        while #lines > LOG_LINES do table.remove(lines, 1) end
        love.filesystem.write(LOG_FILE, table.concat(lines, "\n") .. "\n")
    end)
end
Updater.log = log

local function beat()
    pcall(love.filesystem.write, ALIVE_FILE, os.date("%Y-%m-%d %H:%M:%S") .. " "
        .. (Updater.where or "starting") .. "\n")
end

-- First thing in love.load: reports a previous session that never quit cleanly, then
-- starts the heartbeat
function Updater.begin()
    local s = love.filesystem.getInfo(ALIVE_FILE) and love.filesystem.read(ALIVE_FILE)
    if s then
        log("previous session ended without quitting (last seen " .. (s:gsub("%s+$", ""))
            .. ") - closed from the app list, killed by the system or a native crash")
    end
    beat()
    log("load: begin")
end

-- A step of loading reached ("assets", "sound", ...)
function Updater.step(text) log("load: " .. text) end

-- From love.quit: the session ended normally
function Updater.quit() pcall(love.filesystem.remove, ALIVE_FILE) end

local function readFile(name)
    return love.filesystem.getInfo(name) and love.filesystem.read(name) or nil
end

-- update.txt in one line ("build 81 / file update-81.love / state ok / bad 79")
local function stateLine()
    local s = readFile(STATE_FILE)
    if not s or s:match("^%s*$") then return "(empty)" end
    return (s:gsub("%s*$", ""):gsub("\n", " / "))
end

-- Everything about updates and crashes on this device, as text
function Updater.report()
    local os_ = love.system and love.system.getOS() or "?"
    local version = readFile("version.txt")
    local lines = {
        "Yard Wars build " .. tostring(Updater.build() or "- (no build.txt: no updates)")
            .. (version and "  (" .. version:gsub("%s*$", "") .. ")" or ""),
        "running: " .. (YARD_WARS_UPDATE and "downloaded update" or "installed build")
            .. "   system: " .. os_ .. "   now: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "",
        "--- update.txt",
        stateLine(),
        "",
        "--- crash.txt",
        ((readFile(CRASH_FILE) or "(no crash logged)"):gsub("%s*$", "")),
        "",
        "--- update-log.txt (newest last)",
        ((readFile(LOG_FILE) or "(empty)"):gsub("%s*$", "")),
    }
    return table.concat(lines, "\n") .. "\n"
end

-- The folder for the report copy: Android = the app's own folder in shared storage
-- (.../Android/data/<app>/files, where games/ lives; the app may write there and USB
-- shows it), desktop only with --info-dir DIR (for tests: the save folder is reachable)
local mirrorDir
local function findMirrorDir(args)
    local _, dir = hasArg("--info-dir", args)
    if dir then return dir end
    if not (love.system and love.system.getOS() == "Android") then return nil end
    local source = love.filesystem.getSource() or ""
    return source:match("^(.-/Android/data/[^/]+/files)/")
        or "/storage/emulated/0/Android/data/org.love2d.android/files"
end

-- Write the report copy (if there is a place for it)
function Updater.mirror()
    if not mirrorDir then return end
    local ok, err = pcall(function()
        local path = mirrorDir .. "/" .. INFO_FILE
        -- a new file each time: USB (MTP) notices new files, but keeps the size of the
        -- first write for a rewritten one (it read the Pixel's copy cut off at that size)
        os.remove(path)
        local f, why = io.open(path, "w")
        if not f then error(why or "can't open", 0) end
        f:write(Updater.report())
        f:close()
        Updater.mirrorPath, Updater.mirrorError = path, nil
    end)
    if not ok then Updater.mirrorPath, Updater.mirrorError = nil, tostring(err) end
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

-- Lua errors go to crash.txt (build, date, message, traceback) before LÖVE's error screen.
-- An error in the first seconds of a mounted build also goes into update.txt ("crashed"):
-- boot() then skips the second try.
local function logCrashes()
    -- LÖVE's own error screen (11.5 still calls the default love.errhand); the mounted
    -- build's boot() replaces the hand-installed build's handler (that one's `confirmed`
    -- never changes)
    YARD_WARS_ERROR_SCREEN = YARD_WARS_ERROR_SCREEN or love.errorhandler or love.errhand
    local show = YARD_WARS_ERROR_SCREEN
    love.errorhandler = function(msg)
        local trace = debug.traceback("Error: " .. tostring(msg), 2) -- (from where it failed)
        pcall(function()
            local build = Updater.build()
            love.filesystem.write(CRASH_FILE, "build " .. tostring(build) .. "  "
                .. os.date("%Y-%m-%d %H:%M:%S") .. "\n" .. trace .. "\n")
            if YARD_WARS_UPDATE and not confirmed then
                local st = readState()
                if st.build == YARD_WARS_UPDATE then
                    st.crashed = st.build
                    writeState(st)
                end
            end
            log("crash: " .. (tostring(msg):gsub("\n.*", "")))
            Updater.mirror()
        end)
        return show(msg)
    end
end

-- First line of main.lua: runs a downloaded newer build instead of this one if there is
-- one. Returns true if it did (main.lua must return right away then).
function Updater.boot()
    logCrashes()
    if YARD_WARS_UPDATE then return false end -- we are the mounted build: already booted
    local own = Updater.build()
    if not own or hasArg("--no-update") then return false end
    local st = readState()
    local usable = st.build and st.file and st.build > own and not st.bad[st.build]
        and love.filesystem.getInfo(st.file)
    -- The last start of this build never got going: closed early (one more try) or an error
    local retry = false
    if usable and (st.state == "retry" or st.state == "trying" and st.crashed == st.build) then
        st.bad[st.build] = true
        usable = false
        log("boot: build " .. st.build .. " marked bad ("
            .. (st.state == "retry" and "second start ended early too" or "it crashed") .. ")")
    elseif usable and st.state == "trying" then
        retry = true
        log("boot: build " .. st.build .. " ended early last time - one more try")
    elseif st.build and st.file and not usable then
        log("boot: build " .. st.build .. " not used ("
            .. (st.bad[st.build] and "bad" or st.build <= own and "not newer" or "file missing") .. ")")
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
    st.state = retry and "retry" or "trying"
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

local setStatus, readCrash, startCheck
local checkUrl -- where the update check looks (nil: no check on this copy)

-- Start the check in the background (from love.load)
function Updater.start(args)
    mirrorDir = findMirrorDir(args)
    local own = Updater.build()
    if own then
        log("start: " .. (YARD_WARS_UPDATE and "downloaded update" or "installed build")
            .. "; update.txt: " .. stateLine())
    end
    Updater.mirror()
    if not own or hasArg("--no-update", args) then return end
    local _, url = hasArg("--update-url", args)
    checkUrl = url or Updater.URL
    lastCrash = readCrash()
    startCheck()
end

-- The update check in its thread (again after Updater.retryBad)
function startCheck()
    local bad = {}
    for b in pairs(readState().bad) do bad[#bad + 1] = b end
    channel = love.thread.getChannel("updater")
    channel:clear()
    thread = love.thread.newThread("src/updater_thread.lua")
    thread:start(checkUrl, Updater.build(), table.concat(bad, " "), Updater.PUBLIC_KEY)
    check = "checking for updates"
    setStatus()
end

-- The newest build marked bad on this device, or nil
function Updater.badBuild()
    local newest
    for b in pairs(readState().bad) do
        if not newest or b > newest then newest = b end
    end
    return newest
end

-- The player asked to try the bad builds again (info screen): forget them and check
-- again - the newest build is downloaded once more (its file was deleted when it was
-- marked bad) and used at the next start. Returns false without an update check here
-- (git checkout, --no-update) or while one is still running.
function Updater.retryBad()
    local st = readState()
    local list = {}
    for b in pairs(st.bad) do list[#list + 1] = b end
    if #list == 0 or not checkUrl or (thread and thread:isRunning()) then return false end
    table.sort(list)
    st.bad = {}
    writeState(st)
    log("retry asked: build " .. table.concat(list, ", ") .. " may be used again")
    startCheck()
    Updater.mirror()
    return true
end

-- The lobby's status line: the update check and the running build's last crash
function setStatus()
    if check and lastCrash then Updater.status = check .. "  -  " .. lastCrash
    else Updater.status = check or lastCrash end
end

-- "last crash (build N): <first line>" if crash.txt is from the running build or a newer
-- one (skipped after it crashed)
function readCrash()
    local s = love.filesystem.getInfo(CRASH_FILE) and love.filesystem.read(CRASH_FILE)
    local build, msg = (s or ""):match("^build (%d+)[^\n]*\nError: ([^\n]*)")
    if build and tonumber(build) >= Updater.build() then
        if #msg > 70 then msg = msg:sub(1, 67) .. "..." end
        return "last crash (build " .. build .. "): " .. msg
    end
end

-- Every frame: confirms a mounted build after a few seconds, reads the check's progress
function Updater.update(dt)
    runTime = runTime + dt
    if runTime >= nextBeat then
        nextBeat = runTime + HEARTBEAT
        beat()
    end
    if YARD_WARS_UPDATE and not confirmed and runTime > CONFIRM_AFTER then
        confirmed = true
        local st = readState()
        if st.build == YARD_WARS_UPDATE and (st.state == "trying" or st.state == "retry") then
            st.state, st.crashed = "ok", nil
            writeState(st)
            log("build " .. st.build .. " ran " .. CONFIRM_AFTER .. " s: confirmed")
            Updater.mirror()
        end
    end
    if not channel then return end
    local before = check
    local msg = channel:pop()
    while msg do
        local what, rest = msg:match("^(%S+) ?(.*)$")
        if what == "uptodate" then
            check = "up to date"
        elseif what == "bad" then
            check = "build " .. rest .. " crashed - skipped"
        elseif what == "downloading" then
            check = "downloading build " .. rest .. " ..."
        elseif what == "failed" then
            check = "update failed: " .. rest
        elseif what == "ready" then
            local build, file = rest:match("^(%d+) (%S+)$")
            local st = readState()
            st.build, st.file, st.state, st.crashed = tonumber(build), file, "ok", nil
            writeState(st)
            Updater.ready = st.build
            check = "build " .. build .. " ready - used at the next start"
        end
        msg = channel:pop()
    end
    if thread and thread:getError() then
        check = "update failed: " .. thread:getError():gsub("\n.*", "")
        thread = nil
    end
    if check ~= before then
        setStatus()
        if check ~= "checking for updates" then
            log("check: " .. check)
            Updater.mirror()
        end
    end
end

return Updater
