-- Loads all images and defines quads for the Kenney tilesheet.
local Assets = {}

local TILE = 64

-- Each character has these poses (files: assets/images/characters/<name>_<pose>.png)
Assets.characterNames = { "manBlue", "hitman1", "manBrown", "robot1" }
local POSES = { "stand", "hold", "gun", "machine", "silencer", "reload" }

-- Art style: "comic" (one AI-generated still per character, see tools/make_comic_sprites.py)
-- or "kenney" (pose images). F2 toggles it on desktop.
Assets.style = "comic"
Assets.comicScale = 0.6 -- sprites are stored at ~2x (88px wide) for sharp high-DPI screens
Assets.comicNames = { "gunner", "shotgunner", "sniper", "bot" }

function Assets.load()
    Assets.tiles = love.graphics.newImage("assets/images/tilesheet.png")
    Assets.tiles:setFilter("nearest", "nearest") -- no bleeding between tiles when scaled
    local W, H = Assets.tiles:getDimensions()

    -- col/row in tile units, w/h in tiles (tilesheet is 27 x 20 tiles of 64px)
    local function quad(col, row, w, h)
        return love.graphics.newQuad(col * TILE, row * TILE,
            (w or 1) * TILE, (h or 1) * TILE, W, H)
    end

    Assets.quads = {
        grass = quad(0, 0),
        wall  = quad(0, 4, 2, 2),   -- 128x128 block with orange outline
        bush  = quad(18, 6, 2, 2),  -- 128x128 green bush
        crate = quad(20, 4),        -- 64x64 wooden crate
    }

    Assets.characters = {}
    for _, name in ipairs(Assets.characterNames) do
        local poses = {}
        for _, pose in ipairs(POSES) do
            poses[pose] = love.graphics.newImage(
                "assets/images/characters/" .. name .. "_" .. pose .. ".png")
        end
        Assets.characters[name] = poses
    end

    Assets.comic = {}
    for _, name in ipairs(Assets.comicNames) do
        local img = love.graphics.newImage("assets/images/comic/" .. name .. ".png",
            { mipmaps = true })
        img:setMipmapFilter("linear") -- smooth when drawn smaller than stored
        Assets.comic[name] = img
    end
end

-- A "look" says how a rowdy definition (src/rowdies.lua) is drawn in the current
-- style. It is plain data (image names, no images), so the simulation can use it
-- without graphics (the muzzle position depends on it):
--   comic : { style = "comic", image, weapon, origin = {x, y}, scale,
--             muzzle = {forward, sideways} in world px }
--   kenney: { style = "kenney", character, weapon }
function Assets.look(def)
    local weapon = def.weapon or "gun"
    if Assets.style == "comic" and def.comic then
        local c, k = def.comic, Assets.comicScale
        return {
            style = "comic", image = c.image, weapon = weapon,
            origin = c.origin, scale = k,
            muzzle = { c.muzzle[1] * k, c.muzzle[2] * k },
        }
    end
    return { style = "kenney", character = def.character, weapon = weapon }
end

-- The rowdy's picture (current style), facing up, fitted into a box of size `box`
-- around (cx, cy); rot tilts it (radians). For menus, not the game.
function Assets.drawPortrait(def, cx, cy, box, rot)
    local look = Assets.look(def)
    local img, angle
    if look.style == "comic" then
        img = Assets.comic[look.image]
        angle = 0
    else
        img = Assets.characters[look.character][look.weapon] or Assets.characters[look.character].gun
        angle = -math.pi / 2 -- Kenney art faces right
    end
    local w, h = img:getDimensions()
    local k = box / math.max(w, h)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(img, cx, cy, angle + (rot or 0), k, k, w / 2, h / 2)
end

return Assets
