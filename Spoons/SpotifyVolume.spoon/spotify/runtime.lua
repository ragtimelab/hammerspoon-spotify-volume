local Controller = require("spotify.controller")
local OSDSupervisor = require("spotify.osd_supervisor")
local Transport = require("spotify.transport")
local Runtime = {}
Runtime.__index = Runtime
local module = {}

function module.start(o)
    local hs = assert(o.hs, "Hammerspoon API is required")
    local self = setmetatable({hs = hs, bundleID = o.bundleID or "com.spotify.client",
        logger = o.logger or hs.logger.new("spotify-volume", "warning"),
        buildID = o.buildID or "development", shuttingDown = false}, Runtime)
    self.injectedSpotify = o.spotify ~= nil
    local timerFactory = function(delay, callback) return hs.timer.doAfter(delay, callback) end
    self.supervisor = OSDSupervisor.new({executable = o.helperPath,
        taskFactory = function(...) return hs.task.new(...) end,
        timerFactory = timerFactory, logger = self.logger, protocolVersion = o.protocolVersion or 1,
        buildID = self.buildID,
        killTask = function(task)
            local killer
            killer = hs.task.new("/bin/kill", function() killer = nil end, {"-KILL", tostring(task:pid())})
            if killer then killer:start() end
        end})
    self.transport = o.transport or Transport.new({hs = hs,
        executable = o.controlPath or o.helperPath:gsub("spotify%-osd$", "spotify-control"),
        statePath = o.statePath, buildID = self.buildID})
    local spotify = o.spotify or {
        isRunning = function() return self.spotifyPID ~= nil end,
        getVolume = function(callback) self.transport:request("get", nil, callback) end,
        setVolume = function(volume, callback) self.transport:request("set", volume, callback) end,
    }
    local store = o.store or {
        read = function()
            local f = io.open(o.statePath, "r")
            if not f then return nil end
            local value = tonumber(f:read("*a")); f:close(); return value
        end,
        write = function(segment, callback)
            self.transport:request("write", segment, function(ok, _, err) callback(ok, err) end)
        end,
    }
    self.controller = Controller.new({spotify = spotify, store = store,
        osd = {show = function(segment) self.supervisor:show(segment) end},
        timerFactory = timerFactory, logger = self.logger})
    self.transport.onReady = function()
        if not self.shuttingDown then self.controller:synchronize() end
    end
    self.watcher = hs.application.watcher.new(function(_, kind, application)
        if self.shuttingDown then return end
        if kind == hs.application.watcher.launched or kind == hs.application.watcher.terminated then
            if application and application:bundleID() == self.bundleID then self:_reconcileSpotify() end
        end
    end)
    self.watcher:start()
    self:_reconcileSpotify()
    return self
end
function Runtime:_reconcileSpotify()
    if self.shuttingDown then return false end
    local application = self.hs.application.get(self.bundleID)
    local pid = application and application:pid() or nil
    if pid ~= self.spotifyPID then
        self.controller:spotifyStopped()
        self.spotifyPID = pid
        self.transport:setPID(pid)
        -- A new Spotify generation also resets an exhausted HUD supervisor.
        self.supervisor:setDesiredRunning(false)
        self.supervisor:setDesiredRunning(pid ~= nil)
        if pid and self.injectedSpotify then self.controller:synchronize() end
    end
    return pid ~= nil
end
function Runtime:pressed(delta)
    self:_reconcileSpotify(); return self.controller:pressed(delta)
end
function Runtime:repeated(delta)
    self:_reconcileSpotify(); return self.controller:repeated(delta)
end
function Runtime:released() return self.controller:released() end
function Runtime:shutdown()
    if self.shuttingDown then return end
    self.shuttingDown = true
    self.watcher:stop(); self.controller:shutdown()
    self.transport:shutdown(); self.supervisor:shutdown()
end
function Runtime:status()
    return {spotify = {running = self.spotifyPID ~= nil, pid = self.spotifyPID},
        helper = self.supervisor:status(), control = self.transport:status(),
        volume = self.controller:status(), buildID = self.buildID,
        hammerspoonPID = self.hs.processInfo and self.hs.processInfo.processID or nil}
end
return module
