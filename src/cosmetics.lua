-- Cosmetics: things that only change how a rowdy or the lobby looks, never the game.
-- They are Yard Pass rewards (src/seasons.lua: { cosmetic = "<id>" }); what this device
-- owns and has equipped is kept in pass.txt (src/pass.lua). Drawing: src/decor.lua,
-- skins also in src/assets.lua (Assets.look) and src/rowdy.lua.
--
-- Every entry: id (unique, no spaces; "<kind>.<...>" by convention), kind, name.
--   skin      rowdy = name of the rowdy it is for (src/rowdies.lua), and either
--               hue   = turn of the colours (0..1, 0.5 = opposite colours), optional
--                       sat (saturation factor, default 1) and bright (default 1);
--                       grey/black and skin tones stay as they are (a small shader);
--                       tint = { r, g, b } colours the grey parts (metal) too
--             or
--               image = "<name>": its own art, assets/images/comic/<name>.png (+ side/
--                       <name>.png for the lobby), drawn with the rowdy's origin/muzzle
--                       (same pose, see tools/make_comic_sprites.py)
--   trail     color = { r, g, b } of the bullets, style = "leaf" | "spark" | "bubble"
--             (what the bullets leave behind)
--   pedestal  style = "flowerpot" (lobby pedestal, drawn in src/decor.lua)
--   badge     icon = "flower" | "star" | "shield", color = { r, g, b } (small medal
--             next to the name)
--   title     the name is the title ("Yard Veteran"), shown under the name
local Cosmetics = {
    -- Season 1 "Garden Party"
    -- (hues: the Gunner and Shotgunner are mostly blue (0.58), the Sniper green (0.3),
    -- the Robot grey with red (0) details)
    { id = "skin.gunner.rose", kind = "skin", rowdy = "Gunner", name = "Rose", hue = 0.37, sat = 0.9 },
    { id = "skin.shotgunner.sunflower", kind = "skin", rowdy = "Shotgunner", name = "Sunflower",
      hue = 0.55, sat = 1.1, bright = 1.1 },
    { id = "skin.sniper.tulip", kind = "skin", rowdy = "Sniper", name = "Tulip", hue = 0.67, sat = 1.6 },
    { id = "skin.robot.lavender", kind = "skin", rowdy = "Robot", name = "Lavender", hue = 0.78,
      tint = { 0.86, 0.76, 1 } },
    { id = "trail.leaf", kind = "trail", name = "Leaf trail", color = { 0.45, 0.9, 0.3 }, style = "leaf" },
    { id = "pedestal.flowerpot", kind = "pedestal", name = "Flower pot", style = "flowerpot" },
    { id = "badge.garden", kind = "badge", name = "Garden Party", icon = "flower",
      color = { 0.95, 0.45, 0.6 } },
    { id = "title.veteran", kind = "title", name = "Yard Veteran" },
}

Cosmetics.KINDS = { skin = true, trail = true, pedestal = true, badge = true, title = true }

local byId = {}

-- Check the entries when the file loads (like src/rowdies.lua)
do
    local Rowdies = require("src.rowdies")
    local names = {}
    for _, def in ipairs(Rowdies) do names[def.name] = true end
    local NUMBER, STRING, TABLE = "number", "string", "table"
    local FIELDS = {
        skin = { rowdy = STRING, hue = NUMBER, sat = NUMBER, bright = NUMBER, tint = TABLE, image = STRING },
        trail = { color = TABLE, style = STRING },
        pedestal = { style = STRING },
        badge = { icon = STRING, color = TABLE },
        title = {},
    }
    local STYLES = { trail = { leaf = true, spark = true, bubble = true },
                     pedestal = { flowerpot = true }, badge = { flower = true, star = true, shield = true } }
    for i, c in ipairs(Cosmetics) do
        local function fail(msg)
            error("src/cosmetics.lua: entry " .. i .. " (" .. tostring(c.id) .. "): " .. msg, 0)
        end
        if type(c.id) ~= STRING or not c.id:match("^%S+$") then fail("needs an id without spaces") end
        if byId[c.id] then fail("id used twice") end
        if not Cosmetics.KINDS[c.kind] then fail("unknown kind '" .. tostring(c.kind) .. "'") end
        if type(c.name) ~= STRING then fail("needs a name") end
        local allowed = FIELDS[c.kind]
        for k, v in pairs(c) do
            if k ~= "id" and k ~= "kind" and k ~= "name" then
                if not allowed[k] then fail("unknown field '" .. tostring(k) .. "'") end
                if type(v) ~= allowed[k] then fail("'" .. k .. "' must be a " .. allowed[k]) end
            end
        end
        if c.kind == "skin" then
            if not names[c.rowdy] then fail("rowdy '" .. tostring(c.rowdy) .. "' doesn't exist") end
            if not (c.hue or c.tint) == not c.image then fail("needs either hue/tint or image") end
            if c.tint and #c.tint ~= 3 then fail("tint must be { r, g, b }") end
        end
        local styleKey = (c.kind == "badge") and "icon" or "style"
        if STYLES[c.kind] and not STYLES[c.kind][c[styleKey]] then
            fail("unknown " .. styleKey .. " '" .. tostring(c[styleKey]) .. "'")
        end
        if (c.kind == "trail" or c.kind == "badge") and #c.color ~= 3 then
            fail("color must be { r, g, b }")
        end
        byId[c.id] = c
    end
end

-- The entry with this id, or nil (unknown ids - e.g. from another build over LAN -
-- just mean "default")
function Cosmetics.get(id, kind)
    local c = id and byId[id]
    if c and (not kind or c.kind == kind) then return c end
end

-- A skin for this rowdy definition, or nil if the id isn't one
function Cosmetics.skinFor(def, id)
    local c = Cosmetics.get(id, "skin")
    if c and def and c.rowdy == def.name then return c end
end

-- All skins of a rowdy, in list order
function Cosmetics.skinsOf(name)
    local list = {}
    for _, c in ipairs(Cosmetics) do
        if c.kind == "skin" and c.rowdy == name then list[#list + 1] = c end
    end
    return list
end

-- All entries of a kind, in list order
function Cosmetics.ofKind(kind)
    local list = {}
    for _, c in ipairs(Cosmetics) do
        if c.kind == kind then list[#list + 1] = c end
    end
    return list
end

return Cosmetics
