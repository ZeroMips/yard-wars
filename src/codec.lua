-- Compact serializer for network messages: nil/booleans/numbers/strings and nested
-- tables. Decoding is a plain parser (never runs received data as code) and returns
-- nil on malformed input.
--   number  "n" .. digits .. ";"   (6 significant digits: 0.1px precision in the arena)
--   string  "s" .. length .. ":" .. bytes
--   true/false "T"/"F"
--   table   "{" .. key value ... .. "}"
local Codec = {}

local fmt, concat, sub, find, byte = string.format, table.concat, string.sub, string.find, string.byte

local function encode(v, out)
    local t = type(v)
    if t == "number" then
        if v == math.floor(v) and v > -1e15 and v < 1e15 then
            out[#out + 1] = fmt("n%d;", v)
        else
            out[#out + 1] = fmt("n%.6g;", v)
        end
    elseif t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        out[#out + 1] = "{"
        for k, x in pairs(v) do
            local kt, xt = type(k), type(x)
            if (kt == "number" or kt == "string") and xt ~= "function" and xt ~= "userdata" then
                encode(k, out)
                encode(x, out)
            end
        end
        out[#out + 1] = "}"
    else
        error("codec: cannot encode " .. t)
    end
end

function Codec.encode(v)
    local out = {}
    encode(v, out)
    return concat(out)
end

local B_N, B_S, B_T, B_F, B_OPEN, B_CLOSE = byte("n"), byte("s"), byte("T"), byte("F"),
    byte("{"), byte("}")

-- Returns value, next position (or nil on error)
local function decode(s, i, depth)
    local c = byte(s, i)
    if c == B_N then
        local j = find(s, ";", i + 1, true)
        if not j then return nil end
        local n = tonumber(sub(s, i + 1, j - 1))
        if not n then return nil end
        return n, j + 1
    elseif c == B_S then
        local j = find(s, ":", i + 1, true)
        if not j then return nil end
        local len = tonumber(sub(s, i + 1, j - 1))
        if not len or j + len > #s then return nil end
        return sub(s, j + 1, j + len), j + len + 1
    elseif c == B_T then
        return true, i + 1
    elseif c == B_F then
        return false, i + 1
    elseif c == B_OPEN then
        if depth > 16 then return nil end
        local t = {}
        i = i + 1
        while byte(s, i) ~= B_CLOSE do
            if i > #s then return nil end
            local k, v
            k, i = decode(s, i, depth + 1)
            if k == nil then return nil end
            v, i = decode(s, i, depth + 1)
            if v == nil then return nil end
            t[k] = v
        end
        return t, i + 1
    end
    return nil
end

function Codec.decode(s)
    if type(s) ~= "string" or #s == 0 then return nil end
    local v, i = decode(s, 1, 0)
    if i ~= #s + 1 then return nil end
    return v
end

return Codec
