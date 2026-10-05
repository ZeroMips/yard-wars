-- Style screen: put on the Yard Pass cosmetics (src/cosmetics.lua) - a skin for the
-- shown rowdy, the bullet trail, the lobby pedestal, badge and title. Things not won
-- yet are shown dark with a lock ("Yard Pass"). Opened from the lobby (STYLE) and from
-- the rowdy cards (Skins). Mouse/touch: tap a chip; keyboard: left/right switch the
-- rowdy, Esc back.
-- Laid out in HUD units (720 along the short screen side), like the menu.
local Assets    = require("src.assets")
local Cosmetics = require("src.cosmetics")
local Decor     = require("src.decor")
local Loot      = require("src.loot")
local Pass      = require("src.pass")
local Rowdies   = require("src.rowdies")

local Wardrobe = {}

Wardrobe.rowdy = 1      -- index into Rowdies (whose skins are shown)
Wardrobe.message = nil

local CHIP_W, CHIP_H, GAP = 124, 84, 10
local SECTIONS = {
    { kind = "skin", label = "SKIN", none = "Default" },
    { kind = "trail", label = "BULLET TRAIL", none = "None" },
    { kind = "pedestal", label = "PEDESTAL", none = "Default" },
    { kind = "badge", label = "BADGE", none = "None" },
    { kind = "title", label = "TITLE", none = "None" },
}

local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end
local function inside(r, x, y) return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

local function equipped(kind)
    if kind == "skin" then return Pass.skinFor(Rowdies[Wardrobe.rowdy]) end
    return Pass.equippedId(kind)
end

local function layout()
    local ui = uiScale()
    local sw, sh = love.graphics.getWidth() / ui, love.graphics.getHeight() / ui
    local L = { sw = sw, sh = sh, portrait = sw < sh * 1.2, chips = {} }
    local x0, y
    if L.portrait then
        L.preview = { x = 0, y = 70, w = sw, h = 330 }
        x0, y = 24, 410
    else
        L.preview = { x = 0, y = 70, w = sw * 0.36, h = sh - 170 }
        x0, y = sw * 0.36 + 10, 76
    end
    local maxX = sw - 24
    L.heads = {}
    for _, sec in ipairs(SECTIONS) do
        L.heads[#L.heads + 1] = { text = sec.label, x = x0, y = y }
        y = y + 24
        local x = x0
        local ids = { false }
        local list = sec.kind == "skin" and Cosmetics.skinsOf(Rowdies[Wardrobe.rowdy].name)
            or Cosmetics.ofKind(sec.kind)
        for _, c in ipairs(list) do ids[#ids + 1] = c.id end
        for _, id in ipairs(ids) do
            if x + CHIP_W > maxX then x, y = x0, y + CHIP_H + GAP end
            L.chips[#L.chips + 1] = { x = x, y = y, w = CHIP_W, h = CHIP_H, kind = sec.kind, id = id,
                none = sec.none }
            x = x + CHIP_W + GAP
        end
        y = y + CHIP_H + 12
    end
    local px = L.preview.x + L.preview.w / 2
    L.prev = { x = px - 150, y = L.preview.y + L.preview.h * 0.42 - 24, w = 48, h = 48 }
    L.next = { x = px + 102, y = L.prev.y, w = 48, h = 48 }
    if L.portrait then
        L.back = { x = (sw - 220) / 2, y = math.max(y + 4, sh - 84), w = 220, h = 64 }
    else -- under the preview
        L.back = { x = L.preview.x + (L.preview.w - 220) / 2, y = sh - 84, w = 220, h = 64 }
    end
    return L
end

function Wardrobe.open(rowdyIndex)
    Wardrobe.rowdy = rowdyIndex or Wardrobe.rowdy
    Wardrobe.message = nil
end

-- Screen position -> "chip" + chip, "prev", "next", "back" or nil
function Wardrobe.hit(x, y)
    local ui = uiScale()
    x, y = x / ui, y / ui
    local L = layout()
    for _, name in ipairs({ "back", "prev", "next" }) do
        if inside(L[name], x, y) then return name end
    end
    for _, c in ipairs(L.chips) do
        if inside(c, x, y) then return "chip", c end
    end
end

-- Put on what a chip shows. Returns true if it changed something.
function Wardrobe.choose(chip)
    if chip.id and not Pass.owns(chip.id) then
        Wardrobe.message = "Win it in the Yard Pass"
        return false
    end
    Wardrobe.message = nil
    if equipped(chip.kind) == (chip.id or nil) then return false end
    if chip.kind == "skin" then Pass.setSkin(Rowdies[Wardrobe.rowdy], chip.id or nil)
    else Pass.equip(chip.kind, chip.id or nil) end
    return true
end

function Wardrobe.switch(dir)
    Wardrobe.rowdy = (Wardrobe.rowdy - 1 + dir) % #Rowdies + 1
    Wardrobe.message = nil
end

-- Keyboard: returns "back" or nil (switching is done here)
function Wardrobe.keypressed(key)
    if key == "left" or key == "a" then Wardrobe.switch(-1)
    elseif key == "right" or key == "d" then Wardrobe.switch(1)
    elseif key == "escape" or key == "return" or key == "kpenter" then return "back" end
end

local function drawChip(c, fonts, def)
    local owned = not c.id or Pass.owns(c.id)
    local on = equipped(c.kind) == (c.id or nil)
    love.graphics.setColor(0.08, 0.1, 0.14, 0.92)
    love.graphics.rectangle("fill", c.x, c.y, c.w, c.h, 10, 10)
    local cx, cy = c.x + c.w / 2, c.y + 32
    if not c.id then
        if c.kind == "skin" then Assets.drawPortrait(def, cx, cy, 52)
        elseif c.kind == "pedestal" then
            love.graphics.setColor(0.2, 0.25, 0.35)
            love.graphics.ellipse("fill", cx, cy + 6, 40, 12)
            love.graphics.setColor(1, 0.8, 0.3, 0.7)
            love.graphics.ellipse("line", cx, cy + 6, 40, 12)
        else
            love.graphics.setColor(1, 1, 1, 0.4)
            love.graphics.setLineWidth(3)
            love.graphics.circle("line", cx, cy, 16)
            love.graphics.line(cx - 11, cy + 11, cx + 11, cy - 11)
            love.graphics.setLineWidth(1)
        end
    else
        Decor.drawReward({ cosmetic = c.id }, cx, cy, 58, fonts.text, not owned)
        if not owned then Loot.drawLock(c.x + c.w - 16, c.y + 16, 0.25) end
    end
    love.graphics.setFont(fonts.text)
    love.graphics.setColor(1, 1, 1, owned and 0.95 or 0.5)
    local name = c.id and Cosmetics.get(c.id).name or c.none
    love.graphics.printf(name, c.x + 4, c.y + c.h - 24, c.w - 8, "center")
    if on then
        love.graphics.setColor(1, 0.6, 0.2)
        love.graphics.setLineWidth(4)
        love.graphics.rectangle("line", c.x, c.y, c.w, c.h, 10, 10)
        love.graphics.setLineWidth(1)
    else
        love.graphics.setColor(1, 1, 1, 0.2)
        love.graphics.rectangle("line", c.x, c.y, c.w, c.h, 10, 10)
    end
end

-- fonts = { title, button, text }
function Wardrobe.draw(fonts)
    local L = layout()
    local ui = uiScale()
    local t = love.timer.getTime()
    local def = Rowdies[Wardrobe.rowdy]
    love.graphics.push()
    love.graphics.scale(ui)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, L.sw, L.sh)
    love.graphics.setFont(fonts.button)
    love.graphics.setColor(1, 0.8, 0.2)
    love.graphics.printf("STYLE", 0, 20, L.sw, "center")

    -- preview: the rowdy on its pedestal with skin, badge and title
    local p = L.preview
    local cx = p.x + p.w / 2
    local k = math.min(0.85, p.h / 520)
    local py = p.y + p.h * 0.42 + 120 * k
    if not Decor.drawPedestal(Pass.equippedId("pedestal"), cx, py, k, t) then
        love.graphics.setColor(0.2, 0.25, 0.35)
        love.graphics.ellipse("fill", cx, py, 156 * k, 42 * k)
        love.graphics.setColor(1, 0.8, 0.3, 0.7)
        love.graphics.setLineWidth(4)
        love.graphics.ellipse("line", cx, py, 156 * k, 42 * k)
        love.graphics.setLineWidth(1)
    end
    local skin = Pass.skinFor(def)
    if not Assets.drawStanding(def, cx, py + 6 * k, 290 * k, math.sin(t * 1.3) * 0.02, nil, skin) then
        Assets.drawPortrait(def, cx, py - 140 * k, 240 * k, 0, nil, skin)
    end
    love.graphics.setFont(fonts.button)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(def.name:upper(), p.x, p.y + 4, p.w, "center")
    local badge = Pass.equippedId("badge")
    if badge then Decor.drawBadge(badge, cx - fonts.button:getWidth(def.name:upper()) / 2 - 22, p.y + 18, 13) end
    local title = Pass.equippedId("title")
    if title then Decor.drawTitle(title, fonts.text, cx, py + 70 * k) end
    for _, name in ipairs({ "prev", "next" }) do
        local r = L[name]
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.circle("fill", r.x + r.w / 2, r.y + r.h / 2, 22)
        love.graphics.setColor(0.1, 0.1, 0.15)
        local d = name == "next" and 1 or -1
        local x, y = r.x + r.w / 2, r.y + r.h / 2
        love.graphics.polygon("fill", x + 9 * d, y, x - 6 * d, y - 11, x - 6 * d, y + 11)
    end

    love.graphics.setFont(fonts.text)
    for _, h in ipairs(L.heads) do
        love.graphics.setColor(1, 0.82, 0.3)
        love.graphics.print(h.text, h.x, h.y)
    end
    for _, c in ipairs(L.chips) do drawChip(c, fonts, def) end

    if Wardrobe.message then
        love.graphics.setFont(fonts.text)
        love.graphics.setColor(1, 0.85, 0.4)
        love.graphics.printf(Wardrobe.message, 0, 50, L.sw, "center")
    end

    local b = L.back
    love.graphics.setColor(0.05, 0.05, 0.1, 0.9)
    love.graphics.rectangle("fill", b.x - 2, b.y - 2, b.w + 4, b.h + 6, 12, 12)
    love.graphics.setColor(0.35, 0.37, 0.42)
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h - 4, 10, 10)
    love.graphics.setFont(fonts.button)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Back", b.x, b.y + (b.h - 4 - fonts.button:getHeight()) / 2, b.w, "center")

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

return Wardrobe
