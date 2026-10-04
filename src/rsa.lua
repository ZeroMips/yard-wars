-- RSA signature check (PKCS#1 v1.5 with SHA-256, public exponent 65537) in plain Lua 5.1 /
-- LuaJIT: what `openssl dgst -sha256 -sign key.pem` produces. Used by the updater to
-- check that a downloaded build comes from us (the download itself is plain http).
--
-- Big numbers are arrays of 24-bit limbs (least significant first) stored in doubles.
-- Multiplication is Montgomery's CIOS method: every step adds one 24x24-bit product to a
-- limb and a carry, so no intermediate value gets near 2^53 (exact in a double).
-- 24 bits = 3 bytes, so converting to bytes is simple too.
local Rsa = {}

local B = 16777216 -- 2^24, limb base
local floor = math.floor

-- SHA-256 DigestInfo prefix (DER) of the PKCS#1 v1.5 encoding
local DIGEST_INFO = "\48\49\48\13\6\9\96\134\72\1\101\3\4\2\1\5\0\4\32"

-- Hex string -> limbs (n limbs, or as many as needed), nil for non-hex input
local function fromHex(hex, n)
    hex = hex:gsub("%s", "")
    if hex == "" or hex:find("[^%x]") then return nil end
    local a = {}
    local i = #hex
    while i > 0 do
        a[#a + 1] = tonumber(hex:sub(math.max(1, i - 5), i), 16)
        i = i - 6
    end
    for k = #a + 1, n or 0 do a[k] = 0 end
    return a
end

-- Limbs (n of them) -> big-endian byte string of exactly `bytes` bytes (nil if too big)
local function toBytes(a, n, bytes)
    local out = {}
    for i = n, 1, -1 do
        local v = a[i]
        out[#out + 1] = string.char(floor(v / 65536), floor(v / 256) % 256, v % 256)
    end
    local s = table.concat(out)
    local extra = #s - bytes
    if extra > 0 then
        if s:sub(1, extra):find("[^%z]") then return nil end
        s = s:sub(extra + 1)
    end
    return s
end

-- a >= b (both n limbs)?
local function geq(a, b, n)
    for i = n, 1, -1 do
        if a[i] ~= b[i] then return a[i] > b[i] end
    end
    return true
end

-- a = a - b in place (n limbs, a >= b)
local function sub(a, b, n)
    local borrow = 0
    for i = 1, n do
        local v = a[i] - b[i] - borrow
        if v < 0 then v, borrow = v + B, 1 else borrow = 0 end
        a[i] = v
    end
end

-- Montgomery multiplication: a * b / B^n mod m (a, b < m; np = -m^-1 mod B)
local function montMul(a, b, m, np, n)
    local t = {}
    for j = 1, n + 2 do t[j] = 0 end
    for i = 1, n do
        local ai = a[i]
        -- t += a[i] * b
        local c = 0
        for j = 1, n do
            local x = t[j] + ai * b[j] + c
            c = floor(x / B)
            t[j] = x - c * B
        end
        local x = t[n + 1] + c
        c = floor(x / B)
        t[n + 1] = x - c * B
        t[n + 2] = c
        -- t = (t + q * m) / B, with q chosen so the lowest limb becomes 0
        local q = (t[1] * np) % B
        c = floor((t[1] + q * m[1]) / B)
        for j = 2, n do
            x = t[j] + q * m[j] + c
            c = floor(x / B)
            t[j - 1] = x - c * B
        end
        x = t[n + 1] + c
        c = floor(x / B)
        t[n] = x - c * B
        t[n + 1] = t[n + 2] + c
        t[n + 2] = 0
    end
    -- t < 2m: subtract m once if needed
    if t[n + 1] > 0 or geq(t, m, n) then
        local borrow = 0
        for j = 1, n do
            local v = t[j] - m[j] - borrow
            if v < 0 then v, borrow = v + B, 1 else borrow = 0 end
            t[j] = v
        end
    end
    t[n + 1], t[n + 2] = nil, nil
    return t
end

-- -m^-1 mod B (m odd), by Newton iteration: every round doubles the correct bits
local function negInverse(m0)
    local x = 1
    for _ = 1, 5 do
        x = (x * ((2 - (m0 * x) % B) % B)) % B
    end
    return (B - x) % B
end

-- B^(2n) mod m, by doubling 1 2*24*n times
local function rSquared(m, n)
    local r = {}
    for i = 1, n do r[i] = 0 end
    r[1] = 1
    for _ = 1, 2 * 24 * n do
        local c = 0
        for i = 1, n do
            local v = r[i] * 2 + c
            if v >= B then v, c = v - B, 1 else c = 0 end
            r[i] = v
        end
        if c > 0 or geq(r, m, n) then sub(r, m, n) end
    end
    return r
end

-- s^65537 mod m
local function powE(s, m, n)
    local np = negInverse(m[1])
    local sr = montMul(s, rSquared(m, n), m, np, n) -- s in Montgomery form
    local x = sr
    for _ = 1, 16 do x = montMul(x, x, m, np, n) end
    x = montMul(x, sr, m, np, n)
    local one = { 1 }
    for i = 2, n do one[i] = 0 end
    return montMul(x, one, m, np, n) -- back from Montgomery form
end

-- Does sigHex (hex) sign message for the key with modulus modulusHex (hex)?
-- sha256 = function(data) -> raw 32-byte digest (default: love.data.hash)
function Rsa.verify(modulusHex, message, sigHex, sha256)
    local m = fromHex(modulusHex)
    if not m or m[1] % 2 == 0 then return false end
    local n = #m
    while n > 1 and m[n] == 0 do m[n] = nil; n = n - 1 end
    local k = #(toBytes(m, n, 3 * n):gsub("^%z+", "")) -- modulus length in bytes
    if k < 64 or #sigHex:gsub("%s", "") ~= 2 * k then return false end
    local s = fromHex(sigHex, n)
    if not s or #s > n or geq(s, m, n) then return false end

    local em = toBytes(powE(s, m, n), n, k)
    local hash = (sha256 or function(d) return love.data.hash("sha256", d) end)(message)
    local tail = DIGEST_INFO .. hash
    local expected = "\0\1" .. string.rep("\255", k - 3 - #tail) .. "\0" .. tail
    return em == expected
end

return Rsa
