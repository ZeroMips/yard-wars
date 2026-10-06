-- Yard Pass data: seasons with their tier rewards, the challenge pool and the XP
-- numbers. The progress itself is in src/pass.lua (pass.txt on the device).
-- A new season = one entry in Seasons.list (it shows up once its `starts` date has
-- come, so it can be shipped ahead with a self-update). Old seasons stay playable.
--
-- Season entry:
--   id       unique, no spaces (key in pass.txt - never change it once published)
--   name     shown on the pass screen
--   starts   "YYYY-MM-DD" (device date) from which it is shown
--   tierXp   XP per tier
--   tiers    one reward per tier (the list length is the number of tiers):
--              { coins = 30 }                 coins (src/profile.lua)
--              { rowdy = "Gardener" }         unlocks a rowdy (src/rowdies.lua) for free;
--                                             already bought: DUPLICATE_COINS instead
--              { cosmetic = "skin.gunner.rose" } skin, trail, pedestal, badge or title
--                                             (src/cosmetics.lua)
-- After the last tier every BONUS_XP more gives a bonus reward of BONUS_COINS.
--
-- Challenges (CHARTER.md: they motivate, but never expire or punish a break): OPEN
-- open ones from `challenges` + one big one from `big`. Each stays until it is done; a
-- done one is replaced by a new one when the next round starts. Entry: { id (unique,
-- kept in pass.txt - never change it once published), kind, n,
-- rowdy = name (only counts with that rowdy; only offered once it is unlocked),
-- mode = "duel" | "team" | "waves" (only counts there; LAN games count too) }.
-- Kinds: kills (= knockouts, bots count), wins, rounds, coins (picked up), chests
-- (broken), supers (fired), medpacks (picked up), waves (cleared).
local Seasons = {}

-- XP per thing that happened to the own rowdy (main.lua -> src/pass.lua)
Seasons.XP = {
    win = 100, draw = 60, loss = 40, -- round finished (duel, team fight)
    wavesBase = 40, wave = 20,       -- waves: 40 + 20 per cleared wave
    kill = 10, chest = 5,            -- a knockout, a broken chest
    challenge = 150, big = 600,      -- a challenge / the big challenge completed
}
Seasons.OPEN = 3            -- open challenges at a time (plus the big one)
Seasons.SWAPS = 1           -- swaps in stock; finishing a challenge gives one back
Seasons.BONUS_XP = 1500     -- after the last tier: a bonus reward every this much XP
Seasons.BONUS_COINS = 25
Seasons.DUPLICATE_COINS = 100 -- a rowdy reward for a rowdy that was already bought

local function coins(n) return { coins = n } end
local function cos(id) return { cosmetic = id } end

Seasons.list = {
    {
        id = "garden", name = "Garden Party", starts = "2026-10-05", tierXp = 1200,
        tiers = {
            coins(10), coins(15), coins(20), coins(15), cos("skin.gunner.rose"),            --  1- 5
            coins(20), coins(25), cos("trail.leaf"), coins(25),
            { rowdy = "Gardener" }, -- the season's new rowdy                                 --  6-10
            coins(20), coins(30), cos("skin.shotgunner.sunflower"), coins(25), cos("badge.garden"), -- 11-15
            coins(30), coins(30), cos("pedestal.flowerpot"), coins(35), cos("skin.sniper.tulip"), -- 16-20
            coins(30), coins(35), coins(40), coins(35), cos("skin.robot.lavender"),           -- 21-25
            coins(40), coins(40), coins(45), coins(50), cos("title.veteran"),                 -- 26-30
        },
    },
}

Seasons.challenges = {
    { id = "d.kills20", kind = "kills", n = 20 },
    { id = "d.kills.gunner", kind = "kills", n = 10, rowdy = "Gunner" },
    { id = "d.kills.shotgunner", kind = "kills", n = 10, rowdy = "Shotgunner" },
    { id = "d.kills.sniper", kind = "kills", n = 10, rowdy = "Sniper" },
    { id = "d.kills.robot", kind = "kills", n = 10, rowdy = "Robot" },
    { id = "d.kills.gardener", kind = "kills", n = 10, rowdy = "Gardener" },
    { id = "d.kills.waves", kind = "kills", n = 25, mode = "waves" },
    { id = "d.wins3", kind = "wins", n = 3 },
    { id = "d.wins.duel", kind = "wins", n = 2, mode = "duel" },
    { id = "d.wins.team", kind = "wins", n = 2, mode = "team" },
    { id = "d.rounds5", kind = "rounds", n = 5 },
    { id = "d.coins40", kind = "coins", n = 40 },
    { id = "d.chests3", kind = "chests", n = 3 },
    { id = "d.supers5", kind = "supers", n = 5 },
    { id = "d.medpacks3", kind = "medpacks", n = 3 },
    { id = "d.waves8", kind = "waves", n = 8 },
}

Seasons.big = {
    { id = "w.kills150", kind = "kills", n = 150 },
    { id = "w.wins15", kind = "wins", n = 15 },
    { id = "w.chests20", kind = "chests", n = 20 },
    { id = "w.supers30", kind = "supers", n = 30 },
    { id = "w.waves40", kind = "waves", n = 40 },
    { id = "w.rounds30", kind = "rounds", n = 30 },
}

local MODE_NAMES = { duel = "Duel", team = "Team fight", waves = "Waves" }

-- "Knock out 10 opponents as the Sniper" etc.
function Seasons.describe(c)
    local n = c.n
    local text
    if c.kind == "kills" then text = "Knock out " .. n .. " opponents"
    elseif c.kind == "wins" then text = "Win " .. n .. " rounds"
    elseif c.kind == "rounds" then text = "Play " .. n .. " rounds"
    elseif c.kind == "coins" then text = "Collect " .. n .. " coins"
    elseif c.kind == "chests" then text = "Break " .. n .. " chests"
    elseif c.kind == "supers" then text = "Fire your super " .. n .. " times"
    elseif c.kind == "medpacks" then text = "Pick up " .. n .. " medpacks"
    else text = "Clear " .. n .. " waves" end
    if c.rowdy then text = text .. " as the " .. c.rowdy end
    if c.mode and c.kind ~= "waves" then text = text .. " in " .. MODE_NAMES[c.mode] end
    return text
end

-- ---- Checks when the file loads (a typo would otherwise show up as a broken pass)

local byId, challengeById = {}, {}

do
    local Rowdies = require("src.rowdies")
    local Cosmetics = require("src.cosmetics")
    local names = {}
    for _, def in ipairs(Rowdies) do names[def.name] = true end
    local function fail(where, msg) error("src/seasons.lua: " .. where .. ": " .. msg, 0) end

    local last
    for i, s in ipairs(Seasons.list) do
        local where = "season " .. i .. " (" .. tostring(s.id) .. ")"
        if type(s.id) ~= "string" or not s.id:match("^%S+$") then fail(where, "needs an id without spaces") end
        if byId[s.id] then fail(where, "id used twice") end
        if type(s.name) ~= "string" then fail(where, "needs a name") end
        if type(s.starts) ~= "string" or not s.starts:match("^%d%d%d%d%-%d%d%-%d%d$") then
            fail(where, "starts must be \"YYYY-MM-DD\"")
        end
        if last and s.starts < last then fail(where, "seasons must be in order of their start") end
        last = s.starts
        if type(s.tierXp) ~= "number" or s.tierXp <= 0 then fail(where, "needs tierXp > 0") end
        if type(s.tiers) ~= "table" or #s.tiers == 0 then fail(where, "needs tiers") end
        for t, r in pairs(s.tiers) do
            local tw = where .. ", tier " .. tostring(t)
            if type(t) ~= "number" or t < 1 or t > #s.tiers or t % 1 ~= 0 then fail(tw, "gap in the tier list") end
            local n = 0
            for k, v in pairs(r) do
                n = n + 1
                if k == "coins" then
                    if type(v) ~= "number" or v <= 0 or v % 1 ~= 0 then fail(tw, "coins must be a whole number > 0") end
                elseif k == "rowdy" then
                    if not names[v] then fail(tw, "rowdy '" .. tostring(v) .. "' doesn't exist") end
                elseif k == "cosmetic" then
                    if not Cosmetics.get(v) then fail(tw, "cosmetic '" .. tostring(v) .. "' doesn't exist (src/cosmetics.lua)") end
                else
                    fail(tw, "unknown reward '" .. tostring(k) .. "'")
                end
            end
            if n ~= 1 then fail(tw, "a reward is exactly one of coins / rowdy / cosmetic") end
        end
        byId[s.id] = s
    end

    local KINDS = { kills = true, wins = true, rounds = true, coins = true, chests = true,
                    supers = true, medpacks = true, waves = true }
    local MODES = { duel = true, team = true, waves = true }
    for _, pool in ipairs({ "challenges", "big" }) do
        for i, c in ipairs(Seasons[pool]) do
            local where = pool .. " challenge " .. i .. " (" .. tostring(c.id) .. ")"
            for k in pairs(c) do
                if k ~= "id" and k ~= "kind" and k ~= "n" and k ~= "rowdy" and k ~= "mode" then
                    fail(where, "unknown field '" .. tostring(k) .. "'")
                end
            end
            if type(c.id) ~= "string" or not c.id:match("^%S+$") then fail(where, "needs an id without spaces") end
            if challengeById[c.id] then fail(where, "id used twice") end
            if not KINDS[c.kind] then fail(where, "unknown kind '" .. tostring(c.kind) .. "'") end
            if type(c.n) ~= "number" or c.n < 1 or c.n % 1 ~= 0 then fail(where, "n must be a whole number > 0") end
            if c.rowdy and not names[c.rowdy] then fail(where, "rowdy '" .. tostring(c.rowdy) .. "' doesn't exist") end
            if c.mode and not MODES[c.mode] then fail(where, "unknown mode '" .. tostring(c.mode) .. "'") end
            c.pool = pool
            challengeById[c.id] = c
        end
    end
    if #Seasons.challenges <= Seasons.OPEN then fail("challenges", "the pool needs more entries than OPEN") end
    if #Seasons.big < 2 then fail("big", "the pool needs at least 2 entries") end
end

function Seasons.get(id) return id and byId[id] end
function Seasons.challenge(id) return id and challengeById[id] end

return Seasons
