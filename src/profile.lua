-- The player's progress on this device: coins and the rowdies bought with them.
-- Everybody starts with the Shotgunner only; the others have a `price` (src/rowdies.lua)
-- or come from the Yard Pass (`pass`, given by Profile.grant).
-- Coins come from rounds (Profile.roundReward) and from loot boxes in the arena (a
-- "coin" event of the world for the own rowdy). In a LAN game every device keeps its
-- own profile; the host only reports what happened.
-- Saved in profile.txt: "coins <n>" and "unlocked <name> <name> ..." (names, not
-- indexes, so the rowdy list can be reordered).
local Profile = {}

Profile.STARTER = "Shotgunner" -- the free one (no price), chosen on a first start
-- Coins per round: win / draw / loss (duel, team fight); waves: per cleared wave
Profile.REWARD = { win = 30, draw = 10, loss = 5, wave = 5 }

Profile.coins = 0
Profile.unlocked = {} -- name -> true (bought ones)

-- Test mode (hidden: tap the version line in the lobby 7 times): every rowdy and every
-- Yard Pass cosmetic counts as owned (src/pass.lua), without writing that into
-- profile.txt / pass.txt - switched off, the real progress is back. Remembered in
-- testmode.txt.
Profile.testMode = false

local FILE = "profile.txt"
local TEST_FILE = "testmode.txt"

function Profile.setTestMode(on)
    Profile.testMode = on
    if on then love.filesystem.write(TEST_FILE, "on\n") else love.filesystem.remove(TEST_FILE) end
end

function Profile.load()
    Profile.testMode = love.filesystem.getInfo(TEST_FILE) ~= nil
    if not love.filesystem.getInfo(FILE) then return end
    for line in (love.filesystem.read(FILE) or ""):gmatch("[^\n]+") do
        local key, rest = line:match("^(%S+)%s*(.*)$")
        if key == "coins" then
            Profile.coins = math.max(0, math.floor(tonumber(rest) or 0))
        elseif key == "unlocked" then
            for name in rest:gmatch("%S+") do Profile.unlocked[name] = true end
        end
    end
end

function Profile.save()
    local names = {}
    for name in pairs(Profile.unlocked) do names[#names + 1] = name end
    table.sort(names)
    love.filesystem.write(FILE, "coins " .. Profile.coins .. "\nunlocked " ..
        table.concat(names, " ") .. "\n")
end

-- Usable (bought, free, or test mode)
function Profile.isUnlocked(def)
    return Profile.testMode or Profile.owns(def)
end

-- Really bought, won or free (ignores the test mode)
function Profile.owns(def)
    return Profile.unlocked[def.name] == true or not (def.price or def.pass)
end

-- A pass rowdy (src/rowdies.lua `pass`) is never for sale
function Profile.canAfford(def)
    return not def.pass and Profile.coins >= (def.price or 0)
end

-- Buy a rowdy. Returns true if it is unlocked now.
function Profile.unlock(def)
    if Profile.isUnlocked(def) then return true end
    if not Profile.canAfford(def) then return false end
    Profile.coins = Profile.coins - def.price
    Profile.unlocked[def.name] = true
    Profile.save()
    return true
end

-- A rowdy for free (a Yard Pass reward, src/pass.lua)
function Profile.grant(name)
    Profile.unlocked[name] = true
    Profile.save()
end

function Profile.addCoins(n)
    if n <= 0 then return end
    Profile.coins = Profile.coins + n
    Profile.save()
end

-- Coins for a finished round. outcome: "win" | "draw" | "loss" | "waves" (with the
-- wave reached; the wave the round ended in doesn't count as cleared).
function Profile.roundReward(outcome, wave)
    if outcome == "waves" then return Profile.REWARD.wave * math.max(0, (wave or 1) - 1) end
    return Profile.REWARD[outcome] or 0
end

return Profile
