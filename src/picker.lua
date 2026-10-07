-- Rowdy choice screen: a scrolling grid of cards (picture, role, HP, attack, super)
-- plus a confirm and a Back button. Mouse (wheel scrolls), touch (tap a card, then the
-- button; drag scrolls) and keyboard (arrows, Enter, Esc).
-- Rowdies not bought yet (src/profile.lua) are dark with a lock and their price; the
-- confirm button then says "Unlock" (main.lua buys it). A pass rowdy (src/rowdies.lua
-- `pass`) shows its Yard Pass tier instead, and the button says "Yard Pass". A rowdy with Yard Pass skins
-- (src/cosmetics.lua) has a "Skins" button on its card (opens src/wardrobe.lua).
-- Laid out in HUD units (720 along the short screen side), like the menu.
local Assets   = require("src.assets")
local Rowdies = require("src.rowdies")
local Loot     = require("src.loot")
local Profile  = require("src.profile")
local Pass     = require("src.pass")
local Cosmetics = require("src.cosmetics")
local Seasons  = require("src.seasons")

local Picker = {}

Picker.selected = 1
Picker.confirmLabel = "Play" -- e.g. "Next" before the join screen
Picker.message = nil         -- shown under the title (e.g. "Gunner unlocked!")

-- The selected rowdy isn't bought yet
function Picker.locked()
    return not Profile.isUnlocked(Rowdies[Picker.selected])
end

-- Cards have a fixed size and fill a grid (as many columns as fit) that scrolls
-- between the title and the buttons (mouse wheel, touch drag, keyboard)
local CARD_W, CARD_H, GAP = 210, 310, 16
local TOP = 100         -- top of the card area
local PAD = 8           -- room above/below the cards for the selection outline
local DRAG_SLOP = 12    -- a touch that moved more than this scrolls instead of tapping

Picker.scroll = 0       -- HUD units the cards are scrolled up
Picker.dragged = false  -- the current touch scrolled (main.lua then ignores its release)
local dragDist = 0

local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end

local function layout()
    local ui = uiScale()
    local sw, sh = love.graphics.getWidth() / ui, love.graphics.getHeight() / ui
    local n = #Rowdies
    local cols = math.max(1, math.min(n, math.floor((sw - 40 + GAP) / (CARD_W + GAP))))
    local rows = math.ceil(n / cols)
    local x0 = (sw - (cols * CARD_W + (cols - 1) * GAP)) / 2
    local by = sh - 90
    local view = { y = TOP, h = by - 16 - TOP }
    local contentH = rows * (CARD_H + GAP) - GAP + 2 * PAD
    local maxScroll = math.max(0, contentH - view.h)
    Picker.scroll = math.max(0, math.min(maxScroll, Picker.scroll))
    local cards = {}
    for i = 1, n do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        cards[i] = { x = x0 + col * (CARD_W + GAP),
                     y = TOP + PAD + row * (CARD_H + GAP) - Picker.scroll,
                     w = CARD_W, h = CARD_H }
    end
    local bw = math.min(220, (sw - 60) / 2)
    return {
        cards = cards, cols = cols, view = view,
        confirm = { x = sw / 2 - bw - 10, y = by, w = bw, h = 64 },
        back    = { x = sw / 2 + 10, y = by, w = bw, h = 64 },
    }, sw, sh
end

-- Scroll until the selected card is fully visible (call after the selection changed
-- or the picker was opened)
function Picker.reveal()
    local rects = layout()
    local r, v = rects.cards[Picker.selected], rects.view
    if not r then return end
    if r.y - PAD < v.y then
        Picker.scroll = Picker.scroll - (v.y - (r.y - PAD))
    elseif r.y + r.h + PAD > v.y + v.h then
        Picker.scroll = Picker.scroll + (r.y + r.h + PAD) - (v.y + v.h)
    end
    layout() -- clamp
end

-- Mouse wheel (dy > 0: up)
function Picker.wheel(dy)
    Picker.scroll = Picker.scroll - dy * 60
    layout()
end

-- Touch: touchStart on press, drag with the movement (screen px)
function Picker.touchStart()
    Picker.dragged, dragDist = false, 0
end

function Picker.drag(dy)
    dy = dy / uiScale()
    dragDist = dragDist + math.abs(dy)
    if dragDist > DRAG_SLOP then Picker.dragged = true end
    Picker.scroll = Picker.scroll - dy
    layout()
end

-- The "Skins" button on a card (only for rowdies that have skins)
local function skinsRect(r, def)
    if #Cosmetics.skinsOf(def.name) == 0 then return nil end
    return { x = r.x + r.w - 70, y = r.y + 8, w = 62, h = 28 }
end

-- Screen position -> "card" + index, "skins" + index, "confirm", "back" or nil
function Picker.hit(x, y)
    local ui = uiScale()
    x, y = x / ui, y / ui
    local function inside(r) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end
    local rects = layout()
    if inside(rects.confirm) then return "confirm" end
    if inside(rects.back) then return "back" end
    if y < rects.view.y or y > rects.view.y + rects.view.h then return end
    for i, r in ipairs(rects.cards) do
        local sk = skinsRect(r, Rowdies[i])
        if sk and inside(sk) then return "skins", i end
        if inside(r) then return "card", i end
    end
end

-- Returns "confirm", "back" or nil
function Picker.keypressed(key)
    local n, before = #Rowdies, Picker.selected
    local cols = layout().cols
    if key == "left" or key == "a" then
        Picker.selected = (Picker.selected - 2) % n + 1
    elseif key == "right" or key == "d" then
        Picker.selected = Picker.selected % n + 1
    elseif key == "up" or key == "w" then
        if Picker.selected > cols then Picker.selected = Picker.selected - cols end
    elseif key == "down" or key == "s" then
        Picker.selected = math.min(n, Picker.selected + cols)
    elseif key == "return" or key == "kpenter" or key == "space" then
        return "confirm"
    elseif key == "escape" then
        return "back"
    end
    if Picker.selected ~= before then Picker.reveal() end
end

local function attackText(stats)
    local n = stats.pellets or 1
    local dmg = (n > 1) and (n .. " x " .. stats.damage) or tostring(stats.damage)
    if stats.lob then return dmg .. " dmg bomb, range " .. stats.range end
    return dmg .. " dmg, range " .. stats.range
end

function Picker.draw(fonts, title)
    local rects, sw, sh = layout()
    local ui = uiScale()
    love.graphics.push()
    love.graphics.scale(ui)

    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    love.graphics.setFont(fonts.button)
    love.graphics.setColor(1, 0.8, 0.2)
    love.graphics.printf(title or "Choose your rowdy", 0, 30, sw, "center")
    Loot.drawCounter(Profile.coins, fonts.text, sw - 140, 50, 36)
    if Picker.message then
        love.graphics.setFont(fonts.text)
        love.graphics.setColor(1, 0.9, 0.5)
        love.graphics.printf(Picker.message, 0, 68, sw, "center")
    end

    local v = rects.view
    love.graphics.setScissor(0, math.floor(v.y * ui), love.graphics.getWidth(), math.ceil(v.h * ui))
    for i, r in ipairs(rects.cards) do
        if r.y + r.h >= v.y and r.y <= v.y + v.h then -- (partly) in view
            local def, selected = Rowdies[i], (i == Picker.selected)
            love.graphics.setColor(0.1, 0.12, 0.15, 0.92)
            love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 12, 12)
            if selected then love.graphics.setColor(1, 0.6, 0.2) else love.graphics.setColor(1, 1, 1, 0.3) end
            love.graphics.setLineWidth(selected and 4 or 2)
            love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 12, 12)
            love.graphics.setLineWidth(1)

            local locked = not Profile.isUnlocked(def)
            Assets.drawPortrait(def, r.x + r.w / 2, r.y + 70, 104, 0,
                locked and { 0.12, 0.12, 0.18 } or nil, Pass.skinFor(def))
            local sk = skinsRect(r, def)
            if sk then
                love.graphics.setColor(0.85, 0.4, 0.55)
                love.graphics.rectangle("fill", sk.x, sk.y, sk.w, sk.h, 8, 8)
                love.graphics.setFont(fonts.text)
                love.graphics.setColor(1, 1, 1)
                love.graphics.printf("Skins", sk.x, sk.y + (sk.h - fonts.text:getHeight()) / 2, sk.w, "center")
            end
            if locked then
                Loot.drawLock(r.x + r.w / 2, r.y + 62, 0.7)
            end
            if locked and def.pass then
                local _, tier = Seasons.rowdyTier(def.name)
                love.graphics.setFont(fonts.text)
                love.graphics.setColor(0.8, 0.6, 1)
                love.graphics.printf("Yard Pass tier " .. tier, r.x, r.y + 110 - fonts.text:getHeight() / 2,
                    r.w, "center")
            elseif locked then
                local price = tostring(def.price)
                love.graphics.setFont(fonts.button)
                local w = 28 + fonts.button:getWidth(price)
                local x = r.x + (r.w - w) / 2
                Loot.drawCoin(x + 10, r.y + 110, 10)
                love.graphics.setColor(Profile.canAfford(def) and { 1, 0.88, 0.35 } or { 1, 0.6, 0.55 })
                love.graphics.print(price, x + 28, r.y + 110 - fonts.button:getHeight() / 2)
            end

            love.graphics.setFont(fonts.button)
            love.graphics.setColor(1, 1, 1)
            love.graphics.printf(def.name, r.x, r.y + 128, r.w, "center")
            love.graphics.setFont(fonts.text)
            love.graphics.setColor(1, 0.8, 0.45, 0.9)
            love.graphics.printf(def.role or "", r.x, r.y + 160, r.w, "center")

            local st = def.stats
            love.graphics.setColor(1, 1, 1, 0.8)
            love.graphics.printf("HP " .. st.hp, r.x + 8, r.y + 188, r.w - 16, "center")
            love.graphics.printf(attackText(st), r.x + 8, r.y + 210, r.w - 16, "center")
            if st.super then
                love.graphics.setColor(1, 0.82, 0.1)
                love.graphics.printf("Super: " .. st.super.name, r.x + 8, r.y + 238, r.w - 16, "center")
                love.graphics.setColor(1, 1, 1, 0.6)
                love.graphics.printf(st.super.description or "", r.x + 8, r.y + 260, r.w - 16, "center")
            end
        end
    end
    love.graphics.setScissor()

    for _, name in ipairs({ "confirm", "back" }) do
        local r = rects[name]
        love.graphics.setColor(0.1, 0.12, 0.15, 0.92)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 10, 10)
        if name == "confirm" then love.graphics.setColor(1, 0.6, 0.2) else love.graphics.setColor(1, 1, 1, 0.5) end
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 10, 10)
        love.graphics.setLineWidth(1)
        love.graphics.setFont(fonts.button)
        love.graphics.setColor(1, 1, 1)
        local label = (name == "confirm") and Picker.confirmLabel or "Back"
        if name == "confirm" and Picker.locked() then
            label = Rowdies[Picker.selected].pass and "Yard Pass" or "Unlock"
        end
        love.graphics.printf(label, r.x, r.y + 16, r.w, "center")
    end

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

return Picker
