local C = require("spotify.controller")
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function context()
    local x = {volume = 50, running = true, requests = {}, shows = {}, writes = {}, sets = {}, timers = {}}
    x.c = C.new({spotify = {
        isRunning = function() return x.running end,
        getVolume = function(cb) x.requests[#x.requests + 1] = {kind = "get", cb = cb} end,
        setVolume = function(value, cb) x.requests[#x.requests + 1] = {kind = "set", value = value, cb = cb} end,
    }, store = {read = function() return 8 end,
        write = function(v, cb) x.writes[#x.writes + 1] = v; cb(not x.failWrite, "disk-error") end},
        osd = {show = function(v) x.shows[#x.shows + 1] = v end},
        timerFactory = function(delay, cb)
            local t = {delay = delay, cb = cb, stop = function(self) self.stopped = true end}
            x.timers[#x.timers + 1] = t; return t
        end})
    function x:reply(ok)
        local r = table.remove(self.requests, 1); assert(r)
        if ok == false then r.cb(false, nil, "failure"); return end
        if r.kind == "set" then self.volume = r.value; self.sets[#self.sets + 1] = r.value end
        r.cb(true, self.volume)
    end
    function x:drain() while #self.requests > 0 do self:reply() end end
    return x
end
return {name = "controller", tests = {
    {name = "all original segment mappings round trip", run = function()
        local expected = {0,6,13,19,25,31,38,44,50,56,63,69,75,81,88,94,100}
        for n = 0,16 do eq(C.segmentToVolume(n), expected[n+1]); eq(C.volumeToSegment(expected[n+1]), n) end
        eq(C.clampSegment(-1), 0); eq(C.clampSegment(17), 16)
    end},
    {name = "press and repeats return before Spotify replies and preserve FIFO after release", run = function()
        local x = context(); x.c:pressed(1)
        for _ = 1,4 do x.c:repeated(1) end
        x.c:released(); eq(#x.requests, 1); eq(#x.shows, 0)
        x:drain(); eq(x.volume, 81); eq(#x.sets, 5); eq(x.writes[1], 13)
        for n = 1,5 do eq(x.shows[n], 8+n) end
        eq(x.c:repeated(1), false)
    end},
    {name = "press failure cannot apply stale cached repeats", run = function()
        local x = context(); x.volume = 90
        x.c:pressed(-1); x.c:repeated(-1); x.c:released(); x:reply(false)
        eq(x.volume, 90); eq(#x.sets, 0); eq(#x.shows, 0)
        x.c:pressed(-1); x:drain(); eq(x.volume, 81)
    end},
    {name = "uncertain write is never retried and next press resynchronizes", run = function()
        local x = context(); x.c:pressed(1); x.c:repeated(1); x:reply()
        x.volume = 56; x:reply(false)
        eq(#x.requests, 0); eq(#x.shows, 0)
        x.c:released(); x.c:pressed(1); x:drain(); eq(x.volume, 63)
    end},
    {name = "alternating input order and independent press resynchronization", run = function()
        local x = context(); x.c:pressed(1); x.c:repeated(-1); x.c:released()
        x.c:pressed(-1); x:drain()
        eq(x.shows[1], 9); eq(x.shows[2], 8); eq(x.shows[3], 7)
    end},
    {name = "boundaries retain HUD without redundant writes", run = function()
        for _, volume in ipairs({0,100}) do
            local x = context(); x.volume = volume
            local d = volume == 0 and -1 or 1
            x.c:pressed(d); x.c:repeated(d); x:drain()
            eq(#x.sets, 0); eq(#x.shows, 2)
        end
    end},
    {name = "old generation responses cannot commit state", run = function()
        local x = context(); x.c:pressed(1); x:reply(); x.c:spotifyStopped(); x:reply()
        eq(#x.shows, 0); eq(x.c:status().segment, 8)
    end},
    {name = "startup read cannot overwrite a later gesture", run = function()
        local x = context(); x.c:synchronize(); x.c:pressed(1)
        x:drain(); eq(x.c:status().segment, 9)
    end},
    {name = "absence and storage errors are explicit", run = function()
        local x = context(); x.running = false; eq(x.c:pressed(1), false); eq(#x.requests,0)
        x.running = true; x.failWrite = true; x.c:pressed(1); x:drain(); x.c:released()
        eq(x.c:status().lastError, "disk-error"); eq(x.c:status().persistencePending, true)
    end},
    {name = "input overflow is bounded and visible", run = function()
        local x = context(); x.c:pressed(1)
        for _ = 1,4096 do x.c:repeated(1) end
        eq(x.c:repeated(1), false); eq(#x.c.queue, 4096)
        eq(x.c:status().lastError, "input-queue-overflow")
    end},
}}
