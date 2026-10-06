-- Yard Pass progress on this device: XP per season, claimed tier rewards, the open
-- challenges and the big one, owned and equipped cosmetics. The data (seasons, rewards,
-- challenge pool, XP numbers) is in src/seasons.lua, the screen in src/passview.lua.
--
-- Like the coins, XP is earned per device for the own rowdy: main.lua passes the world
-- events (Pass.onEvent) and the end of a round (Pass.onRoundOver) - on a LAN client
-- too. All XP goes to the selected season (default: the newest one).
--
-- Saved in its own file pass.txt, not profile.txt: an older build (after a bad update)
-- rewrites profile.txt with only coins and rowdies, but never touches pass.txt.
-- Lines (unknown ones are skipped):
--   season <id>                      selected season
--   xp <season> <n>
--   claimed <season> <tier> <tier> ...
--   bonus <season> <n>               bonus rewards (after the last tier) claimed
--   challenge <id> <progress> <0|1>  an open challenge (0|1: done)
--   big <id> <progress> <0|1>        the big challenge
--   swaps <n>                        swaps left
--   drawn <n>                        challenges drawn so far (seed of the next choice)
-- Before build 66 the challenges were daily/weekly ("day", "daily", "week", "weekly",
-- "firstwin" lines): daily/weekly ones are taken over as open/big ones, the rest is
-- dropped (CHARTER.md: nothing expires).
--   own <id> <id> ...                cosmetics (src/cosmetics.lua)
--   skin <rowdy name> <id>           equipped skin per rowdy
--   equip <kind> <id>                equipped trail / pedestal / badge / title
local Seasons   = require("src.seasons")
local Cosmetics = require("src.cosmetics")
local Rowdies   = require("src.rowdies")
local Profile   = require("src.profile")

local Pass = {}

local FILE = "pass.txt"
local XP = Seasons.XP

Pass.clock = os.time -- current time (tests replace it)

local function fresh()
    Pass.selected = nil  -- season id (nil = the newest)
    Pass.xp = {}         -- season id -> XP
    Pass.claimed = {}    -- season id -> { [tier] = true }
    Pass.bonus = {}      -- season id -> bonus rewards claimed
    Pass.open = {}       -- open challenges { id, progress, done }
    Pass.big = {}        -- the big challenge (0 or 1 entry, same form)
    Pass.swaps = Seasons.SWAPS
    Pass.drawn = 0
    Pass.owned = {}      -- cosmetic id -> true
    Pass.skins = {}      -- rowdy name -> skin id
    Pass.equipped = {}   -- kind -> cosmetic id
end
fresh()

local round -- this round's XP for the result screen (Pass.roundStart)

-- Today (device date): only for a season's start date
function Pass.today() return os.date("%Y-%m-%d", Pass.clock()) end

---------------------------------------------------------------------------- file

function Pass.load()
    fresh()
    if not love.filesystem.getInfo(FILE) then return end
    for line in (love.filesystem.read(FILE) or ""):gmatch("[^\n]+") do
        local w = {}
        for word in line:gmatch("%S+") do w[#w + 1] = word end
        local key = w[1]
        if key == "season" then Pass.selected = w[2]
        elseif key == "xp" and w[2] then Pass.xp[w[2]] = math.max(0, math.floor(tonumber(w[3]) or 0))
        elseif key == "claimed" and w[2] then
            local set = {}
            for i = 3, #w do
                local t = tonumber(w[i])
                if t then set[t] = true end
            end
            Pass.claimed[w[2]] = set
        elseif key == "bonus" and w[2] then Pass.bonus[w[2]] = math.max(0, math.floor(tonumber(w[3]) or 0))
        elseif key == "challenge" or key == "big" or key == "daily" or key == "weekly" then
            local def = Seasons.challenge(w[2])
            local list = (key == "challenge" or key == "daily") and Pass.open or Pass.big
            local want = (list == Pass.open) and "challenges" or "big"
            if def and def.pool == want and #list < ((list == Pass.open) and Seasons.OPEN or 1) then
                list[#list + 1] = { id = w[2], progress = math.max(0, tonumber(w[3]) or 0),
                    done = w[4] == "1" }
            end
        elseif key == "swaps" then Pass.swaps = math.max(0, math.min(Seasons.SWAPS, tonumber(w[2]) or 0))
        elseif key == "drawn" then Pass.drawn = math.max(0, math.floor(tonumber(w[2]) or 0))
        elseif key == "own" then
            for i = 2, #w do
                if Cosmetics.get(w[i]) then Pass.owned[w[i]] = true end
            end
        elseif key == "skin" and w[2] and w[3] then Pass.skins[w[2]] = w[3]
        elseif key == "equip" and w[2] and w[3] then Pass.equipped[w[2]] = w[3]
        end
    end
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

function Pass.save()
    local out = {}
    local function add(s) out[#out + 1] = s end
    if Pass.selected then add("season " .. Pass.selected) end
    for _, id in ipairs(sortedKeys(Pass.xp)) do add("xp " .. id .. " " .. Pass.xp[id]) end
    for _, id in ipairs(sortedKeys(Pass.claimed)) do
        local tiers = {}
        for t in pairs(Pass.claimed[id]) do tiers[#tiers + 1] = t end
        table.sort(tiers)
        add("claimed " .. id .. " " .. table.concat(tiers, " "))
    end
    for _, id in ipairs(sortedKeys(Pass.bonus)) do add("bonus " .. id .. " " .. Pass.bonus[id]) end
    for _, c in ipairs(Pass.open) do
        add("challenge " .. c.id .. " " .. c.progress .. " " .. (c.done and 1 or 0))
    end
    for _, c in ipairs(Pass.big) do
        add("big " .. c.id .. " " .. c.progress .. " " .. (c.done and 1 or 0))
    end
    add("swaps " .. Pass.swaps)
    add("drawn " .. Pass.drawn)
    local owned = sortedKeys(Pass.owned)
    if #owned > 0 then add("own " .. table.concat(owned, " ")) end
    for _, name in ipairs(sortedKeys(Pass.skins)) do add("skin " .. name .. " " .. Pass.skins[name]) end
    for _, kind in ipairs(sortedKeys(Pass.equipped)) do add("equip " .. kind .. " " .. Pass.equipped[kind]) end
    love.filesystem.write(FILE, table.concat(out, "\n") .. "\n")
end

---------------------------------------------------------------------------- seasons

-- Seasons that have started (by the device date), oldest first
function Pass.seasons()
    local list, today = {}, Pass.today()
    for _, s in ipairs(Seasons.list) do
        if s.starts <= today then list[#list + 1] = s end
    end
    return list
end

-- The selected season (or the newest), nil if none has started yet
function Pass.season()
    local list = Pass.seasons()
    for _, s in ipairs(list) do
        if s.id == Pass.selected then return s end
    end
    return list[#list]
end

function Pass.select(id)
    Pass.selected = id
    Pass.save()
end

function Pass.xpOf(season) return Pass.xp[season.id] or 0 end

-- Progress in a season: tier reached (0..#tiers), XP into the next tier and XP that
-- tier needs (after the last tier: towards the next bonus reward), bonus rewards earned
function Pass.level(season, xp)
    xp = xp or Pass.xpOf(season)
    local n = #season.tiers
    local tier = math.min(n, math.floor(xp / season.tierXp))
    if tier < n then return tier, xp - tier * season.tierXp, season.tierXp, 0 end
    local extra = xp - n * season.tierXp
    return n, extra % Seasons.BONUS_XP, Seasons.BONUS_XP, math.floor(extra / Seasons.BONUS_XP)
end

-- "claimed", "ready" (reached, not claimed yet) or "locked"
function Pass.tierState(season, t)
    if (Pass.claimed[season.id] or {})[t] then return "claimed" end
    return (Pass.level(season) >= t) and "ready" or "locked"
end

-- Bonus rewards earned but not claimed yet
function Pass.bonusReady(season)
    local _, _, _, earned = Pass.level(season)
    return math.max(0, earned - (Pass.bonus[season.id] or 0))
end

-- Number of rewards to claim, in one season or in all started ones (lobby dot)
function Pass.claimable(season)
    local list = season and { season } or Pass.seasons()
    local n = 0
    for _, s in ipairs(list) do
        for t = 1, Pass.level(s) do
            if Pass.tierState(s, t) == "ready" then n = n + 1 end
        end
        n = n + Pass.bonusReady(s)
    end
    return n
end

-- Text for a reward ("30 coins", "Robot", "Rose skin (Gunner)", ...)
function Pass.rewardText(r)
    if r.coins then return r.coins .. " coins" end
    if r.rowdy then return r.rowdy end
    local c = Cosmetics.get(r.cosmetic)
    if c.kind == "skin" then return c.name .. " skin (" .. c.rowdy .. ")" end
    if c.kind == "title" then return "Title \"" .. c.name .. "\"" end
    if c.kind == "badge" then return c.name .. " badge" end
    return c.name
end

local function rowdyDef(name)
    for _, def in ipairs(Rowdies) do
        if def.name == name then return def end
    end
end

-- Hand out a reward. Returns the message for the pass screen.
local function give(r)
    if r.coins then
        Profile.addCoins(r.coins)
        return "+" .. r.coins .. " coins"
    elseif r.rowdy then
        local def = rowdyDef(r.rowdy)
        if Profile.owns(def) then -- (not test mode: that unlocks nothing for real)
            Profile.addCoins(Seasons.DUPLICATE_COINS)
            return "+" .. Seasons.DUPLICATE_COINS .. " coins (you already have the " .. r.rowdy .. ")"
        end
        Profile.grant(r.rowdy)
        return r.rowdy .. " unlocked!"
    end
    local c = Cosmetics.get(r.cosmetic)
    Pass.owned[c.id] = true
    -- new things are put on right away
    if c.kind == "skin" then Pass.skins[c.rowdy] = c.id else Pass.equipped[c.kind] = c.id end
    return Pass.rewardText(r) .. " unlocked!"
end

-- Claim a reached tier. Returns the message, or nil if there was nothing to claim.
function Pass.claim(season, t)
    if Pass.tierState(season, t) ~= "ready" then return nil end
    Pass.claimed[season.id] = Pass.claimed[season.id] or {}
    Pass.claimed[season.id][t] = true
    local msg = give(season.tiers[t])
    Pass.save()
    return msg
end

function Pass.claimBonus(season)
    if Pass.bonusReady(season) < 1 then return nil end
    Pass.bonus[season.id] = (Pass.bonus[season.id] or 0) + 1
    local msg = give({ coins = Seasons.BONUS_COINS })
    Pass.save()
    return msg
end

---------------------------------------------------------------------------- challenges

-- Small deterministic random generator (Park-Miller), seeded from a text (here: the
-- number of challenges drawn so far, so the choice is the same on every start)
local function generator(text)
    local x = 5381
    for i = 1, #text do x = (x * 33 + text:byte(i)) % 2147483647 end
    if x == 0 then x = 1 end
    return function(n)
        x = (x * 48271) % 2147483647
        return x % n + 1
    end
end

-- A rowdy challenge is only offered once that rowdy is unlocked on this device
local function available(c)
    if not c.rowdy then return true end
    local def = rowdyDef(c.rowdy)
    return def and Profile.owns(def)
end

-- A new challenge from `pool`, not one of those in `exclude` (lists), or nil
local function draw(pool, exclude)
    local taken = {}
    for _, list in ipairs(exclude) do
        for _, c in ipairs(list) do taken[c.id] = true end
    end
    local candidates = {}
    for _, c in ipairs(pool) do
        if not taken[c.id] and available(c) then candidates[#candidates + 1] = c end
    end
    if #candidates == 0 then return nil end
    Pass.drawn = Pass.drawn + 1
    local c = candidates[generator("challenge " .. Pass.drawn)(#candidates)]
    return { id = c.id, progress = 0, done = false }
end

-- Fill the empty challenge places. replaceDone: done challenges make room for new
-- ones first (at the start of a round and when the pass screen opens - during a round
-- a done one stays, so the result screen can show it). Nothing here depends on time.
function Pass.refresh(replaceDone)
    local changed = false
    for _, slot in ipairs({ { Pass.open, Seasons.challenges }, { Pass.big, Seasons.big } }) do
        local list, pool = slot[1], slot[2]
        for i = 1, #list do -- a new challenge takes the done one's place
            if replaceDone and list[i].done then
                local c = draw(pool, { list })
                if c then list[i] = c; changed = true end
            end
        end
    end
    while #Pass.open < Seasons.OPEN do
        local c = draw(Seasons.challenges, { Pass.open })
        if not c then break end
        Pass.open[#Pass.open + 1] = c
        changed = true
    end
    if #Pass.big < 1 then
        local c = draw(Seasons.big, { Pass.big })
        if c then Pass.big[1] = c; changed = true end
    end
    if changed then Pass.save() end
end

-- The open challenges, then the big one: { def, progress, done, big, index }
function Pass.challenges()
    Pass.refresh(false)
    local list = {}
    for i, c in ipairs(Pass.open) do
        list[#list + 1] = { def = Seasons.challenge(c.id), progress = c.progress, done = c.done, index = i }
    end
    for _, c in ipairs(Pass.big) do
        list[#list + 1] = { def = Seasons.challenge(c.id), progress = c.progress, done = c.done, big = true }
    end
    return list
end

function Pass.canSwap(i)
    local c = Pass.open[i]
    return c ~= nil and not c.done and Pass.swaps > 0
end

-- Swap open challenge i for another one (uses a swap; finishing a challenge gives one
-- back, up to Seasons.SWAPS)
function Pass.swap(i)
    if not Pass.canSwap(i) then return false end
    local c = draw(Seasons.challenges, { Pass.open }) -- (not this one again either)
    if not c then return false end
    Pass.open[i] = c
    Pass.swaps = Pass.swaps - 1
    Pass.save()
    return true
end

---------------------------------------------------------------------------- XP

-- XP into the selected season; `key`/`label` sort it into the round's breakdown
local function addXp(n, key, label)
    local season = Pass.season()
    if not season or n <= 0 then return end
    Pass.xp[season.id] = Pass.xpOf(season) + n
    if round then
        local part
        for _, p in ipairs(round.parts) do
            if p.key == key then part = p end
        end
        if not part then
            part = { key = key, label = label, xp = 0, count = 0 }
            round.parts[#round.parts + 1] = part
        end
        part.xp, part.count = part.xp + n, part.count + 1
    end
end

-- Count towards the challenges. ctx = { rowdy = name, mode = "duel"|"team"|"waves" }
local function progress(kind, amount, ctx)
    if amount <= 0 then return end
    Pass.refresh(false)
    for _, big in ipairs({ false, true }) do
        for _, c in ipairs(big and Pass.big or Pass.open) do
            local def = Seasons.challenge(c.id)
            if not c.done and def.kind == kind and (not def.rowdy or def.rowdy == ctx.rowdy)
                and (not def.mode or def.mode == ctx.mode) then
                c.progress = math.min(def.n, c.progress + amount)
                if c.progress >= def.n then
                    c.done = true
                    Pass.swaps = math.min(Seasons.SWAPS, Pass.swaps + 1)
                    local xp = big and XP.big or XP.challenge
                    addXp(xp, "challenge " .. c.id, "Challenge: " .. Seasons.describe(def))
                    if round then round.completed[#round.completed + 1] = { text = Seasons.describe(def), xp = xp } end
                end
            end
        end
    end
end

function Pass.modeId(mode)
    return (mode.waves and "waves") or (mode.teams and "team") or "duel"
end

local function context(localId, world)
    local me = world and world:get(localId)
    return { rowdy = me and me.def and me.def.name, mode = world and Pass.modeId(world.mode) }
end

-- A new round starts (or a game was joined): the result screen shows what comes from now
function Pass.roundStart()
    Pass.refresh(true) -- challenges done last round make room for new ones
    local season = Pass.season()
    round = season and { season = season, before = Pass.xpOf(season), parts = {}, completed = {} }
end

-- A world event (main.lua's playEvents; on LAN clients the host's events)
function Pass.onEvent(ev, localId, world)
    if not localId then return end
    local kind = ev.kind
    if kind == "death" then
        if ev.killer ~= localId or ev.id == localId then return end
        addXp(XP.kill, "kills", "Knockouts")
        progress("kills", 1, context(localId, world))
    elseif kind == "boxBreak" then
        if ev.by ~= localId then return end
        addXp(XP.chest, "chests", "Chests")
        progress("chests", 1, context(localId, world))
    elseif kind == "coin" then
        if ev.id ~= localId then return end
        progress("coins", tonumber(ev.value) or 0, context(localId, world))
    elseif kind == "super" then
        if ev.id ~= localId then return end
        progress("supers", 1, context(localId, world))
    elseif kind == "heal" then
        if ev.id ~= localId then return end
        progress("medpacks", 1, context(localId, world))
    else
        return
    end
    Pass.save()
end

-- The round is over. outcome: "win" | "draw" | "loss" | "waves" (wave = wave reached).
-- Returns what the result screen shows, or nil without a season:
--   { season, before, after (XP), parts = { {label, xp, count} }, total,
--     completed = { {text, xp} }, tiersUp (tiers reached in this round) }
function Pass.onRoundOver(outcome, wave, localId, world)
    local season = Pass.season()
    if not season then return nil end
    if not round or round.season ~= season then Pass.roundStart() end
    local ctx = context(localId, world)
    if outcome == "waves" then
        local cleared = math.max(0, (wave or 1) - 1)
        addXp(XP.wavesBase + XP.wave * cleared, "round", "Waves (" .. cleared .. " cleared)")
        progress("waves", cleared, ctx)
    else
        local names = { win = "Victory", draw = "Draw", loss = "Round played" }
        addXp(XP[outcome] or 0, "round", names[outcome] or "Round")
    end
    progress("rounds", 1, ctx)
    if outcome == "win" then progress("wins", 1, ctx) end
    Pass.save()

    local r = round
    round = nil -- XP after the round (none: the world stands still) isn't shown
    local after = Pass.xpOf(season)
    local total = after - r.before
    local tiersUp = Pass.level(season, after) - Pass.level(season, r.before)
    -- a new bonus reward counts as a tier up too
    local _, _, _, b0 = Pass.level(season, r.before)
    local _, _, _, b1 = Pass.level(season, after)
    return { season = season, before = r.before, after = after, parts = r.parts, total = total,
             completed = r.completed, tiersUp = tiersUp + (b1 - b0) }
end

---------------------------------------------------------------------------- cosmetics

-- Owned (or test mode, src/profile.lua)
function Pass.owns(id) return Pass.owned[id] == true or (Profile.testMode and Cosmetics.get(id) ~= nil) end

-- Equipped skin id for a rowdy definition (nil = default look)
function Pass.skinFor(def)
    local id = def and Pass.skins[def.name]
    if id and Pass.owns(id) and Cosmetics.skinFor(def, id) then return id end
end

function Pass.setSkin(def, id)
    Pass.skins[def.name] = id
    Pass.save()
end

-- Equipped trail / pedestal / badge / title id (nil = none)
function Pass.equippedId(kind)
    local id = Pass.equipped[kind]
    if id and Pass.owns(id) and Cosmetics.get(id, kind) then return id end
end

function Pass.equip(kind, id)
    Pass.equipped[kind] = id
    Pass.save()
end

-- What the own rowdy shows (sent to a LAN host): { skin, trail, title, badge }
function Pass.style(def)
    return { skin = Pass.skinFor(def), trail = Pass.equippedId("trail"),
             title = Pass.equippedId("title"), badge = Pass.equippedId("badge") }
end

return Pass
