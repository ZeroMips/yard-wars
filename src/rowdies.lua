-- Playable rowdies. To add one: add an entry.
--   character  sprite set (see Assets.characterNames)
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
local Rowdies = {
    {
        name = "Gunner", character = "manBlue", weapon = "gun",
        comic = { image = "gunner", origin = { 46, 65 }, muzzle = { 63, 0 } },
        stats = { speed = 250, hp = 100, damage = 20, range = 480, bulletSpeed = 600,
                  reload = 0.3, maxAmmo = 3, ammoRefill = 1.2 },
    },
    {
        name = "Shotgunner", character = "hitman1", weapon = "machine",
        comic = { image = "shotgunner", origin = { 46, 84 }, muzzle = { 82, 0 } },
        stats = { speed = 240, hp = 120, damage = 9, pellets = 5, spread = 0.6,
                  range = 320, bulletSpeed = 600,
                  reload = 0.4, maxAmmo = 3, ammoRefill = 1.6 },
    },
    {
        name = "Sniper", character = "manBrown", weapon = "silencer",
        comic = { image = "sniper", origin = { 46, 89 }, muzzle = { 87, 0 } },
        stats = { speed = 225, hp = 80, damage = 50, range = 720, bulletSpeed = 1100,
                  reload = 0.5, maxAmmo = 3, ammoRefill = 2.0 },
    },
}

-- Look of the enemy bots (not playable, so not part of the list above)
Rowdies.bot = {
    character = "robot1", weapon = "machine",
    comic = { image = "bot", origin = { 46, 81 }, muzzle = { 79, 0 } },
}

return Rowdies
