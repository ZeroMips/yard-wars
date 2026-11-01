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
    shot_pen     = { { wave = "square", f1 = 1800, f2 = 900, dur = 0.05, vol = 0.14, duty = 0.2 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.07, vol = 0.18, lowpass = 0.7, attack = 0.01 } },
    shot_pan     = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.22, vol = 0.3, lowpass = 0.25, attack = 0.05 },
                     { wave = "sine", f1 = 180, f2 = 420, dur = 0.2, vol = 0.15, attack = 0.04, vibrato = { 0.2, 18 } } },
    shot_blaster = { { wave = "square", f1 = 1500, f2 = 480, dur = 0.07, vol = 0.14, duty = 0.25 },
                     { wave = "sine", f1 = 2200, f2 = 900, dur = 0.05, vol = 0.1 } },
    -- a pan bounces off a wall: a cartoon "clang"
    clang        = { { wave = "square", f1 = 1250, f2 = 1180, dur = 0.3, vol = 0.12, duty = 0.15,
                       vibrato = { 0.02, 30 } },
                     { wave = "triangle", f1 = 1870, f2 = 1800, dur = 0.25, vol = 0.12 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.03, vol = 0.3, lowpass = 0.9 } },
    -- frozen / a freeze ball bursts: icy tinkling
    freeze       = notes({ { 1760, 0.04 }, { 2349, 0.04 }, { 2637, 0.04 }, { 3136, 0.12 } }, "triangle", 0.2,
                         { { wave = "noise", f1 = 1, f2 = 1, dur = 0.3, vol = 0.18, lowpass = 0.95, attack = 0.02 } }),
    -- something heavy lands (a book): a dull thud
    thud         = { { wave = "sine", f1 = 160, f2 = 50, dur = 0.25, vol = 0.8 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.18, vol = 0.4, lowpass = 0.12 } },
    shot_potion  = { { wave = "sine", f1 = 2400, f2 = 2300, dur = 0.08, vol = 0.12 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.16, vol = 0.22, lowpass = 0.35, attack = 0.04 } },
    splash       = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.3, vol = 0.45, lowpass = 0.45, attack = 0.01 },
                     { wave = "sine", f1 = 700, f2 = 180, dur = 0.15, vol = 0.3 },
                     { wave = "sine", f1 = 500, f2 = 900, dur = 0.08, vol = 0.15, delay = 0.12 } },
    magnet       = { { wave = "sine", f1 = 300, f2 = 900, dur = 0.35, vol = 0.3, vibrato = { 0.08, 25 } },
                     { wave = "square", f1 = 150, f2 = 450, dur = 0.3, vol = 0.08, duty = 0.3 } },
    jump         = { { wave = "sine", f1 = 220, f2 = 700, dur = 0.22, vol = 0.35, attack = 0.02 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.1, vol = 0.15, lowpass = 0.3 } },
    slam         = { { wave = "sine", f1 = 130, f2 = 35, dur = 0.4, vol = 0.9 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.3, vol = 0.5, lowpass = 0.15 },
                     { wave = "square", f1 = 90, f2 = 50, dur = 0.15, vol = 0.15 } },
    punch        = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.07, vol = 0.45, lowpass = 0.3 },
                     { wave = "sine", f1 = 180, f2 = 70, dur = 0.12, vol = 0.55 } },
    shot_shovel  = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.14, vol = 0.3, lowpass = 0.3, attack = 0.04 },
                     { wave = "triangle", f1 = 600, f2 = 420, dur = 0.08, vol = 0.18, delay = 0.08 } },
    dig          = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.45, vol = 0.5, lowpass = 0.1, curve = 1 },
                     { wave = "sine", f1 = 90, f2 = 60, dur = 0.4, vol = 0.4 } },
    pop          = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.35, vol = 0.55, lowpass = 0.15 },
                     { wave = "sine", f1 = 150, f2 = 600, dur = 0.12, vol = 0.4 },
                     { wave = "sine", f1 = 120, f2 = 40, dur = 0.3, vol = 0.6, delay = 0.05 } },
    boo          = { { wave = "sine", f1 = 500, f2 = 260, dur = 0.35, vol = 0.3, attack = 0.04,
                       vibrato = { 0.06, 7 } },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.2, vol = 0.1, lowpass = 0.2 } },
    vanish       = { { wave = "sine", f1 = 400, f2 = 1800, dur = 0.3, vol = 0.18, vibrato = { 0.05, 30 } },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.25, vol = 0.12, lowpass = 0.5, attack = 0.05 } },
    shot_beam    = { { wave = "saw", f1 = 330, f2 = 300, dur = 0.32, vol = 0.07, attack = 0.03, curve = 0.5,
                       vibrato = { 0.03, 18 } },
                     { wave = "sine", f1 = 660, f2 = 640, dur = 0.32, vol = 0.08, attack = 0.03, curve = 0.5 } },
    grab         = notes({ { 880, 0.05 }, { 1175, 0.05 }, { 1480, 0.12 } }, "triangle", 0.2,
                         { { wave = "sine", f1 = 300, f2 = 600, dur = 0.3, vol = 0.15, vibrato = { 0.1, 12 } } }),
    fling        = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.3, vol = 0.3, lowpass = 0.3, attack = 0.05 },
                     { wave = "sine", f1 = 300, f2 = 1200, dur = 0.25, vol = 0.15 } },
    bonk         = { { wave = "sine", f1 = 900, f2 = 250, dur = 0.18, vol = 0.45 },
                     { wave = "square", f1 = 300, f2 = 150, dur = 0.1, vol = 0.12, duty = 0.3 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.06, vol = 0.3, lowpass = 0.6 } },
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
    -- a rowdy is knocked out: soft puff + cartoon slide whistle (no sad or harsh sound)
    poof         = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.25, vol = 0.35, lowpass = 0.12, attack = 0.02 },
                     { wave = "sine", f1 = 900, f2 = 1500, dur = 0.12, vol = 0.18, delay = 0.03 },
                     { wave = "sine", f1 = 1500, f2 = 500, dur = 0.22, vol = 0.18, delay = 0.15 } },
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
    -- Posion, Fruit Man, Officer, Tornalo, Mecha Robot (2026-10-12)
    shot_goo     = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.18, vol = 0.35, lowpass = 0.3, attack = 0.01 },
                     { wave = "sine", f1 = 260, f2 = 140, dur = 0.12, vol = 0.3, vibrato = { 0.15, 25 } } },
    shot_sling   = { { wave = "triangle", f1 = 700, f2 = 180, dur = 0.12, vol = 0.3 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.05, vol = 0.2, lowpass = 0.6 } },
    shot_cuffs   = { { wave = "square", f1 = 1900, f2 = 1700, dur = 0.05, vol = 0.1, duty = 0.2 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.14, vol = 0.2, lowpass = 0.4, attack = 0.03 } },
    -- handcuffs click shut
    cuff         = { { wave = "square", f1 = 2400, f2 = 2200, dur = 0.03, vol = 0.12, duty = 0.2 },
                     { wave = "square", f1 = 2000, f2 = 1900, dur = 0.04, vol = 0.12, duty = 0.2, delay = 0.06 } },
    whirl        = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.4, vol = 0.45, lowpass = 0.2, attack = 0.08, curve = 1 },
                     { wave = "sine", f1 = 300, f2 = 900, dur = 0.35, vol = 0.12, vibrato = { 0.2, 14 } } },
    gust         = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.5, vol = 0.5, lowpass = 0.12, attack = 0.05, curve = 1.2 },
                     { wave = "sine", f1 = 200, f2 = 600, dur = 0.4, vol = 0.1 } },
    -- a firework rocket pops: a bang and crackles
    firework     = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.25, vol = 0.5, lowpass = 0.4 },
                     { wave = "sine", f1 = 900, f2 = 1400, dur = 0.1, vol = 0.12 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.04, vol = 0.3, lowpass = 0.95, delay = 0.15 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.04, vol = 0.25, lowpass = 0.95, delay = 0.24 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.04, vol = 0.2, lowpass = 0.95, delay = 0.31 } },
    -- the barrier goes up: a whistle and a thump
    barrier      = { { wave = "sine", f1 = 2200, f2 = 2200, dur = 0.25, vol = 0.12, vibrato = { 0.04, 30 } },
                     { wave = "sine", f1 = 140, f2 = 70, dur = 0.2, vol = 0.5, delay = 0.08 } },
    -- Yardball: a kick (a soft "thock"), taking the ball, a bounce off a wall, a goal
    -- (a jingle over a cheering crowd of noise)
    kick         = { { wave = "sine", f1 = 260, f2 = 90, dur = 0.12, vol = 0.7 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.06, vol = 0.35, lowpass = 0.5 } },
    pickup       = { { wave = "triangle", f1 = 500, f2 = 800, dur = 0.08, vol = 0.25 },
                     { wave = "sine", f1 = 180, f2 = 120, dur = 0.06, vol = 0.3 } },
    bounce       = { { wave = "sine", f1 = 220, f2 = 130, dur = 0.08, vol = 0.4 } },
    goal         = notes({ { C5, 0.08 }, { E5, 0.08 }, { G5, 0.08 }, { C6, 0.08 }, { G5, 0.08 }, { C6, 0.4 } },
                         "square", 0.16,
                         { { wave = "noise", f1 = 1, f2 = 1, dur = 1.3, vol = 0.28, lowpass = 0.35, attack = 0.15,
                             curve = 1 },
                           { wave = "noise", f1 = 1, f2 = 1, dur = 1.0, vol = 0.18, lowpass = 0.7, attack = 0.1,
                             delay = 0.15, curve = 1.2 } }),
    -- King of the Yard: a heart beacon appears (a soft chime), a rowdy is brought back
    -- (a rising jingle), the fog starts closing in (a low whoosh)
    beacon       = notes({ { E5, 0.1 }, { C5, 0.2 } }, "sine", 0.25),
    revive       = notes({ { C5, 0.06 }, { E5, 0.06 }, { G5, 0.06 }, { C6, 0.06 }, { E5 * 2, 0.2 } }, "triangle", 0.28,
                         { { wave = "sine", f1 = 400, f2 = 1200, dur = 0.35, vol = 0.12, attack = 0.05 } }),
    fog          = { { wave = "noise", f1 = 1, f2 = 1, dur = 1.4, vol = 0.4, lowpass = 0.08, attack = 0.4, curve = 1 },
                     { wave = "sine", f1 = 110, f2 = 80, dur = 1.2, vol = 0.25, attack = 0.3, curve = 1 } },
    -- Hide and seek: the seeker's countdown (the last seconds), "ready or not, here I
    -- come!", a hider turns into a bush (a rustle, only the own team hears it), a picture
    -- piece placed, the picture complete, the hint shimmer
    tick         = { { wave = "triangle", f1 = 1400, f2 = 1300, dur = 0.05, vol = 0.25 } },
    ready        = notes({ { G5, 0.1 }, { G5, 0.1 }, { C6, 0.1 }, { E5 * 2, 0.3 } }, "square", 0.17,
                         { { wave = "sine", f1 = 300, f2 = 900, dur = 0.35, vol = 0.12, delay = 0.3 } }),
    rustle       = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.35, vol = 0.3, lowpass = 0.45, attack = 0.05, curve = 1 } },
    piece        = notes({ { C5, 0.07 }, { G5, 0.07 }, { C6, 0.18 } }, "triangle", 0.3,
                         { { wave = "sine", f1 = 180, f2 = 120, dur = 0.12, vol = 0.4 } }),
    picture      = notes({ { C5, 0.08 }, { E5, 0.08 }, { G5, 0.08 }, { C6, 0.08 }, { E5 * 2, 0.08 }, { G5 * 2, 0.4 } },
                         "triangle", 0.28,
                         { { wave = "noise", f1 = 1, f2 = 1, dur = 0.8, vol = 0.15, lowpass = 0.7, attack = 0.1, delay = 0.3 } }),
    hint         = { { wave = "sine", f1 = 1800, f2 = 2600, dur = 0.5, vol = 0.12, vibrato = { 0.04, 16 } },
                     { wave = "triangle", f1 = 2400, f2 = 3200, dur = 0.4, vol = 0.08, delay = 0.12 } },
    -- Flower Gardens: a flower picked (a soft pluck), one delivered (a chime), a bulldozer
    -- arrives (a toy horn), its engine (a short putt-putt, played again and again while
    -- it drives), a fence knocked down (wood crashing)
    flower       = { { wave = "triangle", f1 = 900, f2 = 1300, dur = 0.09, vol = 0.25 },
                     { wave = "sine", f1 = 1300, f2 = 1600, dur = 0.12, vol = 0.12, delay = 0.05 } },
    deliver      = notes({ { E5, 0.07 }, { G5, 0.07 }, { C6, 0.2 } }, "sine", 0.32,
                         { { wave = "triangle", f1 = C6 * 2, f2 = C6 * 2, dur = 0.3, vol = 0.08, delay = 0.14 } }),
    dozerStart   = notes({ { G5 / 2, 0.14 }, { C5, 0.32 } }, "square", 0.2),
    dozer        = { { wave = "square", f1 = 70, f2 = 60, dur = 0.12, vol = 0.18, duty = 0.3 },
                     { wave = "noise", f1 = 1, f2 = 1, dur = 0.1, vol = 0.15, lowpass = 0.1 } },
    fence        = { { wave = "noise", f1 = 1, f2 = 1, dur = 0.6, vol = 0.6, lowpass = 0.25, curve = 2 },
                     { wave = "sine", f1 = 200, f2 = 70, dur = 0.3, vol = 0.6 },
                     { wave = "square", f1 = 420, f2 = 300, dur = 0.08, vol = 0.12, delay = 0.12, duty = 0.2 },
                     { wave = "square", f1 = 360, f2 = 250, dur = 0.08, vol = 0.1, delay = 0.25, duty = 0.2 } },
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
