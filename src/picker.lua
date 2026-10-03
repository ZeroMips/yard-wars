-- Rowdy choice screen: one card per rowdy (picture, role, HP, attack, super)
-- plus a confirm and a Back button. Mouse, touch (tap a card, then the button) and
-- keyboard (left/right, Enter, Esc).
-- Rowdies not bought yet (src/profile.lua) are dark with a lock and their price; the
-- confirm button then says "Unlock" (main.lua buys it).
-- Laid out in HUD units (720 along the short screen side), like the menu.
local Assets   = require("src.assets")
local Rowdies = require("src.rowdies")
local Loot     = require("src.loot")
local Profile  = require("src.profile")

local Picker = {}

Picker.selected = 1
Picker.confirmLabel = "Play" -- e.g. "Next" before the join screen
Picker.message = nil         -- shown under the title (e.g. "Gunner unlocked!")

-- The selected rowdy isn't bought yet
function Picker.locked()
    return not Profile.isUnlocked(Rowdies[Picker.selected])
end

local CARD_H, GAP = 330, 16

local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end

local function layout()
    local ui = uiScale()
    local sw = love.graphics.getWidth() / ui
    local n = #Rowdies
    local cw = math.min(250, (sw - 40 - (n - 1) * GAP) / n)
    local x0 = (sw - (n * cw + (n - 1) * GAP)) / 2
    local cards = {}
    for i = 1, n do cards[i] = { x = x0 + (i - 1) * (cw + GAP), y = 100, w = cw, h = CARD_H } end
    local bw = math.min(220, (sw - 60) / 2)
    return {
        cards = cards,
        confirm = { x = sw / 2 - bw - 10, y = 100 + CARD_H + 24, w = bw, h = 64 },
        back    = { x = sw / 2 + 10, y = 100 + CARD_H + 24, w = bw, h = 64 },
    }, sw
end

-- Screen position -> "card" + index, "confirm", "back" or nil
function Picker.hit(x, y)
    local ui = uiScale()
    x, y = x / ui, y / ui
    local function inside(r) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end
    local rects = layout()
    for i, r in ipairs(rects.cards) do
        if inside(r) then return "card", i end
    end
    if inside(rects.confirm) then return "confirm" end
    if inside(rects.back) then return "back" end
end

-- Returns "confirm", "back" or nil
function Picker.keypressed(key)
    if key == "left" or key == "a" then
        Picker.selected = (Picker.selected - 2) % #Rowdies + 1
    elseif key == "right" or key == "d" then
        Picker.selected = Picker.selected % #Rowdies + 1
    elseif key == "return" or key == "kpenter" or key == "space" then
        return "confirm"
    elseif key == "escape" then
        return "back"
    end
end

local function attackText(stats)
    local n = stats.pellets or 1
    local dmg = (n > 1) and (n .. " x " .. stats.damage) or tostring(stats.damage)
    return "Attack: " .. dmg .. " dmg, range " .. stats.range
end

function Picker.draw(fonts, title)
    local rects, sw = layout()
    local ui = uiScale()
    local sh = love.graphics.getHeight() / ui
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

    for i, r in ipairs(rects.cards) do
        local def, selected = Rowdies[i], (i == Picker.selected)
        love.graphics.setColor(0.1, 0.12, 0.15, 0.92)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 12, 12)
        if selected then love.graphics.setColor(1, 0.6, 0.2) else love.graphics.setColor(1, 1, 1, 0.3) end
        love.graphics.setLineWidth(selected and 4 or 2)
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 12, 12)
        love.graphics.setLineWidth(1)

        local locked = not Profile.isUnlocked(def)
        Assets.drawPortrait(def, r.x + r.w / 2, r.y + 78, 110, 0,
            locked and { 0.12, 0.12, 0.18 } or nil)
        if locked then
            Loot.drawLock(r.x + r.w / 2, r.y + 70, 0.7)
            local price = tostring(def.price)
            love.graphics.setFont(fonts.button)
            local w = 28 + fonts.button:getWidth(price)
            local x = r.x + (r.w - w) / 2
            Loot.drawCoin(x + 10, r.y + 120, 10)
            love.graphics.setColor(Profile.canAfford(def) and { 1, 0.88, 0.35 } or { 1, 0.6, 0.55 })
            love.graphics.print(price, x + 28, r.y + 120 - fonts.button:getHeight() / 2)
        end

        love.graphics.setFont(fonts.button)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(def.name, r.x, r.y + 142, r.w, "center")
        love.graphics.setFont(fonts.text)
        love.graphics.setColor(1, 0.8, 0.45, 0.9)
        love.graphics.printf(def.role or "", r.x, r.y + 176, r.w, "center")

        local st = def.stats
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.printf("HP " .. st.hp .. "\n" .. attackText(st), r.x + 8, r.y + 204, r.w - 16, "center")
        if st.super then
            love.graphics.setColor(1, 0.82, 0.1)
            love.graphics.printf("Super: " .. st.super.name, r.x + 8, r.y + 262, r.w - 16, "center")
            love.graphics.setColor(1, 1, 1, 0.6)
            love.graphics.printf(st.super.description or "", r.x + 8, r.y + 284, r.w - 16, "center")
        end
    end

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
        if name == "confirm" and Picker.locked() then label = "Unlock" end
        love.graphics.printf(label, r.x, r.y + 16, r.w, "center")
    end

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

return Picker
