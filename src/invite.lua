-- The invitation banner in the lobby: "Anna invites you to Team fight" with JOIN and
-- NO THANKS. Invites come from a host's waiting room over the local network only
-- (src/net.lua Lobby listener) and are only shown while the player is in the lobby.
-- CHARTER.md: calm, no nagging - one banner at a time, it goes away by itself after
-- SHOW_TIME, no sound loop, and the same host can't invite again for a while.
local Invite = {}

Invite.SHOW_TIME = 20 -- seconds the banner stays
Invite.QUIET = 60     -- seconds an invite from the same address is ignored after the last one

Invite.current = nil  -- { nick, mode, address, expires }
local lastFrom = {}   -- address -> time of its last accepted invite

local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end

-- A new invite (from Lobby:update). Returns true if it will be shown.
function Invite.add(inv, now)
    now = now or love.timer.getTime()
    if Invite.current then return false end
    if lastFrom[inv.address] and now - lastFrom[inv.address] < Invite.QUIET then return false end
    lastFrom[inv.address] = now
    Invite.current = { nick = inv.nick ~= "" and inv.nick or "Somebody", mode = inv.mode,
        address = inv.address, expires = now + Invite.SHOW_TIME }
    return true
end

function Invite.update(now)
    now = now or love.timer.getTime()
    if Invite.current and now >= Invite.current.expires then Invite.current = nil end
end

function Invite.clear() Invite.current = nil end

local function layout()
    local ui = uiScale()
    local sw = love.graphics.getWidth() / ui
    local w = math.min(560, sw - 24)
    local x = (sw - w) / 2
    local panel = { x = x, y = 8, w = w, h = 92 }
    local bw = (w - 36) / 2
    return { panel = panel,
        join = { x = x + 12, y = 48, w = bw, h = 44 },
        no = { x = x + 24 + bw, y = 48, w = bw, h = 44 } }
end

-- Screen position -> "join", "no" (or "panel" for the rest of the banner) or nil
function Invite.hit(x, y)
    if not Invite.current then return nil end
    local ui = uiScale()
    x, y = x / ui, y / ui
    local L = layout()
    local function inside(r) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end
    if inside(L.join) then return "join" end
    if inside(L.no) then return "no" end
    if inside(L.panel) then return "panel" end
end

function Invite.draw(fonts)
    local inv = Invite.current
    if not inv then return end
    local L = layout()
    love.graphics.push()
    love.graphics.scale(uiScale())
    local p = L.panel
    love.graphics.setColor(0.08, 0.1, 0.16, 0.96)
    love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, 12, 12)
    love.graphics.setColor(1, 0.8, 0.2)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", p.x, p.y, p.w, p.h, 12, 12)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(fonts.text)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(inv.nick .. " invites you" .. (inv.mode ~= "" and (": " .. inv.mode) or ""),
        p.x + 12, p.y + 12, p.w - 24, "center")
    for _, name in ipairs({ "join", "no" }) do
        local r = L[name]
        if name == "join" then love.graphics.setColor(0.3, 0.75, 0.3) else love.graphics.setColor(0.35, 0.37, 0.45) end
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 10, 10)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf(name == "join" and "JOIN" or "NO THANKS", r.x, r.y + (r.h - fonts.text:getHeight()) / 2,
            r.w, "center")
    end
    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

return Invite
