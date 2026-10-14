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
--   name       shown in menus; also the key profile.txt stores bought rowdies by (may
--              contain single spaces, saved as "_"; so no "_" in names)
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
--                in it takes `damage` once; on a shot (no lob): it bursts like that where
--                it stops - on the first rowdy, wall or chest it hits, or at its range
--                (firework rockets)
--   radius       projectile size (default 6); wallRadius: its size against walls and
--                crates (default radius); pierce: flies through rowdies (hits each once)
--   boomerang    true: flies `range`, turns and flies back to where it was thrown;
--                hits each rowdy once per leg (a wall or chest turns it early)
--   burst        shots per attack (default 1), burstDelay seconds apart (default 0.08);
--                one ammo bar for all; twin = true: the shots come alternately from the
--                muzzle and its mirror image (two blasters)
--   freeze       seconds an opponent hit (or in the blast) can't move or attack
--   pull         true: the opponent hit flies to the shooter
--   hold         seconds an opponent hit can't walk (handcuffs; it may still attack)
--   goo          extra damage an opponent hit takes over the next 2 s (sticky goo,
--                World.GOO_TIME); hit again, it starts over
--   chargeHit    super charge per hit instead of the damage (for an attack without
--                damage: the handcuffs)
--   heal         share of the max HP a kind "heal" gives back (default 0.5)
--   targets      how many opponents a kind "magnet" pulls (default 2)
--   dash         px the rowdy dashes forward before each shot (punches: a short range,
--                big radius and pierce make the "shot" a melee hit)
--   kind         what the attack does (default: fires projectiles):
--                  "leap"   the rowdy jumps aimDist far (at most range, over walls,
--                           at bulletSpeed px/s, can't be hit meanwhile) and lands with
--                           a blast (blast radius, damage)
--                  "burrow" the rowdy digs in for `duration` seconds: can't be hit or
--                           attack, walks faster; pops out under the first opponent it
--                           touches (or when the time is up) with a blast; range = how
--                           near a bot must be to start it
--                  "blink"  teleports aimDist far (at most range, also through walls,
--                           onto open ground) with a blast where it appears
--                  "vanish" invisible (except up close) and through walls for
--                           `duration` seconds; range: for bots, as for burrow
--                  "beam"   a beam while the attack is held: hits the first opponent
--                           or chest on it for `damage` every 0.1 s, uses 1 ammo bar per
--                           second (refills smoothly while it is off)
--                  "grab"   the beam grabs the first opponent on it: it follows the aim
--                           for `duration` seconds (default 1.2), then it is flung;
--                           crashing into a wall, chest or rowdy does `damage`
--                  "heal"   heals the rowdy by `heal` (bots use it when hurt)
--                  "spin"   hits everybody within `blast` around the rowdy (range =
--                           how near a bot must be: set it to about blast)
--                  "gust"   dashes aimDist far (at most range, at bulletSpeed px/s), stops
--                           at the first opponent or wall and hits around it (blast)
--                  "magnet" pulls the `targets` nearest opponents within range (in
--                           sight) to the rowdy, with `damage` each (pull = true)
--                  "barrier" a fence in front of the rowdy for `duration` seconds:
--                           opponents can't walk or shoot through, the own team can
--   projectile   how it is drawn (src/bullet.lua): "pen", "book", "pan", "waffle",
--                "snowball", "potion", "magnet", "glove", "swing", "apple", "stone",
--                "goo", "rocket", "cuffs"; for a leap / burrow / blink / spin / gust its
--                blast: "slam", "dirt", "boo", "whirl"; default a ball in bulletColor (a bomb for
--                lob)
--   super        special attack, charged by dealing damage (optional):
--                  name, description, charge (damage needed to fill the meter), and
--                  and every attack field above (pellets, spread, damage, range,
--                  bulletSpeed, radius, pierce, lob, blast, boomerang, burst, ...);
--                  spread >= pi: a ring around the rowdy instead of a cone (pellets
--                  evenly all around, the first one along the aim)
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
    {
        -- Gideon's design sheets (2026-10-08): pen + book. The new rowdies' art: one
        -- Gemini sheet each (--scale 0.253), origin + muzzle set by hand (head centre,
        -- weapon tip); some side views mirrored (drawn facing left)
        name = "Student", role = "Long shots, falls easily", price = 300, shot = "shot_pen",
        comic = { image = "student", origin = { 52.5, 115 }, muzzle = { 110, 0 } },
        stats = { speed = 245, hp = 90, damage = 24, range = 560, bulletSpeed = 900,
                  reload = 0.35, maxAmmo = 3, ammoRefill = 1.5, projectile = "pen",
                  bulletColor = { 0.25, 0.45, 1 },
                  super = { name = "Book Drop", description = "A heavy book, thrown over walls",
                            charge = 160, damage = 70, range = 420, bulletSpeed = 500,
                            radius = 14, lob = true, blast = 80, projectile = "book" } },
    },
    {
        -- A frying pan like a boomerang, waffle irons as the super
        name = "Chef", role = "Pan that comes back", price = 400, shot = "shot_pan",
        comic = { image = "chef", origin = { 52.5, 117 }, muzzle = { 88, 0 } },
        stats = { speed = 235, hp = 120, damage = 26, range = 380, bulletSpeed = 650,
                  reload = 0.5, maxAmmo = 3, ammoRefill = 1.6, boomerang = true,
                  radius = 12, wallRadius = 8, projectile = "pan",
                  bulletColor = { 1, 0.7, 0.35 }, -- (the pan has its own colours: aim beam)
                  super = { name = "Waffle Toss", description = "Two waffle irons, through everyone",
                            -- 2 x 60, in a V: point blank both can hit one rowdy
                            charge = 180, pellets = 2, spread = 0.9, damage = 60, range = 460,
                            bulletSpeed = 750, radius = 20, wallRadius = 10, pierce = true,
                            projectile = "waffle" } },
    },
    {
        -- Two toy blasters (bursts) and freeze balls (CHARTER.md: toys, a short freeze)
        name = "Agent Angel", role = "Blaster bursts, freezes", price = 450, shot = "shot_blaster",
        comic = { image = "agent", origin = { 54, 104 }, muzzle = { 99, 29 } },
        stats = { speed = 250, hp = 100, damage = 9, burst = 4, burstDelay = 0.07, twin = true,
                  range = 450, bulletSpeed = 800, reload = 0.45, maxAmmo = 3, ammoRefill = 1.5,
                  bulletColor = { 1, 0.4, 0.75 },
                  super = { name = "Freeze Balls", description = "Three balls that freeze everyone they splash",
                            charge = 170, pellets = 3, spread = 0.7, damage = 20, range = 420,
                            bulletSpeed = 500, radius = 11, lob = true, blast = 70, freeze = 1.5,
                            projectile = "snowball" } },
    },
    {
        -- A cheerful mad scientist: slime potions and a magnet (CHARTER.md: slime, not
        -- poison). "Doctor Dummie" on Gideon's sheet; he chose the English name.
        name = "Doctor Fizzle", role = "Slime potions, pulls", price = 400, shot = "shot_potion",
        comic = { image = "doctor", origin = { 54.5, 105 }, muzzle = { 77, 0 } },
        stats = { speed = 240, hp = 110, damage = 32, range = 400, bulletSpeed = 520,
                  reload = 0.5, maxAmmo = 3, ammoRefill = 1.6, lob = true, blast = 60,
                  projectile = "potion", bulletColor = { 0.45, 0.95, 0.3 },
                  super = { name = "Magnet Potion", description = "Pulls the first one it hits right to you",
                            charge = 160, damage = 40, range = 480, bulletSpeed = 850,
                            radius = 12, pull = true, projectile = "magnet" } },
    },
    {
        -- Jumps onto opponents; the super is a combo of four punches (cartoon gloves)
        name = "Wrestler", role = "Jumps on you, tough", price = 450, shot = "jump",
        comic = { image = "wrestler", origin = { 56, 72 }, muzzle = { 62, 0 } },
        stats = { speed = 215, hp = 150, kind = "leap", damage = 40, blast = 70, range = 250,
                  -- (45 dmg / 1.8 s refill won 10:0 against a bot: it can't be hit in
                  -- the air and lands right on a standing target)
                  bulletSpeed = 650, reload = 0.8, maxAmmo = 2, ammoRefill = 2.0,
                  projectile = "slam", bulletColor = { 1, 0.8, 0.3 },
                  super = { name = "Punch Combo", description = "Four punches, a step forward each",
                            -- 4 x 28 = 112 if every punch lands
                            charge = 170, burst = 4, burstDelay = 0.2, dash = 50, damage = 28,
                            range = 70, bulletSpeed = 800, radius = 24, wallRadius = 8,
                            pierce = true, projectile = "glove" } },
    },
    {
        -- A shovel (CHARTER.md: no sword) and digging in
        name = "Digger", role = "Shovel up close, digs", price = 350, shot = "shot_shovel",
        comic = { image = "digger", origin = { 79.5, 62 }, muzzle = { 45, 0 } },
        stats = { speed = 240, hp = 130, damage = 36, range = 75, bulletSpeed = 750,
                  radius = 24, wallRadius = 8, pierce = true, reload = 0.4, maxAmmo = 3,
                  ammoRefill = 1.1, projectile = "swing", bulletColor = { 0.85, 0.75, 0.55 },
                  super = { name = "Burrow", description = "Digs in and pops out under someone",
                            charge = 160, kind = "burrow", duration = 4, damage = 70, blast = 90,
                            range = 450, projectile = "dirt" } },
    },
    {
        -- A friendly cartoon ghost: teleports with a "boo", vanishes through walls
        name = "Ghostman", role = "Teleports, vanishes", price = 500, shot = "boo",
        comic = { image = "ghostman", origin = { 58.5, 82 }, muzzle = { 74, 0 } },
        stats = { speed = 250, hp = 90, kind = "blink", damage = 30, blast = 60, range = 220,
                  reload = 0.6, maxAmmo = 3, ammoRefill = 1.6, projectile = "boo",
                  bulletColor = { 0.8, 0.92, 1 },
                  super = { name = "Vanish", description = "Invisible and through walls for 5 s",
                            charge = 150, kind = "vanish", duration = 5, range = 500 } },
    },
    {
        -- A magic beam you hold; the super grabs someone and flings them (slapstick)
        name = "Wizard", role = "Magic beam, flings", price = 500, shot = "shot_beam",
        comic = { image = "wizard", origin = { 49.5, 75 }, muzzle = { 70, -1 } },
        stats = { speed = 240, hp = 100, kind = "beam", damage = 3, range = 420, reload = 0.2,
                  maxAmmo = 3, ammoRefill = 1.5, bulletColor = { 0.75, 0.45, 1 },
                  super = { name = "Telekinesis", description = "Grabs someone, then flings them into things",
                            charge = 170, kind = "grab", duration = 1.2, damage = 50, range = 450 } },
    },
    {
        -- Gideon's second batch (photos of 2026-10-12): green goo (CHARTER.md: cartoon
        -- slime) and paper firework rockets. The name is Gideon's.
        name = "Posion", role = "Sticky goo, fireworks", price = 400, shot = "shot_goo",
        comic = { image = "posion", origin = { 52.5, 87 }, muzzle = { 83, 0 } },
        stats = { speed = 245, hp = 100, damage = 6, pellets = 5, spread = 0.7, range = 300,
                  bulletSpeed = 650, goo = 20, reload = 0.45, maxAmmo = 3, ammoRefill = 1.5,
                  projectile = "goo", bulletColor = { 0.5, 0.95, 0.2 },
                  super = { name = "Firework Volley", description = "Four rockets that pop with confetti",
                            charge = 170, burst = 4, burstDelay = 0.12, damage = 30, blast = 60,
                            range = 500, bulletSpeed = 750, radius = 10, projectile = "rocket" } },
    },
    {
        -- Two apples at once (a wide V: two opponents), heals himself with a snack
        name = "Fruit Man", role = "Two fruits at once, heals", price = 350, shot = "shot_throw",
        comic = { image = "fruitman", origin = { 57, 63 }, muzzle = { 44, 0 } },
        stats = { speed = 245, hp = 110, damage = 22, pellets = 2, spread = 0.5, range = 450,
                  bulletSpeed = 700, radius = 9, reload = 0.4, maxAmmo = 3, ammoRefill = 1.5,
                  projectile = "apple", bulletColor = { 0.9, 0.15, 0.15 },
                  super = { name = "Fruit Snack", description = "Heals half his health",
                            charge = 150, kind = "heal", heal = 0.5 } },
    },
    {
        -- Toy handcuffs hold an opponent in place (12 damage: with none he could never
        -- knock anybody out); a barrier only his own team gets through
        name = "Officer", role = "Handcuffs, barriers", price = 400, shot = "shot_cuffs",
        comic = { image = "officer", origin = { 50.5, 66 }, muzzle = { 56, 3 } },
        stats = { speed = 250, hp = 130, damage = 12, hold = 1.2, chargeHit = 25, range = 420,
                  bulletSpeed = 750, radius = 10, reload = 0.4, maxAmmo = 4, ammoRefill = 1.3,
                  projectile = "cuffs", bulletColor = { 0.85, 0.87, 0.92 },
                  super = { name = "Barrier", description = "A fence they can't pass or shoot through",
                            charge = 100, kind = "barrier", duration = 6, range = 350 } },
    },
    {
        -- A toy mech with a kid pilot: slingshot stones all around, a tractor beam
        name = "Mecha Robot", role = "Slingshots, pulls", price = 500, shot = "shot_sling",
        comic = { image = "mecha", origin = { 79, 77 }, muzzle = { 52, 0 } },
        stats = { speed = 215, hp = 150, damage = 30, pellets = 4, spread = 2 * math.pi * 3 / 4,
                  range = 420, bulletSpeed = 700, radius = 10, reload = 0.5, maxAmmo = 3,
                  ammoRefill = 1.6, projectile = "stone", bulletColor = { 0.6, 0.6, 0.62 },
                  super = { name = "Tractor Beam", description = "Pulls the two nearest to him",
                            charge = 160, kind = "magnet", targets = 2, pull = true, damage = 20,
                            range = 450 } },
    },
    {
        -- A wind kid (Gideon's second batch, art a day later): spins, rides a gust
        name = "Tornalo", role = "Spins, rides the wind", price = 450, shot = "whirl",
        comic = { image = "tornalo", origin = { 59.5, 60 }, muzzle = { 48, 0 } },
        stats = { speed = 265, hp = 140, kind = "spin", damage = 40, blast = 120, range = 120,
                  reload = 0.5, maxAmmo = 3, ammoRefill = 1.4, projectile = "whirl",
                  bulletColor = { 0.85, 0.95, 1 },
                  super = { name = "Wind Gust", description = "Rides the wind to an opponent",
                            charge = 120, kind = "gust", damage = 50, blast = 80, range = 450,
                            bulletSpeed = 1000, projectile = "whirl" } },
    },
}

-- The old enemy bot (not playable). No longer spawned - bots are random rowdies from
-- the list above (src/world.lua, BOT_DAMAGE) - but kept: the key "bot" stays valid
-- and the LAN version hash (src/net.lua) unchanged.
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
-- fields of an attack (the normal one in stats, the super in stats.super)
local ATTACK = { damage = NUMBER, pellets = NUMBER, spread = NUMBER, range = NUMBER,
                 bulletSpeed = NUMBER, radius = NUMBER, wallRadius = NUMBER, pierce = BOOL,
                 lob = BOOL, blast = NUMBER, boomerang = BOOL, burst = NUMBER,
                 burstDelay = NUMBER, twin = BOOL, freeze = NUMBER, projectile = STRING,
                 pull = BOOL, dash = NUMBER, kind = STRING, duration = NUMBER,
                 hold = NUMBER, goo = NUMBER, chargeHit = NUMBER, heal = NUMBER,
                 targets = NUMBER }
local STATS = { speed = NUMBER, hp = NUMBER, reload = NUMBER, maxAmmo = NUMBER,
                ammoRefill = NUMBER, super = TABLE, barColor = TABLE, bulletColor = TABLE }
local SUPER = { name = STRING, description = STRING, charge = NUMBER }
for k, v in pairs(ATTACK) do STATS[k], SUPER[k] = v, v end
local PROJECTILES = { pen = true, book = true, pan = true, waffle = true, snowball = true,
                      potion = true, magnet = true, glove = true, swing = true, slam = true,
                      dirt = true, boo = true, apple = true, stone = true, goo = true,
                      rocket = true, cuffs = true, whirl = true }
local KINDS = { shot = true, leap = true, burrow = true, blink = true, vanish = true,
                beam = true, grab = true, heal = true, spin = true, gust = true,
                magnet = true, barrier = true }
-- kinds that hit with a blast around a spot (they need blast = radius)
local BLASTS = { leap = true, burrow = true, blink = true, spin = true, gust = true }

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
    -- names are stored space-separated in profile.txt (a space in a name as "_")
    local name = def.name
    if not name or not name:match("^%S") or not name:match("%S$") or name:find("%s%s")
        or name:find("[_\t\n]") then
        fail("needs a name (single spaces between words, no \"_\")")
    end
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
        if t and t.lob and not (t.blast and t.blast > 0) then
            fail(a[2] .. "lob needs " .. a[2] .. "blast (radius > 0)")
        end
        if t and t.blast and t.blast <= 0 then fail(a[2] .. "blast must be a radius > 0") end
        if t and t.projectile and not PROJECTILES[t.projectile] then
            fail("unknown " .. a[2] .. "projectile '" .. t.projectile .. "' (see src/bullet.lua)")
        end
        if t and t.burst and (t.burst < 1 or t.burst % 1 ~= 0) then
            fail(a[2] .. "burst must be a whole number >= 1")
        end
        if t and t.kind and not KINDS[t.kind] then
            fail("unknown " .. a[2] .. "kind '" .. t.kind .. "'")
        end
        if t and BLASTS[t.kind] and not (t.blast and t.blast > 0) then
            fail(a[2] .. "kind " .. t.kind .. " needs blast (radius of the hit)")
        end
        if t and (t.kind == "burrow" or t.kind == "vanish" or t.kind == "barrier")
            and not (t.duration and t.duration > 0) then
            fail(a[2] .. "kind " .. t.kind .. " needs duration (seconds)")
        end
        if t and t.kind == "beam" and t == sup then fail("a beam can only be the normal attack") end
        if t and t.kind == "magnet" and not t.pull then fail(a[2] .. "kind magnet needs pull = true") end
        if t and t.blast and not t.lob and not BLASTS[t.kind] and (t.pierce or t.boomerang) then
            fail(a[2] .. "a bursting shot (blast without lob) stops at the first hit: no pierce/boomerang")
        end
        if t and t.boomerang and (t.lob or t.pierce) then
            fail(a[2] .. "boomerang can't be lob (it flies low) and pierces anyway")
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
