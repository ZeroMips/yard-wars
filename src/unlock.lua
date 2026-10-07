-- How a rowdy that isn't usable yet becomes the player's: by beating it in a boss
-- fight (World mode `boss`, src/world.lua).
--   Coin rowdy (`price`): CHALLENGE once you have the coins; they are only paid when
--     you win. Beaten but not paid (too few coins then, or you only helped a friend
--     over LAN): UNLOCK for the price, no second fight.
--   Pass rowdy (`pass`): its Yard Pass tier unlocks the boss fight (claiming the tier
--     after beating it - e.g. as a helper - gives the rowdy right away).
-- Rowdies already owned (bought or won before the boss fights) stay owned.
local Profile = require("src.profile")
local Pass    = require("src.pass")
local Seasons = require("src.seasons")

local Unlock = {}

-- Has the Yard Pass tier that gives this pass rowdy been claimed?
function Unlock.hasTicket(def)
    local season, tier = Seasons.rowdyTier(def.name)
    return season ~= nil and Pass.tierState(season, tier) == "claimed"
end

-- nil (usable), "challenge" (boss fight), "buy" (beaten, pay the price) or "pass"
-- (needs its Yard Pass tier first)
function Unlock.state(def)
    if Profile.isUnlocked(def) then return nil end
    if def.pass then return Unlock.hasTicket(def) and "challenge" or "pass" end
    return Profile.beaten[def.name] and "buy" or "challenge"
end

-- Can the boss fight start now? (a coin rowdy needs the coins ready)
function Unlock.canChallenge(def)
    return Unlock.state(def) == "challenge" and (def.pass or Profile.canAfford(def))
end

-- Why a boss fight can't start (for the notice line)
function Unlock.why(def)
    local state = Unlock.state(def)
    if state == "pass" then
        local season, tier = Seasons.rowdyTier(def.name)
        return "The " .. def.name .. "'s boss fight is a Yard Pass reward: " .. season.name
            .. ", tier " .. tier
    end
    return "You need " .. def.price .. " coins to challenge the " .. def.name
        .. " - win rounds and break boxes"
end

-- The boss fight against `def` was won. challenger: this device started it (a LAN
-- client only helped: it doesn't pay automatically). Returns the message for the
-- result screen.
function Unlock.won(def, challenger)
    if Profile.owns(def) then return nil end
    Profile.beat(def.name)
    if def.pass then
        if Unlock.hasTicket(def) then
            Profile.grant(def.name)
            return def.name .. " unlocked!"
        end
        local season, tier = Seasons.rowdyTier(def.name)
        return "You beat the " .. def.name .. "! Claim it at tier " .. tier .. " of "
            .. season.name
    end
    if challenger and Profile.unlock(def) then
        return def.name .. " unlocked!  (-" .. def.price .. " coins)"
    end
    return "You beat the " .. def.name .. "! Unlock it in the lobby for " .. def.price .. " coins"
end

return Unlock
