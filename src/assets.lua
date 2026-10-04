-- Loads all images and defines quads for the Kenney tilesheet (arena tiles).
-- Rowdy art: one AI-generated still per rowdy (see tools/make_comic_sprites.py), the
-- image names come from src/rowdies.lua.
local Assets = {}

local TILE = 64

Assets.comicScale = 0.6 -- sprites are stored at ~2x (88px wide) for sharp high-DPI screens

local function loadSmooth(path)
    local img = love.graphics.newImage(path, { mipmaps = true })
    img:setMipmapFilter("linear") -- smooth when drawn smaller than stored
    return img
end

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

    -- Every rowdy plus the bot: top view (required) and side view for the lobby
    -- (optional), by comic image name
    local Rowdies = require("src.rowdies")
    local defs = { Rowdies.bot }
    for _, def in ipairs(Rowdies) do defs[#defs + 1] = def end
    Assets.comic, Assets.side = {}, {}
    for _, def in ipairs(defs) do
        local name = def.comic.image
        local top = "assets/images/comic/" .. name .. ".png"
        if not love.filesystem.getInfo(top) then
            error("rowdy " .. def.name .. ": missing " .. top
                .. " - run tools/make_comic_sprites.py", 0)
        end
        Assets.comic[name] = loadSmooth(top)
        local side = "assets/images/side/" .. name .. ".png"
        if love.filesystem.getInfo(side) then Assets.side[name] = loadSmooth(side) end
    end
end

-- A "look" says how a rowdy definition (src/rowdies.lua) is drawn. It is plain data
-- (image name, no images), so the simulation can use it without graphics (the muzzle
-- position depends on it):
--   { image, origin = {x, y} (image px), scale, muzzle = {forward, sideways} in world px }
function Assets.look(def)
    local c, k = def.comic, Assets.comicScale
    return {
        image = c.image, origin = c.origin, scale = k,
        muzzle = { c.muzzle[1] * k, c.muzzle[2] * k },
    }
end

-- The rowdy's picture, facing up, fitted into a box of size `box` around (cx, cy);
-- rot tilts it (radians); tint: color multiplied in (e.g. dark for a locked one).
-- For menus, not the game.
function Assets.drawPortrait(def, cx, cy, box, rot, tint)
    local img = Assets.comic[def.comic.image]
    local w, h = img:getDimensions()
    local k = box / math.max(w, h)
    love.graphics.setColor(tint or { 1, 1, 1 })
    love.graphics.draw(img, cx, cy, rot or 0, k, k, w / 2, h / 2)
    love.graphics.setColor(1, 1, 1)
end

-- The rowdy standing (side view), feet at (cx, footY), `height` tall; sway: tilt
-- (radians) around the feet. Returns false if the rowdy has no side view (then use
-- drawPortrait).
function Assets.drawStanding(def, cx, footY, height, sway, tint)
    local img = Assets.side[def.comic.image]
    if not img then return false end
    local w, h = img:getDimensions()
    local k = height / h
    love.graphics.setColor(tint or { 1, 1, 1 })
    love.graphics.draw(img, cx, footY, sway or 0, k, k, w / 2, h)
    love.graphics.setColor(1, 1, 1)
    return true
end

return Assets
