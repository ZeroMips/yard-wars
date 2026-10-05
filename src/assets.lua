-- Loads all images and defines quads for the Kenney tilesheet (arena tiles).
-- Rowdy art: one AI-generated still per rowdy (see tools/make_comic_sprites.py), the
-- image names come from src/rowdies.lua (skins with their own art: src/cosmetics.lua).
local Cosmetics = require("src.cosmetics")

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
    local function loadRowdy(name, who)
        local top = "assets/images/comic/" .. name .. ".png"
        if not love.filesystem.getInfo(top) then
            error(who .. ": missing " .. top .. " - run tools/make_comic_sprites.py", 0)
        end
        Assets.comic[name] = loadSmooth(top)
        local side = "assets/images/side/" .. name .. ".png"
        if love.filesystem.getInfo(side) then Assets.side[name] = loadSmooth(side) end
    end
    for _, def in ipairs(defs) do loadRowdy(def.comic.image, "rowdy " .. def.name) end
    for _, c in ipairs(Cosmetics.ofKind("skin")) do
        if c.image then loadRowdy(c.image, "skin " .. c.id) end
    end
end

-- Skins with a colour change (src/cosmetics.lua: hue/sat/bright) are drawn through
-- this shader: it turns the hue of coloured pixels; grey/black (outlines) and skin
-- tones stay as they are; tint colours the grey parts.
local HUE_SHADER = [[
extern float hue;
extern float sat;
extern float bright;
extern vec3 tint;

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 px = Texel(tex, tc);
    vec3 hsv = rgb2hsv(px.rgb);
    float skinTone = (1.0 - smoothstep(0.08, 0.13, hsv.x)) * (1.0 - smoothstep(0.55, 0.7, hsv.y))
        * smoothstep(0.35, 0.5, hsv.z);
    float amount = smoothstep(0.12, 0.3, hsv.y) * (1.0 - skinTone);
    vec3 shifted = hsv2rgb(vec3(fract(hsv.x + hue), clamp(hsv.y * sat, 0.0, 1.0),
        clamp(hsv.z * bright, 0.0, 1.0)));
    float grey = 1.0 - smoothstep(0.12, 0.3, hsv.y);
    vec3 rgb = mix(px.rgb, shifted, amount);
    rgb = mix(rgb, min(rgb * tint * 1.1, vec3(1.0)), grey);
    return vec4(rgb, px.a) * color;
}
]]
local hueShader

-- Set the colour-change shader for a look or skin entry with a hue (nothing otherwise).
-- Returns true if it was set: then call love.graphics.setShader() after drawing.
function Assets.beginSkin(look)
    if not (look and (look.hue or look.tint)) then return false end
    hueShader = hueShader or love.graphics.newShader(HUE_SHADER)
    hueShader:send("hue", look.hue or 0)
    hueShader:send("tint", look.tint or { 1 / 1.1, 1 / 1.1, 1 / 1.1 })
    hueShader:send("sat", look.sat or 1)
    hueShader:send("bright", look.bright or 1)
    love.graphics.setShader(hueShader)
    return true
end

-- A "look" says how a rowdy definition (src/rowdies.lua) is drawn. It is plain data
-- (image name, no images), so the simulation can use it without graphics (the muzzle
-- position depends on it):
--   { image, origin = {x, y} (image px), scale, muzzle = {forward, sideways} in world px,
--     skin = cosmetic id or nil, hue/sat/bright/tint (colour-change skins) }
-- skin: id of a skin (src/cosmetics.lua); unknown ids or another rowdy's skin = default
function Assets.look(def, skin)
    local c, k = def.comic, Assets.comicScale
    local s = Cosmetics.skinFor(def, skin)
    return {
        image = s and s.image or c.image, origin = c.origin, scale = k,
        muzzle = { c.muzzle[1] * k, c.muzzle[2] * k },
        skin = s and s.id, hue = s and s.hue, sat = s and s.sat, bright = s and s.bright,
        tint = s and s.tint,
    }
end

-- The rowdy's picture, facing up, fitted into a box of size `box` around (cx, cy);
-- rot tilts it (radians); tint: color multiplied in (e.g. dark for a locked one);
-- skin: skin id (nil = default). For menus, not the game.
function Assets.drawPortrait(def, cx, cy, box, rot, tint, skin)
    local s = Cosmetics.skinFor(def, skin)
    local img = Assets.comic[s and s.image or def.comic.image]
    local w, h = img:getDimensions()
    local k = box / math.max(w, h)
    love.graphics.setColor(tint or { 1, 1, 1 })
    local shaded = Assets.beginSkin(s)
    love.graphics.draw(img, cx, cy, rot or 0, k, k, w / 2, h / 2)
    if shaded then love.graphics.setShader() end
    love.graphics.setColor(1, 1, 1)
end

-- The rowdy standing (side view), feet at (cx, footY), `height` tall; sway: tilt
-- (radians) around the feet. Returns false if the rowdy has no side view (then use
-- drawPortrait). skin: skin id (nil = default).
function Assets.drawStanding(def, cx, footY, height, sway, tint, skin)
    local s = Cosmetics.skinFor(def, skin)
    local img = Assets.side[s and s.image or def.comic.image]
    if not img then return false end
    local w, h = img:getDimensions()
    local k = height / h
    love.graphics.setColor(tint or { 1, 1, 1 })
    local shaded = Assets.beginSkin(s)
    love.graphics.draw(img, cx, footY, sway or 0, k, k, w / 2, h)
    if shaded then love.graphics.setShader() end
    love.graphics.setColor(1, 1, 1)
    return true
end

return Assets
