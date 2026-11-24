-- The waiting room of a LAN game: everybody who wants to play together arrives here
-- before the round starts. Shows who is there (nick + rowdy), the host's START button
-- (everybody else waits for it), ROWDY (change the own rowdy) and LEAVE.
-- Laid out in HUD units (720 along the short screen side), like the menu.
local Rowdies = require("src.rowdies")
local Assets  = require("src.assets")

local Waiting = {}

local CARD_W, CARD_H, GAP = 140, 210, 12
local BUTTON_H = 70
local CHIP_W, CHIP_H, MAX_CHIP_ROWS = 150, 36, 2
Waiting.INVITE_QUIET = 30 -- seconds a chip stays "invited" before it can be tapped again

local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end

local function layout(info)
    local ui = uiScale()
    local sw, sh = love.graphics.getWidth() / ui, love.graphics.getHeight() / ui
    local L = { sw = sw, sh = sh, cards = {}, buttons = {} }
    -- cards: as many per row as fit, centred; rows from the top of the list area
    local n = #(info.players or {})
    local perRow = math.max(1, math.min(n > 0 and n or 1, math.floor((sw - 24 + GAP) / (CARD_W + GAP))))
    local top = 150
    local rows = math.ceil(math.max(n, 1) / perRow)
    -- the host also has the list of friends nearby (invite chips) above the buttons
    local nearby = info.host and info.nearby or {}
    local perChipRow = math.max(1, math.floor((sw - 24 + 10) / (CHIP_W + 10)))
    local chipRows = info.host and math.min(MAX_CHIP_ROWS, math.max(1, math.ceil(#nearby / perChipRow))) or 0
    local chipsH = info.host and (26 + chipRows * (CHIP_H + 8)) or 0
    local ch = math.min(CARD_H, math.floor((sh - top - BUTTON_H - 60 - chipsH - (rows - 1) * GAP) / rows))
    L.cardH = math.max(120, ch)
    for i = 1, n do
        local row, col = math.floor((i - 1) / perRow), (i - 1) % perRow
        local inRow = math.min(perRow, n - row * perRow)
        local x0 = (sw - (inRow * CARD_W + (inRow - 1) * GAP)) / 2
        L.cards[i] = { x = x0 + col * (CARD_W + GAP), y = top + row * (L.cardH + GAP), w = CARD_W, h = L.cardH }
    end
    -- invite chips: right above the buttons
    L.chips, L.chipLabelY = {}, sh - 24 - BUTTON_H - 12 - chipsH + 4
    for i = 1, math.min(#nearby, chipRows * perChipRow) do
        local row, col = math.floor((i - 1) / perChipRow), (i - 1) % perChipRow
        local inRow = math.min(perChipRow, #nearby - row * perChipRow)
        local x0 = (sw - (inRow * CHIP_W + (inRow - 1) * 10)) / 2
        L.chips[i] = { x = x0 + col * (CHIP_W + 10), y = L.chipLabelY + 26 + row * (CHIP_H + 8), w = CHIP_W, h = CHIP_H }
    end
    -- buttons along the bottom: START (host only), ROWDY, LEAVE
    local names = info.host and { "start", "rowdy", "leave" } or { "rowdy", "leave" }
    local bw = math.min(200, (sw - 24 - (#names - 1) * GAP) / #names)
    local x0 = (sw - (#names * bw + (#names - 1) * GAP)) / 2
    for i, name in ipairs(names) do
        L.buttons[name] = { x = x0 + (i - 1) * (bw + GAP), y = sh - 24 - BUTTON_H, w = bw, h = BUTTON_H }
    end
    return L
end

-- Screen position -> "start", "rowdy", "leave", "invite" + the index in info.nearby, or nil
function Waiting.hit(info, x, y)
    local ui = uiScale()
    x, y = x / ui, y / ui
    local L = layout(info)
    for name, r in pairs(L.buttons) do
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then return name end
    end
    for i, r in ipairs(L.chips) do
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then return "invite", i end
    end
end

-- Returns "start" (host), "rowdy", "leave" or nil
function Waiting.keypressed(info, key)
    if key == "return" or key == "kpenter" or key == "space" then
        return info.host and "start" or nil
    elseif key == "r" then return "rowdy"
    elseif key == "escape" then return "leave" end
end

local function button(r, label, color, fonts)
    love.graphics.setColor(color[1], color[2], color[3], 0.95)
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 12, 12)
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 12, 12)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(fonts.button)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(label, r.x, r.y + (r.h - fonts.button:getHeight()) / 2, r.w, "center")
end

-- info: { host = bool, mode = "Team fight", address = "192.168.1.5" or nil, hostNick,
--         players = { { id, nick, rowdy, host }, ... }, localId, connecting = "text" or nil }
function Waiting.draw(info, fonts)
    local L = layout(info)
    love.graphics.push()
    love.graphics.scale(uiScale())
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, L.sw, L.sh)

    love.graphics.setFont(fonts.button)
    love.graphics.setColor(1, 0.8, 0.2)
    love.graphics.printf(info.host and "Your game" or "Waiting room", 0, 24, L.sw, "center")
    love.graphics.setFont(fonts.text)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.printf(info.mode or "", 0, 66, L.sw, "center")

    if info.connecting then
        love.graphics.setFont(fonts.button)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(info.connecting, 0, L.sh / 2 - 40, L.sw, "center")
    else
        love.graphics.setFont(fonts.text)
        love.graphics.setColor(1, 1, 1, 0.75)
        if info.host then
            love.graphics.printf("Friends: JOIN in your Wi-Fi" .. (info.address and (" or type " .. info.address) or "")
                .. " - then press START when everybody is here", 24, 96, L.sw - 48, "center")
        else
            love.graphics.printf("Waiting for " .. (info.hostNick or "the host") .. " to start the round",
                24, 96, L.sw - 48, "center")
        end

        for i, p in ipairs(info.players) do
            local r = L.cards[i]
            local def = Rowdies[p.rowdy] or Rowdies[1]
            local mine = p.id == info.localId
            love.graphics.setColor(0.1, 0.12, 0.15, 0.92)
            love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 12, 12)
            love.graphics.setColor(mine and 1 or 0.4, mine and 0.8 or 0.85, mine and 0.2 or 0.4)
            love.graphics.setLineWidth(3)
            love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 12, 12)
            love.graphics.setLineWidth(1)
            local h = r.h - 88
            if not Assets.drawStanding(def, r.x + r.w / 2, r.y + 10 + h, h) then
                Assets.drawPortrait(def, r.x + r.w / 2, r.y + 10 + h / 2, h)
            end
            love.graphics.setFont(fonts.text)
            love.graphics.setColor(1, 1, 1)
            love.graphics.printf(p.nick, r.x + 4, r.y + r.h - 70, r.w - 8, "center")
            love.graphics.setColor(1, 1, 1, 0.6)
            love.graphics.printf(def.name, r.x + 4, r.y + r.h - 48, r.w - 8, "center")
            local tag = p.host and (mine and "HOST - YOU" or "HOST") or (mine and "YOU" or nil)
            if tag then
                love.graphics.setColor(1, 0.8, 0.2)
                love.graphics.printf(tag, r.x + 4, r.y + r.h - 27, r.w - 8, "center")
            end
        end
    end

    if info.host and not info.connecting then -- friends nearby: tap = invite
        love.graphics.setFont(fonts.text)
        love.graphics.setColor(1, 1, 1, 0.75)
        local label = #info.nearby == 0 and "Nobody nearby in the lobby - friends can also JOIN"
            or "Invite friends nearby:"
        love.graphics.printf(label, 12, L.chipLabelY, L.sw - 24, "center")
        for i, r in ipairs(L.chips) do
            local g = info.nearby[i]
            local sent = info.invited and info.invited[g.address]
                and info.now - info.invited[g.address] < Waiting.INVITE_QUIET
            love.graphics.setColor(sent and 0.2 or 0.15, sent and 0.35 or 0.45, sent and 0.25 or 0.8, 0.95)
            love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 8, 8)
            love.graphics.setColor(1, 1, 1, sent and 0.6 or 1)
            love.graphics.printf((sent and "sent: " or "") .. g.nick, r.x + 4, r.y + (r.h - fonts.text:getHeight()) / 2,
                r.w - 8, "center")
        end
    end
    if L.buttons.start then button(L.buttons.start, "START", { 0.9, 0.65, 0.05 }, fonts) end
    button(L.buttons.rowdy, "ROWDY", { 0.2, 0.5, 0.9 }, fonts)
    button(L.buttons.leave, "LEAVE", { 0.35, 0.37, 0.45 }, fonts)
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

return Waiting
