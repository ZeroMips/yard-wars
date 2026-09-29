-- Camera that follows a target. It always shows the same amount of world along
-- the SHORT side of the screen (viewSize), so landscape and portrait both work
-- and resizing the window doesn't change gameplay.
local Camera = {
    x = 0, y = 0,          -- world position shown at the screen center
    viewSize = 720,        -- world units visible along the shorter screen side
    shakeAmount = 0,
}

function Camera.scale()
    return math.min(love.graphics.getWidth(), love.graphics.getHeight()) / Camera.viewSize
end

local function clampAxis(v, half, size)
    if size <= half * 2 then return size / 2 end -- world smaller than view: center
    return math.max(half, math.min(size - half, v))
end

-- Keep the view inside the world (bw x bh in world units)
function Camera.clamp(bw, bh)
    local s = Camera.scale()
    local halfW = love.graphics.getWidth() / s / 2
    local halfH = love.graphics.getHeight() / s / 2
    Camera.x = clampAxis(Camera.x, halfW, bw)
    Camera.y = clampAxis(Camera.y, halfH, bh)
end

-- Jump directly to a position (use once at start)
function Camera.snap(x, y, bw, bh)
    Camera.x, Camera.y = x, y
    Camera.clamp(bw, bh)
end

-- Smoothly follow (tx, ty)
function Camera.update(dt, tx, ty, bw, bh)
    local k = 1 - math.exp(-8 * dt)
    Camera.x = Camera.x + (tx - Camera.x) * k
    Camera.y = Camera.y + (ty - Camera.y) * k
    Camera.clamp(bw, bh)
    Camera.shakeAmount = math.max(0, Camera.shakeAmount - 30 * dt)
end

function Camera.shake(amount)
    Camera.shakeAmount = math.max(Camera.shakeAmount, amount)
end

function Camera.attach()
    local w, h = love.graphics.getDimensions()
    love.graphics.push()
    love.graphics.translate(w / 2, h / 2)
    love.graphics.scale(Camera.scale())
    local ox, oy = 0, 0
    if Camera.shakeAmount > 0 then
        ox = (math.random() * 2 - 1) * Camera.shakeAmount
        oy = (math.random() * 2 - 1) * Camera.shakeAmount
    end
    love.graphics.translate(-Camera.x + ox, -Camera.y + oy)
end

function Camera.detach()
    love.graphics.pop()
end

-- Screen (mouse) position -> world position
function Camera.toWorld(sx, sy)
    local w, h = love.graphics.getDimensions()
    local s = Camera.scale()
    return (sx - w / 2) / s + Camera.x, (sy - h / 2) / s + Camera.y
end

return Camera
