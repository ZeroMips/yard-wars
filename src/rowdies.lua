-- Playable rowdies. To add one: add an entry.
--   character  sprite set (see Assets.characterNames)
--   weapon     pose the character holds: "gun", "machine" or "silencer"
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
return {
    {
        name = "Gunner", character = "manBlue", weapon = "gun",
        stats = { speed = 250, hp = 100, damage = 20, range = 480, bulletSpeed = 600,
                  reload = 0.3, maxAmmo = 3, ammoRefill = 1.2 },
    },
    {
        name = "Shotgunner", character = "hitman1", weapon = "machine",
        stats = { speed = 240, hp = 120, damage = 9, pellets = 5, spread = 0.6,
                  range = 320, bulletSpeed = 600,
                  reload = 0.4, maxAmmo = 3, ammoRefill = 1.6 },
    },
    {
        name = "Sniper", character = "manBrown", weapon = "silencer",
        stats = { speed = 225, hp = 80, damage = 50, range = 720, bulletSpeed = 1100,
                  reload = 0.5, maxAmmo = 3, ammoRefill = 2.0 },
    },
}
