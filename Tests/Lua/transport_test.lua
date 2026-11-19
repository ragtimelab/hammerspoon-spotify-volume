local Transport = require("spotify.transport")
local function eq(a,b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function context()
    local c = {tasks = {}, timers = {}, messages = {}, results = {}}
    local hs = {json = {
        encode = function(m) c.sent = m; return "request" end,
        decode = function(s) return assert(c.messages[s], "invalid JSON") end,
    }, timer = {doAfter = function(delay, cb)
        local timer = {delay = delay, cb = cb, stop = function(t) t.stopped = true end}
        c.timers[#c.timers + 1] = timer; return timer
    end}, task = {new = function(_, done, stream)
        local t = {inputs = {}, running = false,
            start = function(t) t.running = true; return true end,
            closeInput = function(t) t.closed = true end,
            terminate = function(t) t.terminated = true end,
            isRunning = function(t) return t.running end,
            pid = function() return 9001 end,
            setInput = function(t, input) t.inputs[#t.inputs+1] = input end,
            emit = function(t, input) stream(t, input, "") end,
            exit = function(t) t.running = false; done(0,"","") end,
            late = function() stream(nil, "late\n", "") end}
        c.tasks[#c.tasks+1] = t; return t
    end}}
    c.t = Transport.new({hs = hs, executable = "/test/control", statePath = "/test/state", buildID = "test"})
    c.t:setPID(100)
    function c:message(name, message)
        self.messages[name] = message; self.tasks[#self.tasks]:emit(name .. "\n")
    end
    function c:ready() self:message("ready", {ready=1, buildID="test"}) end
    function c:request() self.t:request("get", nil, function(ok,v,err) self.results[#self.results+1] = {ok,v,err} end) end
    function c:timer(delay)
        for i=#self.timers,1,-1 do local t=self.timers[i]; if not t.stopped and t.delay==delay then t.cb(); return end end
        error("timer missing")
    end
    return c
end
return {name="transport", tests={
    {name="one request in flight prevents setInput replacement", run=function()
        local c=context(); c:request(); c:request(); eq(#c.tasks[1].inputs,0); c:ready()
        eq(#c.tasks[1].inputs,1)
        c:message("reply1",{id=c.sent.id,generation=1,ok=true,value=50})
        eq(#c.tasks[1].inputs,2); eq(#c.results,1)
    end},
    {name="fragmented frames wait for newline", run=function()
        local c=context(); c.messages.ready={ready=1,buildID="test"}
        c.tasks[1]:emit("rea"); eq(c.t.ready,false)
        c.tasks[1]:emit("dy\n"); eq(c.t.ready,true)
    end},
    {name="wrong identity fails without replay", run=function()
        local c=context(); c:ready(); c:request()
        c:message("wrong",{id=999,generation=1,ok=true,value=50})
        eq(c.results[1][1],false); eq(c.tasks[1].closed,true); eq(#c.tasks[1].inputs,1)
    end},
    {name="readiness failures use finite restart budget", run=function()
        local c=context()
        for n=1,4 do
            c:timer(5); c.tasks[n]:exit()
            if n<4 then c:timer(({0.25,1,4})[n]) end
        end
        eq(#c.tasks,4); eq(c.t.failureCount,4)
    end},
    {name="timeout fails queued requests without replay", run=function()
        local c=context(); c:ready(); c:request(); c:request(); c:timer(125)
        eq(#c.results,2); eq(c.results[1][1],false); eq(c.tasks[1].closed,true)
    end},
    {name="generation change waits for old worker exit and ignores late callbacks", run=function()
        local c=context(); c:ready(); c:request(); c.t:setPID(200)
        eq(#c.tasks,1); eq(c.results[1][1],false)
        c.tasks[1]:exit(); eq(#c.tasks,2)
        c.tasks[1]:late(); eq(c.t.lastError,"control-exited")
        c:ready(); eq(c.t.pid,200)
    end},
    {name="frame overflow closes worker", run=function()
        local c=context(); c.tasks[1]:emit(string.rep("x",65537))
        eq(c.tasks[1].closed,true); eq(c.t.lastError,"control-buffer-overflow")
    end},
}}
