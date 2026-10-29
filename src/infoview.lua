-- Info screen: what the updater did on this device and the last crash (Updater.report(),
-- see src/updater.lua), so it can be read (or screenshotted) on a phone, where the save
-- folder can't be reached. Opened by a long press on the build line in the lobby (key I).
-- The text scrolls: drag, mouse wheel, arrow / page keys. While a build is marked bad
-- here, a "Try build N again" button (key R) lets it be downloaded and used once more
-- (Updater.retryBad). Laid out in HUD units (720 along the short screen side), like the
-- menu.
local Updater = require("src.updater")

local InfoView = {}

InfoView.scroll = 0
InfoView.dragged = false -- the current touch scrolled (main.lua then ignores its release)
local text = ""
local dragDist = 0
local DRAG_SLOP = 12
local maxScroll = 0
local notice -- shown under the title after a retry ("Build 105 is downloaded again ...")

local function uiScale() return math.min(love.graphics.getDimensions()) / 720 end

local function layout()
    local ui = uiScale()
    local sw, sh = love.graphics.getWidth() / ui, love.graphics.getHeight() / ui
    local back = { x = (sw - 220) / 2, y = sh - 76, w = 220, h = 60 }
    local retry
    if Updater.badBuild() then -- two buttons: retry on the left, Back on the right
        local w = math.min(320, (sw - 56) / 2 - 50)
        retry = { x = sw / 2 - 8 - w, y = back.y, w = w, h = 60 }
        back.x = sw / 2 + 8
    end
    local box = { x = 20, y = 96, w = sw - 40, h = back.y - 16 - 96 }
    return box, back, sw, sh, retry
end

-- Try the bad build again (button / key R)
local function retry()
    local build = Updater.badBuild()
    if not build then return end
    if Updater.retryBad() then
        notice = "Build " .. build .. " is allowed again: the newest build is downloaded and used at the next start"
    else
        notice = "Can't check for updates right now - try again in a moment"
    end
    text = Updater.report()
end

function InfoView.open()
    Updater.mirror() -- the copy shows what is on screen
    text = Updater.report()
    InfoView.scroll = 0
    notice = nil
end

local function clamp()
    InfoView.scroll = math.max(0, math.min(maxScroll, InfoView.scroll))
end

function InfoView.touchStart() InfoView.dragged, dragDist = false, 0 end

function InfoView.drag(dy)
    dy = dy / uiScale()
    dragDist = dragDist + math.abs(dy)
    if dragDist > DRAG_SLOP then InfoView.dragged = true end
    InfoView.scroll = InfoView.scroll - dy
    clamp()
end

function InfoView.wheel(y)
    InfoView.scroll = InfoView.scroll - y * 60
    clamp()
end

-- Returns "back" or nil
function InfoView.keypressed(key)
    local box = layout()
    if key == "escape" or key == "backspace" or key == "return" or key == "i" then return "back"
    elseif key == "r" then retry()
    elseif key == "down" or key == "s" then InfoView.scroll = InfoView.scroll + 40
    elseif key == "up" or key == "w" then InfoView.scroll = InfoView.scroll - 40
    elseif key == "pagedown" or key == "space" then InfoView.scroll = InfoView.scroll + box.h - 40
    elseif key == "pageup" then InfoView.scroll = InfoView.scroll - box.h + 40
    elseif key == "home" then InfoView.scroll = 0
    elseif key == "end" then InfoView.scroll = maxScroll end
    clamp()
end

local function inside(r, x, y) return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end

-- Screen position -> "back" or nil (the retry button is handled here)
function InfoView.hit(x, y)
    local ui = uiScale()
    x, y = x / ui, y / ui
    local _, back, _, _, retryRect = layout()
    if inside(back, x, y) then return "back" end
    if inside(retryRect, x, y) then retry() end
end

function InfoView.draw(fonts)
    local box, back, sw, sh, retryRect = layout()
    local ui = uiScale()
    love.graphics.push()
    love.graphics.scale(ui)

    love.graphics.setColor(0, 0, 0, 0.88)
    love.graphics.rectangle("fill", 0, 0, sw, sh)

    love.graphics.setFont(fonts.button)
    love.graphics.setColor(1, 0.8, 0.2)
    love.graphics.printf("Updates and crashes", 0, 20, sw, "center")
    love.graphics.setFont(fonts.text)
    love.graphics.setColor(1, 1, 1, 0.7)
    local where = Updater.mirrorPath and ("Copy for USB: " .. Updater.mirrorPath)
        or Updater.mirrorError and ("No copy for USB: " .. Updater.mirrorError)
        or "Take a screenshot to send this"
    if notice then love.graphics.setColor(0.5, 1, 0.5) end
    love.graphics.printf(notice or where, 20, 62, sw - 40, "center")

    love.graphics.setColor(0.08, 0.1, 0.12, 0.95)
    love.graphics.rectangle("fill", box.x, box.y, box.w, box.h, 10, 10)
    local font = fonts.small or fonts.text
    local _, lines = font:getWrap(text, box.w - 24)
    local height = #lines * font:getHeight()
    maxScroll = math.max(0, height - (box.h - 20))
    clamp()
    love.graphics.setScissor(box.x * ui, (box.y + 6) * ui, box.w * ui, (box.h - 12) * ui)
    love.graphics.setFont(font)
    love.graphics.setColor(0.9, 0.95, 0.9)
    love.graphics.printf(text, box.x + 12, box.y + 10 - InfoView.scroll, box.w - 24, "left")
    love.graphics.setScissor()
    if maxScroll > 0 then -- scroll bar
        local track = box.h - 20
        local h = math.max(30, track * (box.h - 20) / height)
        local y = box.y + 10 + (track - h) * InfoView.scroll / maxScroll
        love.graphics.setColor(1, 1, 1, 0.3)
        love.graphics.rectangle("fill", box.x + box.w - 8, y, 4, h, 2, 2)
    end

    love.graphics.setColor(0.1, 0.12, 0.15, 0.9)
    love.graphics.rectangle("fill", back.x, back.y, back.w, back.h, 10, 10)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", back.x, back.y, back.w, back.h, 10, 10)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(fonts.button)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Back", back.x, back.y + 14, back.w, "center")
    if retryRect then
        love.graphics.setColor(0.2, 0.55, 0.3, 0.95)
        love.graphics.rectangle("fill", retryRect.x, retryRect.y, retryRect.w, retryRect.h, 10, 10)
        love.graphics.setColor(1, 1, 1, 0.6)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", retryRect.x, retryRect.y, retryRect.w, retryRect.h, 10, 10)
        love.graphics.setLineWidth(1)
        love.graphics.setFont(fonts.text)
        love.graphics.setColor(1, 1, 1)
        love.graphics.printf("Try build " .. Updater.badBuild() .. " again", retryRect.x,
            retryRect.y + (retryRect.h - fonts.text:getHeight()) / 2, retryRect.w, "center")
    end

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
end

return InfoView
