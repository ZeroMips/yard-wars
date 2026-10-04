-- Update check, run as a love.thread by src/updater.lua (so the lobby never waits for the
-- network). Reports over the "updater" channel: "uptodate", "bad <build>" (crashed here
-- before, not used again), "downloading <build>",
-- "ready <build> <file in the save folder>" or "failed <why>".
require("love.filesystem")
require("love.data")
local url, own, badList, publicKey = ...
local channel = love.thread.getChannel("updater")

local function fail(why) error({ why = why }) end

local function check()
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local Rsa = require("src.rsa")
    http.TIMEOUT = 5

    -- No redirects: an http -> https redirect can't be followed anyway
    local function get(u)
        local parts = {}
        local ok, code = http.request({ url = u, sink = ltn12.sink.table(parts), redirect = false })
        if not ok then fail(tostring(code)) end
        if code ~= 200 then fail("HTTP " .. tostring(code)) end
        return table.concat(parts)
    end

    local manifest = get(url .. "latest.txt")
    local signed, sig = manifest:match("^(.-\n)sig (%x+)%s*$")
    if not signed or not Rsa.verify(publicKey, signed, sig) then fail("bad signature") end
    local m = {}
    for line in signed:gmatch("[^\n]+") do
        local key, value = line:match("^(%w+) (.*)$")
        if key then m[key] = value end
    end
    local build, size = tonumber(m.build), tonumber(m.size)
    local file, sha = m.file and m.file:match("^[%w%-%.]+%.love$"), m.sha256
    if not (build and size and file and sha) then fail("bad manifest") end

    if build <= own then channel:push("uptodate") return end
    for b in badList:gmatch("%d+") do
        if tonumber(b) == build then channel:push("bad " .. build) return end -- crashed before
    end

    channel:push("downloading " .. build)
    local data = get(url .. file)
    if #data ~= size then fail("wrong size") end
    if love.data.encode("string", "hex", love.data.hash("sha256", data)) ~= sha:lower() then
        fail("wrong checksum")
    end
    local name = "update-" .. build .. ".love"
    local ok, err = love.filesystem.write(name, data)
    if not ok then fail("can't save: " .. tostring(err)) end
    channel:push("ready " .. build .. " " .. name)
end

local ok, err = pcall(check)
if not ok then
    channel:push("failed " .. (type(err) == "table" and err.why or tostring(err)))
end
