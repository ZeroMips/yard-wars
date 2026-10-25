-- Hide and seek drawing (rules: src/world.lua): the picture frame in the middle and the
-- picture pieces (a sunny garden made of shapes, one quarter per piece), a hider
-- disguised as a bush, the hint shimmer, the seeker counting, the seeker's covered
-- screen during the hide phase and the marks on the minimap.
local Assets = require("src.assets")
local Arena  = require("src.arena")

local HideSeek = {}

local SKY   = { 0.55, 0.8, 1 }
local GRASS = { 0.42, 0.75, 0.32 }
local WOOD  = { 0.55, 0.33, 0.15 }
local GOLD  = { 1, 0.82, 0.2 }
local PIECE_W, PIECE_H = 64, 48 -- px: a piece on the ground (the frame's slots are bigger)

-- Quarter k of the picture into the box x, y, w, h (1 top left: the sun, 2 top right:
-- a cloud and a bird, 3 bottom left: a house, 4 bottom right: a tree with flowers)
function HideSeek.drawPart(k, x, y, w, h, a)
    a = a or 1
    local function col(c, k2) love.graphics.setColor(c[1], c[2], c[3], (k2 or 1) * a) end
    if k <= 2 then -- sky with a strip of hills at the bottom
        col(SKY)
        love.graphics.rectangle("fill", x, y, w, h)
        col(GRASS)
        love.graphics.rectangle("fill", x, y + h * 0.75, w, h * 0.25)
        love.graphics.ellipse("fill", x + w * (k == 1 and 0.7 or 0.3), y + h * 0.78, w * 0.45, h * 0.12)
    else
        col(GRASS)
        love.graphics.rectangle("fill", x, y, w, h)
    end
    local cx, cy, s = x + w / 2, y + h / 2, math.min(w, h)
    if k == 1 then -- the sun with rays
        col(GOLD)
        love.graphics.setLineWidth(math.max(1, s * 0.05))
        for i = 0, 7 do
            local ang = i / 8 * math.pi * 2
            love.graphics.line(cx + math.cos(ang) * s * 0.24, cy - s * 0.08 + math.sin(ang) * s * 0.24,
                cx + math.cos(ang) * s * 0.36, cy - s * 0.08 + math.sin(ang) * s * 0.36)
        end
        love.graphics.circle("fill", cx, cy - s * 0.08, s * 0.18)
    elseif k == 2 then -- a cloud and a bird
        col({ 1, 1, 1 })
        for _, c in ipairs({ { -0.18, 0, 0.13 }, { 0, -0.07, 0.17 }, { 0.18, 0, 0.13 } }) do
            love.graphics.circle("fill", cx + c[1] * w, cy - h * 0.12 + c[2] * h, c[3] * s)
        end
        col({ 0.15, 0.15, 0.2 })
        love.graphics.setLineWidth(math.max(1, s * 0.04))
        local bx, by = cx + w * 0.15, cy + h * 0.2
        love.graphics.line(bx - s * 0.1, by - s * 0.05, bx, by, bx + s * 0.1, by - s * 0.05)
    elseif k == 3 then -- a house: wall, roof, door, window
        col({ 0.98, 0.9, 0.7 })
        love.graphics.rectangle("fill", cx - w * 0.25, cy - h * 0.05, w * 0.5, h * 0.4)
        col({ 0.85, 0.25, 0.2 })
        love.graphics.polygon("fill", cx - w * 0.32, cy - h * 0.05, cx, cy - h * 0.38, cx + w * 0.32, cy - h * 0.05)
        col(WOOD)
        love.graphics.rectangle("fill", cx - w * 0.06, cy + h * 0.12, w * 0.12, h * 0.23)
        col(SKY)
        love.graphics.rectangle("fill", cx + w * 0.1, cy + h * 0.02, w * 0.1, h * 0.1)
    else -- a tree and two flowers
        col(WOOD)
        love.graphics.rectangle("fill", cx - w * 0.05, cy, w * 0.1, h * 0.35)
        col({ 0.2, 0.55, 0.2 })
        love.graphics.circle("fill", cx, cy - h * 0.12, s * 0.28)
        love.graphics.circle("fill", cx - s * 0.18, cy, s * 0.18)
        love.graphics.circle("fill", cx + s * 0.18, cy, s * 0.18)
        col({ 1, 0.45, 0.6 })
        love.graphics.circle("fill", x + w * 0.15, y + h * 0.8, s * 0.06)
        col({ 1, 0.9, 0.3 })
        love.graphics.circle("fill", x + w * 0.85, y + h * 0.85, s * 0.06)
    end
    love.graphics.setLineWidth(1)
end

-- A piece as a small framed card, centred on x, y (w x h)
local function card(k, x, y, w, h, a)
    love.graphics.setColor(0, 0, 0, 0.3 * (a or 1))
    love.graphics.rectangle("fill", x - w / 2 - 3, y - h / 2 + 1, w + 6, h + 6, 4, 4)
    love.graphics.setColor(1, 0.97, 0.88, a or 1)
    love.graphics.rectangle("fill", x - w / 2 - 3, y - h / 2 - 3, w + 6, h + 6, 4, 4)
    HideSeek.drawPart(k, x - w / 2, y - h / 2, w, h, a)
end

-- The frame in the middle: a wooden frame with four slots; placed pieces fill theirs,
-- the empty ones show a faint outline. Glows gold once the picture is complete.
-- slot(k) = the centre of slot k (World.pieceSlot). now = world time.
function HideSeek.drawFrame(hide, now, slot)
    local f = Arena.frame
    if not f then return end
    local complete = hide and hide.placed and hide.placed >= #hide.pieces and #hide.pieces > 0
    if complete then
        local k = 0.5 + 0.5 * math.sin(now * 4)
        love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], 0.25 + 0.2 * k)
        love.graphics.rectangle("fill", f.x - 30, f.y - 30, f.w + 60, f.h + 60, 18, 18)
    end
    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.rectangle("fill", f.x - 10, f.y - 4, f.w + 20, f.h + 20, 6, 6)
    love.graphics.setColor(1, 0.97, 0.88, 0.55)
    love.graphics.rectangle("fill", f.x, f.y, f.w, f.h)
    local sw, sh = f.w / 2, f.h / 2
    for k = 1, 4 do
        local cx, cy = slot(k)
        local placed = false
        for _, p in ipairs(hide and hide.pieces or {}) do
            if p.id == k and p.placed then placed = true end
        end
        if placed then
            HideSeek.drawPart(k, cx - sw / 2, cy - sh / 2, sw, sh, 1)
        else
            love.graphics.setColor(0.4, 0.3, 0.2, 0.35)
            love.graphics.setLineWidth(3)
            love.graphics.rectangle("line", cx - sw / 2 + 10, cy - sh / 2 + 10, sw - 20, sh - 20, 6, 6)
            love.graphics.setLineWidth(1)
        end
    end
    love.graphics.setColor(WOOD)
    love.graphics.setLineWidth(14)
    love.graphics.rectangle("line", f.x - 7, f.y - 7, f.w + 14, f.h + 14, 4, 4)
    love.graphics.setColor(0.75, 0.5, 0.25)
    love.graphics.setLineWidth(4)
    love.graphics.rectangle("line", f.x - 7, f.y - 7, f.w + 14, f.h + 14, 4, 4)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

-- A piece lying on the ground: bobs a little, with a gold ring around it
function HideSeek.drawGroundPiece(p, now)
    local bob = math.sin(now * 3 + p.id) * 3
    local k = 0.5 + 0.5 * math.sin(now * 4 + p.id)
    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.ellipse("fill", p.x, p.y + 22, 34, 10)
    love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], 0.35 + 0.35 * k)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", p.x, p.y, 46 + 3 * k)
    love.graphics.setLineWidth(1)
    card(p.id, p.x, p.y - 6 + bob, PIECE_W, PIECE_H)
    love.graphics.setColor(1, 1, 1, 1)
end

-- A carried piece: held up above the carrier's head
function HideSeek.drawCarriedPiece(p, e)
    card(p.id, e.x, e.y - e.radius - 40, PIECE_W * 0.7, PIECE_H * 0.7)
    love.graphics.setColor(1, 1, 1, 1)
end

-- A hider disguised as a bush (smaller than the arena's bush blocks: a careful seeker
-- can spot a bush where none belongs); alpha < 1: the own one, see-through
function HideSeek.drawDisguise(e, alpha)
    local q = Assets.quads.bush
    local _, _, qw, qh = q:getViewport()
    local s = 76 / qw
    love.graphics.setColor(0, 0, 0, 0.2 * alpha)
    love.graphics.ellipse("fill", e.x, e.y + 22, 34, 12)
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(Assets.tiles, q, e.x, e.y, 0, s, s, qw / 2, qh / 2)
    love.graphics.setColor(1, 1, 1, 1)
end

-- A small leaf over a disguised team mate (so the own team knows)
function HideSeek.drawLeaf(e)
    local x, y = e.x + e.radius * 0.8, e.y - e.radius - 6
    love.graphics.setColor(0.3, 0.75, 0.3, 0.95)
    love.graphics.ellipse("fill", x, y, 8, 5)
    love.graphics.setColor(0.15, 0.45, 0.15, 1)
    love.graphics.line(x - 7, y + 2, x + 6, y - 2)
    love.graphics.setColor(1, 1, 1, 1)
end

-- The hint: twinkling stars around a hider (drawn above the bushes, so it shows in one)
function HideSeek.drawShimmer(e, t)
    love.graphics.setBlendMode("add")
    love.graphics.setColor(1, 0.95, 0.6, 0.35)
    love.graphics.circle("fill", e.x, e.y, e.radius + 14 + 4 * math.sin(t * 10))
    love.graphics.setColor(1, 1, 0.8, 0.95)
    love.graphics.setLineWidth(2)
    for i = 1, 6 do
        local a = t * 3 + i / 6 * math.pi * 2
        local r = e.radius + 18 + 6 * math.sin(t * 7 + i)
        local x, y = e.x + math.cos(a) * r, e.y + math.sin(a) * r
        local s = 4 + 2 * math.sin(t * 12 + i * 2)
        love.graphics.line(x - s, y, x + s, y)
        love.graphics.line(x, y - s, x, y + s)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
end

-- The seeker's aim: the area its tag swing reaches (attack = World.TAG)
function HideSeek.drawTagAim(e, attack)
    local r = attack.range + attack.radius
    love.graphics.setColor(1, 0.85, 0.3, 0.18)
    love.graphics.arc("fill", e.x, e.y, r, e.aim - 0.9, e.aim + 0.9, 16)
    love.graphics.setColor(1, 0.85, 0.3, 0.6)
    love.graphics.setLineWidth(2)
    love.graphics.arc("line", e.x, e.y, r, e.aim - 0.9, e.aim + 0.9, 16)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

-- The seeker counting (seen by the hiders): a speech bubble with the seconds left
function HideSeek.drawCounting(e, n, font)
    local text = tostring(n)
    local w, h = math.max(44, font:getWidth(text) + 20), font:getHeight() + 8
    local x, y = e.x - w / 2, e.y - e.radius - 30 - h
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.rectangle("fill", x, y, w, h, 10, 10)
    love.graphics.polygon("fill", e.x - 6, y + h, e.x + 6, y + h, e.x, y + h + 9)
    love.graphics.setColor(0.15, 0.15, 0.2, 1)
    love.graphics.setFont(font)
    love.graphics.printf(text, x, y + 4, w, "center")
    love.graphics.setColor(1, 1, 1, 1)
end

-- The seeker's screen while the hiders hide (HUD units sw x sh): covered, a countdown
function HideSeek.drawCover(fonts, sw, sh, left, t)
    love.graphics.setColor(0.06, 0.2, 0.1, 1)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    love.graphics.setColor(0.1, 0.3, 0.15, 1) -- a few big bush shapes in the background
    for i = 1, 7 do
        local x = (i - 0.5) / 7 * sw
        love.graphics.circle("fill", x, sh + 20, 110 + 30 * math.sin(i * 1.7))
    end
    love.graphics.setFont(fonts.button)
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.printf("You seek! Eyes closed, counting...", 0, sh * 0.28, sw, "center")
    local s = 1 + 0.08 * math.max(0, math.sin((left % 1) * math.pi))
    love.graphics.push()
    love.graphics.translate(sw / 2, sh * 0.47)
    love.graphics.scale(s * 2)
    love.graphics.setFont(fonts.title)
    local fh = fonts.title:getHeight()
    love.graphics.setColor(GOLD)
    love.graphics.printf(tostring(math.max(0, math.ceil(left))), -sw / 2, -fh / 2, sw, "center")
    love.graphics.pop()
    love.graphics.setFont(fonts.text)
    love.graphics.setColor(1, 1, 1, 0.75)
    love.graphics.printf("The hiders hide now. Then find them all: look for bushes where none belong!",
        40, sh * 0.66, sw - 80, "center")
    love.graphics.setColor(1, 1, 1, 1)
end

-- On the minimap (x0, y0 = its corner, s = its scale): the frame and the pieces not
-- placed yet (carried ones too: a carrier is never hidden)
function HideSeek.drawMinimap(hide, x0, y0, s)
    local f = Arena.frame
    if not f then return end
    love.graphics.setColor(WOOD)
    love.graphics.rectangle("fill", x0 + f.x * s, y0 + f.y * s, f.w * s, f.h * s)
    love.graphics.setColor(GOLD)
    love.graphics.rectangle("line", x0 + f.x * s, y0 + f.y * s, f.w * s, f.h * s)
    for _, p in ipairs(hide and hide.pieces or {}) do
        if not p.placed then
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.rectangle("fill", x0 + p.x * s - 4.5, y0 + p.y * s - 3.5, 9, 7)
            love.graphics.setColor(GOLD)
            love.graphics.rectangle("fill", x0 + p.x * s - 3.5, y0 + p.y * s - 2.5, 7, 5)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Mode icon (lobby mode card): a bush with two eyes peeking out
function HideSeek.drawIcon(cx, cy, s)
    love.graphics.setColor(0.25, 0.6, 0.25, 1)
    for _, c in ipairs({ { -0.4, 0.15, 0.38 }, { 0.4, 0.15, 0.38 }, { 0, -0.15, 0.45 } }) do
        love.graphics.circle("fill", cx + c[1] * s, cy + c[2] * s, c[3] * s)
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("fill", cx - s * 0.17, cy - s * 0.05, s * 0.14)
    love.graphics.circle("fill", cx + s * 0.17, cy - s * 0.05, s * 0.14)
    love.graphics.setColor(0.1, 0.1, 0.15, 1)
    love.graphics.circle("fill", cx - s * 0.13, cy - s * 0.03, s * 0.07)
    love.graphics.circle("fill", cx + s * 0.21, cy - s * 0.03, s * 0.07)
    love.graphics.setColor(1, 1, 1, 1)
end

return HideSeek
