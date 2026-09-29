-- Loads all images and defines quads for the Kenney tilesheet.
local Assets = {}

local TILE = 64

-- Each character has these poses (files: assets/images/characters/<name>_<pose>.png)
Assets.characterNames = { "manBlue", "hitman1", "manBrown", "robot1" }
local POSES = { "stand", "hold", "gun", "machine", "silencer", "reload" }

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
end

-- A "look" = which character + which weapon pose to hold ("gun", "machine", "silencer")
function Assets.look(character, weapon)
    return { poses = Assets.characters[character], weapon = weapon or "gun" }
end

return Assets
