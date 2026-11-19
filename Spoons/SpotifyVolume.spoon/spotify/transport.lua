local T = {}
T.__index = T
function T.new(o)
    return setmetatable({hs = o.hs, executable = o.executable, statePath = o.statePath,
        buildID = o.buildID, generation = 0, nextID = 0, queue = {}, buffer = "",
        ready = false, stopping = false, failureCount = 0}, T)
end
function T:_cancel(field)
    if self[field] then self[field]:stop(); self[field] = nil end
end
function T:_fail(reason)
    self.lastError = reason; self.ready = false
    self:_cancel("requestTimer"); self:_cancel("readyTimer"); self:_cancel("stableTimer")
    local requests, pending = self.queue, self.pending
    self.queue = {}; self.pending = nil
    -- Block reentrant submissions from failure callbacks until cleanup finishes.
    self.failing = true
    if pending then pending.callback(false, nil, reason) end
    for _, r in ipairs(requests) do r.callback(false, nil, reason) end
    self.failing = false
end
function T:_close(failed)
    local task = self.task
    if not task or self.stopping then return end
    self.stopping = true; self.stopFailed = failed == true
    task:closeInput()
    self.stopTimer = self.hs.timer.doAfter(0.25, function()
        if self.task == task and task:isRunning() then
            task:terminate()
            self.killTimer = self.hs.timer.doAfter(0.25, function()
                if self.task == task and task:isRunning() then
                    self.killer = self.hs.task.new("/bin/kill", function() self.killer = nil end,
                        {"-KILL", tostring(task:pid())})
                    if self.killer then self.killer:start() end
                end
            end)
        end
    end)
end
function T:setPID(pid)
    if self.desiredPID == pid then return end
    self.desiredPID = pid; self.generation = self.generation + 1; self.failureCount = 0
    self:_cancel("restartTimer"); self:_fail("spotify-generation-changed")
    if self.task then self:_close(false) else self:_start() end
end
function T:_restartFailure()
    self.failureCount = self.failureCount + 1
    local delay = ({0.25, 1, 4})[self.failureCount]
    if delay and self.desiredPID then
        self.restartTimer = self.hs.timer.doAfter(delay, function()
            self.restartTimer = nil; self:_start()
        end)
    end
end
function T:_start()
    if self.task or not self.desiredPID or self.restartTimer or self.failureCount > 3 then return end
    self.pid = self.desiredPID; self.buffer = ""; self.stopping = false
    local generation, task = self.generation
    task = self.hs.task.new(self.executable, function()
        if self.task ~= task then return end
        local failed = not self.stopping or self.stopFailed
        self:_cancel("stopTimer"); self:_cancel("killTimer")
        self.task = nil; self:_fail("control-exited"); self.stopping = false
        if failed and generation == self.generation then self:_restartFailure() else self:_start() end
    end, function(streamTask, stdout, stderr)
        if streamTask and self.task == task and generation == self.generation and not self.stopping then
            if stderr and stderr ~= "" then self.lastError = stderr:sub(1, 1024) end
            self:_consume(stdout or "")
        end
        return true
    end, {"--server", tostring(self.pid), self.statePath, self.buildID})
    self.task = task
    if not task or not task:start() then
        self.task = nil; self:_fail("control-start-failed"); self:_restartFailure(); return
    end
    self.readyTimer = self.hs.timer.doAfter(5, function()
        self:_fail("control-ready-timeout"); self:_close(true)
    end)
end
function T:_consume(data)
    self.buffer = self.buffer .. data
    if #self.buffer > 65536 then self:_fail("control-buffer-overflow"); self:_close(true); return end
    while true do
        local e = self.buffer:find("\n", 1, true)
        if not e then return end
        local line = self.buffer:sub(1, e - 1); self.buffer = self.buffer:sub(e + 1)
        local ok, m = pcall(self.hs.json.decode, line)
        if not ok or type(m) ~= "table" then self:_fail("control-invalid-json"); self:_close(true); return end
        if m.busy then
            self:_fail("control-busy"); self:_close(true); return
        elseif m.ready then
            if m.ready ~= 1 or m.buildID ~= self.buildID or self.ready then
                self:_fail("control-protocol-mismatch"); self:_close(true); return
            end
            self.ready = true; self:_cancel("readyTimer")
            self.lastError = nil
            self.stableTimer = self.hs.timer.doAfter(30, function() self.failureCount = 0 end)
            if self.onReady then self.onReady() end
            self:_dispatch()
        elseif self.pending and m.id == self.pending.id and m.generation == self.generation
            and type(m.ok) == "boolean" then
            self:_cancel("requestTimer")
            local r = self.pending; self.pending = nil
            if not m.ok then self.lastError = m.error end
            r.callback(m.ok, m.value, m.error); self:_dispatch()
        else self:_fail("control-unexpected-reply"); self:_close(true); return end
    end
end
function T:request(operation, value, callback)
    if not self.desiredPID or self.stopping or self.failing or self.failureCount > 3 then
        callback(false, nil, "control-unavailable"); return
    end
    if #self.queue >= 4096 then callback(false, nil, "control-queue-overflow"); return end
    self.nextID = self.nextID + 1
    self.queue[#self.queue + 1] = {id = self.nextID, operation = operation, value = value, callback = callback}
    self:_start(); self:_dispatch()
end
function T:_dispatch()
    if not self.ready or self.pending or self.stopping then return end
    local r = table.remove(self.queue, 1)
    if not r then return end
    self.pending = r
    self.task:setInput(self.hs.json.encode({id = r.id, generation = self.generation,
        pid = self.pid, operation = r.operation, value = r.value}) .. "\n")
    self.requestTimer = self.hs.timer.doAfter(125, function()
        self:_fail("control-response-timeout"); self:_close(true)
    end)
end
function T:shutdown() self:setPID(nil) end
function T:status()
    return {ready = self.ready, pid = self.task and self.task:pid() or nil,
        targetPID = self.pid, generation = self.generation, buildID = self.buildID,
        pending = self.pending ~= nil, queued = #self.queue, stopping = self.stopping,
        lastError = self.lastError, restartAttempts = self.failureCount}
end
return T
