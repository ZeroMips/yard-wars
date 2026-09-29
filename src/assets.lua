-- Loads all images and defines quads for the Kenney tilesheet.
local Assets = {}

local TILE = 64

-- Each character has these poses (files: assets/images/characters/<name>_<pose>.png)
Assets.characterNames = { "manBlue", "hitman1", "manBrown", "robot1" }
local POSES = { "stand", "hold", "gun", "machine", "silencer", "reload" }

-- Art style: "comic" (one AI-generated still per character, see tools/make_comic_sprites.py)
-- or "kenney" (pose images). F2 toggles it on desktop.
Assets.style = "comic"
Assets.comicScale = 0.5 -- comic sprites are stored at 2x for sharp high-DPI screens
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

-- A "look" = which character + which weapon pose to hold ("gun", "machine", "silencer").
-- With style "comic" and a `comic` entry (see src/rowdies.lua) it is a single sprite:
--   { sprite = img, origin = {x, y}, scale, muzzle = {forward, sideways} in world px }
function Assets.look(character, weapon, comic)
    if Assets.style == "comic" and comic then
        local k = Assets.comicScale
        return {
            sprite = Assets.comic[comic.image], weapon = weapon or "gun",
            origin = comic.origin, scale = k,
            muzzle = { comic.muzzle[1] * k, comic.muzzle[2] * k },
        }
    end
    return { poses = Assets.characters[character], weapon = weapon or "gun" }
end

return Assets
