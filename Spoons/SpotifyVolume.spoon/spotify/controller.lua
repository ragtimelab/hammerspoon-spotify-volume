local Controller = {}
Controller.__index = Controller
local module = {}
function module.clampSegment(v) return math.max(0, math.min(16, v)) end
function module.segmentToVolume(v) return math.floor(module.clampSegment(v) * 100 / 16 + 0.5) end
function module.volumeToSegment(v) return module.clampSegment(math.floor(v * 16 / 100 + 0.5)) end

function module.new(o)
    return setmetatable({spotify = o.spotify, store = o.store, osd = o.osd,
        timerFactory = o.timerFactory, logger = o.logger,
        currentSegment = module.clampSegment(math.floor((tonumber(o.store.read()) or 8) + 0.5)),
        queue = {}, generation = 0, nextGesture = 0, synchronized = false,
        failed = {}, processing = false}, Controller)
end
function Controller:_stopWriteTimer()
    if self.writeTimer then self.writeTimer:stop(); self.writeTimer = nil end
end
function Controller:_persist()
    self:_stopWriteTimer()
    if not self.dirty then return end
    local segment, generation = self.currentSegment, self.generation
    self.store.write(segment, function(ok, err)
        if generation ~= self.generation then return end
        if ok then
            if self.currentSegment == segment then self.dirty = false end
        else self.lastError = err or "state-write-failed" end
    end)
end
function Controller:_schedulePersist()
    self:_stopWriteTimer()
    self.writeTimer = self.timerFactory(0.25, function() self.writeTimer = nil; self:_persist() end)
end
function Controller:_enqueue(event)
    if #self.queue >= 4096 then
        self.lastError = "input-queue-overflow"; self.failed[event.gesture] = true
        return false, self.lastError
    end
    self.queue[#self.queue + 1] = event; self:_pump(); return true
end
function Controller:pressed(delta)
    if not self.spotify.isRunning() then return false, "spotify-not-running" end
    self.nextGesture = self.nextGesture + 1; self.activeGesture = self.nextGesture
    return self:_enqueue({kind = "press", delta = delta, gesture = self.activeGesture})
end
function Controller:repeated(delta)
    if not self.activeGesture then return false, "no-active-press" end
    return self:_enqueue({kind = "repeat", delta = delta, gesture = self.activeGesture})
end
function Controller:released()
    local gesture = self.activeGesture; self.activeGesture = nil
    if gesture then return self:_enqueue({kind = "release", gesture = gesture}) end
end
function Controller:_pump()
    if self.processing then return end
    local event = table.remove(self.queue, 1)
    if not event then return end
    if event.kind == "release" then
        self.failed[event.gesture] = nil; self:_persist(); self:_pump(); return
    end
    if self.failed[event.gesture] then self:_pump(); return end
    self.processing = true
    local generation = self.generation
    local function finish(ok, segment, changed, err)
        if generation ~= self.generation then return end
        self.processing = false
        if ok then
            self.currentSegment = segment; self.synchronized = true
            self.lastError = nil
            if changed then self.dirty = true; self:_schedulePersist() end
            self.osd.show(segment)
        else
            self.failed[event.gesture] = true; self.synchronized = false
            self.lastError = err or "spotify-request-failed"
        end
        self:_pump()
    end
    local function step(oldSegment)
        if generation ~= self.generation then return end
        local nextSegment = module.clampSegment(oldSegment + event.delta)
        if nextSegment == oldSegment then finish(true, nextSegment, false); return end
        self.spotify.setVolume(module.segmentToVolume(nextSegment), function(ok, _, err)
            finish(ok, nextSegment, true, err)
        end)
    end
    if event.kind == "press" then
        self.spotify.getVolume(function(ok, volume, err)
            if generation ~= self.generation then return end
            if not ok or type(volume) ~= "number" or volume < 0 or volume > 100 then
                finish(false, nil, false, err or "invalid-volume")
            else step(module.volumeToSegment(volume)) end
        end)
    elseif self.synchronized then step(self.currentSegment)
    else finish(false, nil, false, "not-synchronized") end
end
function Controller:synchronize()
    if self.processing or #self.queue > 0 then return end
    local generation, gesture = self.generation, self.nextGesture
    self.spotify.getVolume(function(ok, volume, err)
        if generation ~= self.generation or gesture ~= self.nextGesture then return end
        if ok and type(volume) == "number" and volume >= 0 and volume <= 100 then
            self.currentSegment = module.volumeToSegment(volume); self.synchronized = true
            self.lastError = nil
        else self.lastError = err end
    end)
end
function Controller:spotifyStopped()
    self:_persist(); self.generation = self.generation + 1
    self.queue = {}; self.failed = {}; self.activeGesture = nil
    self.processing = false; self.synchronized = false
end
function Controller:shutdown() self:spotifyStopped() end
function Controller:status()
    return {segment = self.currentSegment, persistencePending = self.writeTimer ~= nil or self.dirty == true,
        synchronized = self.synchronized, queued = #self.queue, processing = self.processing, lastError = self.lastError}
end
return module
