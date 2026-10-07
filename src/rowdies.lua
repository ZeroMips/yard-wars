-- Playable rowdies. Adding one = one entry here + its images:
--   1. Make a top view (facing UP) and a side view (standing, facing right) on white
--      background (same Gemini chat as the others, see CLAUDE.md "Art"); put them as
--      <image>.png into ~/Downloads/yard-wars-art-new/top/ and .../side/.
--   2. Add the entry below with comic = { image = "<image>" } (the tool finds the
--      names here), then run
--        python3 tools/make_comic_sprites.py --scale 0.27 ~/Downloads/yard-wars-art-new/top <image>
--        python3 tools/make_comic_sprites.py --side ~/Downloads/yard-wars-art-new/side <image>
--   3. Paste the printed `comic = { ... }` line into the entry.
--   4. Fill in name, role, stats, price (or pass) and optionally shot.
--
--   name       shown in menus; also the key profile.txt stores bought rowdies by
--   role       short description for the rowdy choice screen
--   price      coins to unlock it, paid when its boss fight is won (src/unlock.lua);
--              none = free from the start
--   pass       true = its boss fight is a Yard Pass reward (a tier in src/seasons.lua),
--              never for coins; needs no price. Players who bought it before keep
--              it (profile.txt lists owned rowdies by name)
--   shot       shot sound (a name from src/sound.lua's DEFS, default "shot_gunner")
--   comic      look:
--                image   assets/images/comic/<image>.png (art faces UP, required)
--                origin  body centre in the image (px); the sprite rotates around it
--                muzzle  {forward, sideways} barrel tip from the origin (image px)
--              assets/images/side/<image>.png (optional): side view standing on the
--              lobby pedestal (without one the lobby shows the top view)
--
-- stats:
--   speed        walking speed (px/s)
--   hp           health
--   damage       damage PER PROJECTILE
--   pellets      projectiles per attack (default 1)
--   spread       total cone angle of the pellets in radians (default 0)
--   range        how far projectiles fly (px)
--   bulletSpeed  projectile speed (px/s)
--   reload       minimum delay between two attacks (s)
--   maxAmmo      ammo bars
--   ammoRefill   seconds until one ammo bar refills
--   lob          true: throws bombs - they fly in an arc over walls, rowdies and
--                chests to where the player aims (how far the aim stick is pulled /
--                the mouse distance, at most `range`) and explode there
--   blast        radius of the explosion (px) of a lob attack: every opponent and chest
--                in it takes `damage` once
--   super        special attack, charged by dealing damage (optional):
--                  name, description, charge (damage needed to fill the meter), and
--                  like above pellets, spread, damage, range, bulletSpeed, plus
--                  radius (bullet size, default 6), wallRadius (size against walls and
--                  crates, default radius) and pierce (flies through rowdies);
--                  spread >= pi: a ring around the rowdy instead of a cone; lob +
--                  blast as above
local Rowdies = {
    {
        name = "Gunner", role = "All-rounder", price = 150, shot = "shot_gunner",
        comic = { image = "gunner", origin = { 46, 80 }, muzzle = { 77, 0 } },
        stats = { speed = 250, hp = 100, damage = 20, range = 480, bulletSpeed = 600,
                  reload = 0.3, maxAmmo = 3, ammoRefill = 1.2,
                  super = { name = "Bullet Storm", description = "Fan of 10 bullets",
                            charge = 200, pellets = 10, spread = 0.9,
                            -- 10 x 14 = 140 point blank (22 did 220, twice any HP)
                            damage = 14, range = 520, bulletSpeed = 750 } },
    },
    {
        name = "Shotgunner", role = "Close range, tough", shot = "shot_shotgun",
        comic = { image = "shotgunner", origin = { 48, 91 }, muzzle = { 88, 0.5 } },
        stats = { speed = 240, hp = 120, damage = 9, pellets = 5, spread = 0.6,
                  range = 320, bulletSpeed = 600,
                  reload = 0.4, maxAmmo = 3, ammoRefill = 1.6,
                  super = { name = "Wrecking Ball",
                            description = "Big ball that rolls through everyone", charge = 180, damage = 75, range = 440,
                            -- fast enough to catch a strafing bot at mid range
                            -- (450 px/s missed every moving target)
                            bulletSpeed = 900, radius = 28, pierce = true,
                            -- grazes walls: fired right next to one (or through a
                            -- 1-tile gap) it would vanish at once with radius 28
                            wallRadius = 16 } },
    },
    {
        name = "Sniper", role = "Long range, fragile", price = 300, shot = "shot_sniper",
        comic = { image = "sniper", origin = { 33.5, 120.5 }, muzzle = { 117.5, 1 } },
        stats = { speed = 225, hp = 80, damage = 50, range = 720, bulletSpeed = 1100,
                  reload = 0.5, maxAmmo = 3, ammoRefill = 2.0,
                  super = { name = "Railgun", description = "Fast shot through everyone",
                            charge = 150, damage = 90, range = 960,
                            bulletSpeed = 1800, radius = 7, pierce = true } },
    },
    {
        name = "Robot", role = "Heavy and slow", price = 500, shot = "shot_bot",
        comic = { image = "robot", origin = { 46, 96 }, muzzle = { 93, 1 } },
        stats = { speed = 205, hp = 160, damage = 34, range = 420, bulletSpeed = 650,
                  reload = 0.55, maxAmmo = 3, ammoRefill = 1.9,
                  super = { name = "Shockwave", description = "Ring of bolts all around",
                            -- 16 bolts, 22.5 degrees apart: at point blank 2-3 hit
                            charge = 170, pellets = 16, spread = 2 * math.pi * 15 / 16,
                            damage = 30, range = 360, bulletSpeed = 700, radius = 9 } },
    },
    {
        -- Season 1 "Garden Party" (src/seasons.lua: tier 10, only there). Origin by hand:
        -- the water tank on the back made the tool's guess sit below the hat's centre.
        name = "Gardener", role = "Water spray, mid range", pass = true, shot = "shot_water",
        comic = { image = "gardener", origin = { 51.5, 108 }, muzzle = { 105, -0.5 } },
        stats = { speed = 240, hp = 110, damage = 7, pellets = 4, spread = 0.22,
                  range = 380, bulletSpeed = 750, reload = 0.25, maxAmmo = 3, ammoRefill = 1.3,
                  bulletColor = { 0.45, 0.8, 1 },
                  super = { name = "Sprinkler Burst", description = "Wide fan of drops that soak through everyone",
                            -- 7 x 20 = 140 if all drops hit one rowdy point blank
                            charge = 170, pellets = 7, spread = 1.2, damage = 20, range = 460,
                            bulletSpeed = 700, radius = 10, wallRadius = 6, pierce = true } },
    },
    {
        -- Bought with coins (not a pass reward). Origin + muzzle by hand: the tool took
        -- the fuse spark as the muzzle; bombs start at the bomb in his hands.
        name = "Pirate", role = "Bombs over walls", price = 450, shot = "shot_throw",
        comic = { image = "pirate", origin = { 55, 98 }, muzzle = { 55, 0 } },
        stats = { speed = 235, hp = 100, damage = 40, range = 420, bulletSpeed = 520,
                  reload = 0.7, maxAmmo = 2, ammoRefill = 1.9, lob = true, blast = 90,
                  bulletColor = { 1, 0.55, 0.15 },
                  super = { name = "Powder Keg", description = "Huge blast, thrown over walls",
                            charge = 160, damage = 90, range = 400, bulletSpeed = 450,
                            radius = 16, lob = true, blast = 170 } },
    },
}

-- The enemy bots (not playable, so not part of the list above)
Rowdies.bot = {
    name = "Bot", shot = "shot_bot",
    comic = { image = "bot", origin = { 46, 81 }, muzzle = { 79, 0 } },
    stats = { speed = 170, hp = 100, damage = 15, reload = 0.6, maxAmmo = 3, ammoRefill = 1.8,
              barColor = { 0.9, 0.25, 0.25 }, bulletColor = { 1, 0.35, 0.3 } },
}

-- Check the entries when this file loads: a typo ("bulletspeed") would otherwise
-- silently fall back to a default. Allowed fields and their types:
local NUMBER, STRING, BOOL, TABLE = "number", "string", "boolean", "table"
local ENTRY = { name = STRING, role = STRING, price = NUMBER, pass = BOOL, shot = STRING,
                comic = TABLE, stats = TABLE }
local COMIC = { image = STRING, origin = TABLE, muzzle = TABLE }
local STATS = { speed = NUMBER, hp = NUMBER, damage = NUMBER, pellets = NUMBER,
                spread = NUMBER, range = NUMBER, bulletSpeed = NUMBER, reload = NUMBER,
                maxAmmo = NUMBER, ammoRefill = NUMBER, super = TABLE,
                barColor = TABLE, bulletColor = TABLE, lob = BOOL, blast = NUMBER }
local SUPER = { name = STRING, description = STRING, charge = NUMBER, pellets = NUMBER,
                spread = NUMBER, damage = NUMBER, range = NUMBER, bulletSpeed = NUMBER,
                radius = NUMBER, wallRadius = NUMBER, pierce = BOOL, lob = BOOL, blast = NUMBER }

local function validate(def, label)
    local function fail(msg) error("src/rowdies.lua: " .. label .. ": " .. msg, 0) end
    local function check(t, allowed, where)
        if type(t) ~= TABLE then fail(where .. " must be a table") end
        for k, v in pairs(t) do
            if not allowed[k] then fail("unknown field '" .. where .. tostring(k) .. "'") end
            if type(v) ~= allowed[k] then
                fail("'" .. where .. k .. "' must be a " .. allowed[k] .. ", not " .. type(v))
            end
        end
    end
    check(def, ENTRY, "")
    -- names are stored space-separated in profile.txt
    if not def.name or not def.name:match("^%S+$") then fail("needs a name without spaces") end
    if not def.comic or not def.comic.image then fail("needs comic = { image, origin, muzzle }") end
    check(def.comic, COMIC, "comic.")
    for _, k in ipairs({ "origin", "muzzle" }) do
        local v = def.comic[k]
        if not v or type(v[1]) ~= NUMBER or type(v[2]) ~= NUMBER then
            fail("comic." .. k .. " must be { x, y } (paste the line printed by "
                .. "tools/make_comic_sprites.py)")
        end
    end
    if not def.stats then fail("needs stats") end
    check(def.stats, STATS, "stats.")
    local sup = def.stats.super
    if sup then
        check(sup, SUPER, "stats.super.")
        if not sup.name or not sup.charge then fail("stats.super needs name and charge") end
    end
    for _, a in ipairs({ { def.stats, "stats." }, { sup, "stats.super." } }) do
        local t = a[1]
        if t and (t.lob or t.blast) and not (t.lob and t.blast and t.blast > 0) then
            fail(a[2] .. "lob and " .. a[2] .. "blast belong together (blast = radius > 0)")
        end
    end
    if def.price and (def.price <= 0 or def.price % 1 ~= 0) then
        fail("price must be a whole number > 0 (none = free)")
    end
    if def.pass and def.price then fail("a pass rowdy has no price (only the Yard Pass gives it)") end
end

do
    local names = {}
    for i, def in ipairs(Rowdies) do
        validate(def, "entry " .. i .. " (" .. tostring(def.name) .. ")")
        if names[def.name] then error("src/rowdies.lua: two rowdies named " .. def.name, 0) end
        names[def.name] = true
    end
    validate(Rowdies.bot, "Rowdies.bot")
end

-- Short key for a definition (sent over the network): its index, or "bot"
function Rowdies.key(def)
    if def == Rowdies.bot then return "bot" end
    for i, d in ipairs(Rowdies) do
        if d == def then return i end
    end
end

function Rowdies.byKey(key)
    if key == "bot" then return Rowdies.bot end
    return Rowdies[key]
end

return Rowdies
