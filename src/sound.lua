-- Sound effects, synthesized at startup (sfxr-style: tones with pitch slides, noise,
-- envelopes), so there are no sound files and no licenses to care about.
-- Sound.play(name, x, y): world position -> quieter with distance from the listener
-- (the own rowdy) and panned left/right; nil position = UI sound at full volume.
local Sound = {}

local RATE = 44100
local HEAR_DIST = 1100   -- px: silent beyond this distance from the listener
local PAN_DIST = 700     -- px: fully left/right at this horizontal offset
local VOICES = 6         -- copies per sound that can play at the same time
local MIN_GAP = 0.035    -- s: the same sound is not restarted faster than this

Sound.volume = 0.8
Sound.muted = false

local sources = {}       -- name -> { list of Sources }
Sound.data = {}          -- name -> SoundData
local lastPlayed = {}    -- name -> time
local listenerX, listenerY = 0, 0

---------------------------------------------------------------------------- synth

-- One layer: wave, frequency slide f1 -> f2 (exponential), attack/decay envelope
--   { wave = "square"|"saw"|"sine"|"triangle"|"noise", f1, f2, dur, vol, attack,
--     delay (s before it starts), lowpass (0..1, noise smoothing; 1 = none),
--     vibrato = { depth, rate }, duty (square, default 0.5) }
local function renderLayer(buf, n, L)
    local start = math.floor((L.delay or 0) * RATE)
    local len = math.floor(L.dur * RATE)
    local phase, noise, lp = 0, 0, L.lowpass or 1
    local attack = math.max(1, math.floor((L.attack or 0.005) * RATE))
    local duty = L.duty or 0.5
    for i = 0, len - 1 do
        local k = start + i
        if k >= n then break end
        local t = i / len
        local f = L.f1 * (L.f2 / L.f1) ^ t
        if L.vibrato then f = f * (1 + L.vibrato[1] * math.sin(2 * math.pi * L.vibrato[2] * i / RATE)) end
        phase = (phase + f / RATE) % 1
        local v
        if L.wave == "square" then v = phase < duty and 1 or -1
        elseif L.wave == "saw" then v = 2 * phase - 1
        elseif L.wave == "triangle" then v = 1 - 4 * math.abs(phase - 0.5)
        elseif L.wave == "sine" then v = math.sin(2 * math.pi * phase)
        else -- noise, smoothed by a one-pole lowpass (lower = duller)
            noise = noise + ((math.random() * 2 - 1) - noise) * lp
            v = noise
        end
        local env = math.min(1, i / attack) * (1 - t) ^ (L.curve or 1.5)
        buf[k] = buf[k] + v * env * (L.vol or 0.5)
    end
end

-- Several layers mixed into one SoundData
local function synth(layers)
    local total = 0
    for _, L in ipairs(layers) do total = math.max(total, (L.delay or 0) + L.dur) end
    local n = math.floor(total * RATE) + 1
    local buf = {}
    for i = 0, n - 1 do buf[i] = 0 end
    for _, L in ipairs(layers) do renderLayer(buf, n, L) end
    local data = love.sound.newSoundData(n, RATE, 16, 1)
    for i = 0, n - 1 do data:setSample(i, math.max(-1, math.min(1, buf[i]))) end
    return data
end

-- Notes one after another (jingles): { {freq, dur}, ... }
local function notes(list, wave, vol, extra)
    local layers, t = {}, 0
    for _, nt in ipairs(list) do
        layers[#layers + 1] = { wave = wave, f1 = nt[1], f2 = nt[1], dur = nt[2] * 1.6,
            vol = vol, delay = t, curve = 2, duty = 0.3 }
        t = t + nt[2]
    end
    for _, L in ipairs(extra or {}) do layers[#layers + 1] = L end
    return layers
end

local C5, E5, G5, C6 = 523.3, 659.3, 784.0, 1046.5

local DEFS = {
    -- shots (one per attack; picked by rowdy: `shot` in src/rowdies.lua)
    shot_gunner  = { { wave = "square", f1 = 900, f2 = 220, dur = 0.09, vol = 0.22, duty = 0.35 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.05, vol = 0.35, lowpass = 0.5 } },
    shot_shotgun = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.24, vol = 0.6, lowpass = 0.25, curve = 2.5 },
                     { wave = "sine", f1 = 140, f2 = 45, dur = 0.18, vol = 0.6 } },
    shot_sniper  = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.06, vol = 0.5, lowpass = 0.9 },
                     { wave = "saw", f1 = 1600, f2 = 250, dur = 0.16, vol = 0.22 },
                     { wave = "sine", f1 = 180, f2 = 60, dur = 0.2, vol = 0.4 } },
    shot_bot     = { { wave = "square", f1 = 700, f2 = 260, dur = 0.11, vol = 0.18, duty = 0.25,
                       vibrato = { 0.05, 40 } } },
    shot_water   = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.16, vol = 0.4, lowpass = 0.75, attack = 0.01 },
                     { wave = "sine", f1 = 520, f2 = 260, dur = 0.06, vol = 0.3 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.1, vol = 0.15, lowpass = 0.15, delay = 0.04 } },
    shot_throw   = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.18, vol = 0.25, lowpass = 0.35, attack = 0.04 },
                     { wave = "sine", f1 = 300, f2 = 700, dur = 0.14, vol = 0.18, attack = 0.03 } },
    blast        = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.5, vol = 0.7, lowpass = 0.18, curve = 2 },
                     { wave = "sine", f1 = 120, f2 = 35, dur = 0.45, vol = 0.8 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.08, vol = 0.4, lowpass = 0.8 } },
    blastBig     = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.8, vol = 0.8, lowpass = 0.12, curve = 1.8 },
                     { wave = "sine", f1 = 90, f2 = 25, dur = 0.7, vol = 0.9 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.12, vol = 0.45, lowpass = 0.8 } },
    super        = { { wave = "saw", f1 = 250, f2 = 1400, dur = 0.14, vol = 0.25 },
                     { wave = "sine", f1 = 220, f2 = 40, dur = 0.5, vol = 0.7, delay = 0.08 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.4, vol = 0.45, lowpass = 0.3, delay = 0.08 } },
    superReady   = notes({ { 880, 0.07 }, { 1320, 0.12 } }, "triangle", 0.35),
    -- hits
    hit          = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.06, vol = 0.4, lowpass = 0.35 },
                     { wave = "sine", f1 = 320, f2 = 140, dur = 0.08, vol = 0.45 } },
    hurt         = { { wave = "square", f1 = 240, f2 = 110, dur = 0.14, vol = 0.25, duty = 0.4 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.08, vol = 0.35, lowpass = 0.3 } },
    impact       = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.035, vol = 0.22, lowpass = 0.6 } },
    death        = { { wave = "square", f1 = 620, f2 = 90, dur = 0.38, vol = 0.22, duty = 0.3 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.3, vol = 0.35, lowpass = 0.2 } },
    spawn        = { { wave = "sine", f1 = 300, f2 = 950, dur = 0.25, vol = 0.3, attack = 0.05 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.2, vol = 0.08, lowpass = 0.15, attack = 0.08 } },
    heal         = notes({ { C5, 0.06 }, { E5, 0.06 }, { G5, 0.06 }, { C6, 0.1 } }, "triangle", 0.3),
    -- loot: a box appears / is hit / breaks, a coin is picked up, a rowdy is bought
    box          = { { wave = "sine", f1 = 200, f2 = 520, dur = 0.18, vol = 0.3, attack = 0.02 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.12, vol = 0.12, lowpass = 0.2 } },
    boxHit       = { { wave = "sine", f1 = 210, f2 = 120, dur = 0.07, vol = 0.5 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.05, vol = 0.3, lowpass = 0.25 } },
    boxBreak     = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.35, vol = 0.55, lowpass = 0.3, curve = 2.5 },
                     { wave = "sine", f1 = 160, f2 = 50, dur = 0.25, vol = 0.55 },
                     { wave = "square", f1 = 1320, f2 = 1320, dur = 0.08, vol = 0.12, delay = 0.12, duty = 0.3 },
                     { wave = "square", f1 = 1760, f2 = 1760, dur = 0.12, vol = 0.12, delay = 0.19, duty = 0.3 } },
    coin         = notes({ { 988, 0.05 }, { 1319, 0.12 } }, "square", 0.14),
    unlock       = notes({ { C5, 0.08 }, { E5, 0.08 }, { G5, 0.08 }, { C6, 0.08 }, { G5, 0.08 }, { C6, 0.3 } },
                         "square", 0.18,
                         { { wave = "triangle", f1 = C5 / 2, f2 = C5 / 2, dur = 0.7, vol = 0.25, delay = 0.4 } }),
    -- Yard Pass: a new tier reached, a reward claimed
    tierUp       = notes({ { G5, 0.07 }, { C6, 0.07 }, { E5 * 2, 0.07 }, { G5 * 2, 0.22 } }, "triangle", 0.3,
                         { { wave = "sine", f1 = 400, f2 = 1600, dur = 0.3, vol = 0.12, attack = 0.05 } }),
    claim        = notes({ { E5, 0.05 }, { G5, 0.05 }, { C6, 0.16 } }, "square", 0.16,
                         { { wave = "noise", f1 = 1, f2 = 1, dur = 0.25, vol = 0.1, lowpass = 0.6, delay = 0.08 } }),
    -- rounds and UI
    roundStart   = notes({ { G5, 0.09 }, { C6, 0.16 } }, "square", 0.18),
    victory      = notes({ { C5, 0.11 }, { E5, 0.11 }, { G5, 0.11 }, { C6, 0.35 } }, "square", 0.2,
                         { { wave = "triangle", f1 = C5 / 2, f2 = C5 / 2, dur = 0.8, vol = 0.25, delay = 0.33 } }),
    defeat       = notes({ { G5 / 2, 0.16 }, { E5 / 2, 0.16 }, { C5 / 2, 0.16 }, { C5 / 2 * 0.94, 0.45 } }, "saw", 0.3),
    draw         = notes({ { E5, 0.14 }, { E5, 0.3 } }, "triangle", 0.3),
    click        = { { wave = "square", f1 = 1200, f2 = 900, dur = 0.025, vol = 0.15 } },
}

local SETTINGS_FILE = "sound.txt" -- remembers "muted" between starts

-- Build all sounds (call once in love.load)
function Sound.load()
    Sound.muted = love.filesystem.getInfo(SETTINGS_FILE) ~= nil
        and love.filesystem.read(SETTINGS_FILE) == "muted"
    love.audio.setDistanceModel("none") -- positions only pan, the volume is ours
    -- a rowdy's shot sound must exist (src/rowdies.lua: shot)
    local Rowdies = require("src.rowdies")
    for _, def in ipairs({ Rowdies.bot, unpack(Rowdies) }) do
        if def.shot and not DEFS[def.shot] then
            error("src/rowdies.lua: " .. def.name .. ": unknown shot sound '" .. def.shot
                .. "' (see DEFS in src/sound.lua)", 0)
        end
    end
    for name, layers in pairs(DEFS) do
        local data = synth(layers)
        Sound.data[name] = data -- kept for tests (levels, export)
        local src = love.audio.newSource(data, "static")
        local list = { src }
        for _ = 2, VOICES do list[#list + 1] = src:clone() end
        sources[name] = list
    end
end

-- Where the ears are (the own rowdy)
function Sound.setListener(x, y)
    listenerX, listenerY = x, y
end

function Sound.play(name, x, y, volume)
    local list = sources[name]
    if not list or Sound.muted then return end
    local now = love.timer.getTime()
    if lastPlayed[name] and now - lastPlayed[name] < MIN_GAP then return end

    local vol, pan = Sound.volume * (volume or 1), 0
    if x then
        local dx, dy = x - listenerX, y - listenerY
        local d = math.sqrt(dx * dx + dy * dy)
        if d >= HEAR_DIST then return end
        vol = vol * (1 - d / HEAR_DIST) ^ 1.5
        pan = math.max(-1, math.min(1, dx / PAN_DIST))
    end
    lastPlayed[name] = now

    -- a free voice, or else the first one again
    local src = list[1]
    for _, s in ipairs(list) do
        if not s:isPlaying() then src = s break end
    end
    src:stop()
    src:setVolume(vol)
    src:setPosition(pan, 0, 0)
    src:play()
end

-- Shot sound of a rowdy definition (its `shot` field in src/rowdies.lua)
function Sound.shotFor(def)
    return def and def.shot or "shot_gunner"
end

function Sound.toggleMute()
    Sound.muted = not Sound.muted
    if Sound.muted then love.audio.stop() end
    love.filesystem.write(SETTINGS_FILE, Sound.muted and "muted" or "on")
end

return Sound
