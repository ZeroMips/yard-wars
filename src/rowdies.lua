-- Playable rowdies. To add one: add an entry.
--   character  sprite set (see Assets.characterNames)
--   role       short description for the rowdy choice screen
--   weapon     pose the character holds: "gun", "machine" or "silencer"
--   comic      look for the comic art style (Assets.style = "comic"):
--                image   assets/images/comic/<image>.png (art faces UP)
--                origin  body centre in the image (px); the sprite rotates around it
--                muzzle  {forward, sideways} barrel tip from the origin (image px)
--              tools/make_comic_sprites.py prints origin and muzzle for new images.
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
--   super        special attack, charged by dealing damage (optional):
--                  name, description, charge (damage needed to fill the meter), and
--                  like above pellets, spread, damage, range, bulletSpeed, plus
--                  radius (bullet size, default 6) and pierce (flies through rowdies)
local Rowdies = {
    {
        name = "Gunner", role = "All-rounder", character = "manBlue", weapon = "gun",
        comic = { image = "gunner", origin = { 46, 65 }, muzzle = { 63, 0 } },
        stats = { speed = 250, hp = 100, damage = 20, range = 480, bulletSpeed = 600,
                  reload = 0.3, maxAmmo = 3, ammoRefill = 1.2,
                  super = { name = "Bullet Storm", description = "Fan of 10 bullets",
                            charge = 200, pellets = 10, spread = 0.9,
                            damage = 22, range = 520, bulletSpeed = 750 } },
    },
    {
        name = "Shotgunner", role = "Close range, tough", character = "hitman1",
        weapon = "machine",
        comic = { image = "shotgunner", origin = { 46, 84 }, muzzle = { 82, 0 } },
        stats = { speed = 240, hp = 120, damage = 9, pellets = 5, spread = 0.6,
                  range = 320, bulletSpeed = 600,
                  reload = 0.4, maxAmmo = 3, ammoRefill = 1.6,
                  super = { name = "Wrecking Ball",
                            description = "Big ball that rolls through everyone", charge = 180, damage = 75, range = 440,
                            bulletSpeed = 450, radius = 16, pierce = true } },
    },
    {
        name = "Sniper", role = "Long range, fragile", character = "manBrown",
        weapon = "silencer",
        comic = { image = "sniper", origin = { 46, 89 }, muzzle = { 87, 0 } },
        stats = { speed = 225, hp = 80, damage = 50, range = 720, bulletSpeed = 1100,
                  reload = 0.5, maxAmmo = 3, ammoRefill = 2.0,
                  super = { name = "Railgun", description = "Fast shot through everyone",
                            charge = 150, damage = 90, range = 960,
                            bulletSpeed = 1800, radius = 7, pierce = true } },
    },
}

-- The enemy bots (not playable, so not part of the list above)
Rowdies.bot = {
    name = "Bot", character = "robot1", weapon = "machine",
    comic = { image = "bot", origin = { 46, 81 }, muzzle = { 79, 0 } },
    stats = { speed = 170, hp = 100, damage = 15, reload = 0.6, maxAmmo = 3, ammoRefill = 1.8,
              barColor = { 0.9, 0.25, 0.25 }, bulletColor = { 1, 0.35, 0.3 } },
}

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
