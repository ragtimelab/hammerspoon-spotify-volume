local Runtime = require("spotify.runtime")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(string.format(
            "%s: expected %s, got %s",
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ), 2)
    end
end

local function makeApplication(pid)
    return {
        pid = function() return pid end,
        bundleID = function() return "com.spotify.client" end,
    }
end

local function makeContext(initialPID)
    local context = {
        order = {},
        currentApplication = initialPID and makeApplication(initialPID) or nil,
        tasks = {},
        timers = {},
        writes = {},
        watcherStops = 0,
    }

    local watcherConstants = {
        launched = 1,
        terminated = 2,
    }

    local hs = {
        inspect = tostring,
        logger = {
            new = function()
                return {ef = function() end}
            end,
        },
        application = {
            get = function()
                context.order[#context.order + 1] = "application-get"
                return context.currentApplication
            end,
            watcher = watcherConstants,
        },
        timer = {
            doAfter = function(delay, callback)
                local timer = {
                    delay = delay,
                    stopped = false,
                    stop = function(self) self.stopped = true end,
                    fire = function(self)
                        if not self.stopped then
                            self.stopped = true
                            callback()
                        end
                    end,
                }
                context.timers[#context.timers + 1] = timer
                return timer
            end,
        },
        task = {
            new = function(_, terminationCallback, streamCallback)
                local task = {
                    running = false,
                    closed = false,
                    terminated = false,
                    inputs = {},
                    start = function(self)
                        self.running = true
                        context.order[#context.order + 1] = "task-start"
                        return true
                    end,
                    closeInput = function(self)
                        self.closed = true
                        return self
                    end,
                    terminate = function(self)
                        self.running = false
                        self.terminated = true
                        return self
                    end,
                    isRunning = function(self) return self.running end,
                    setInput = function(self, input)
                        self.inputs[#self.inputs + 1] = input
                        return self
                    end,
                    pid = function() return 9000 + #context.tasks end,
                    exit = function(self, code)
                        self.running = false
                        terminationCallback(code or 0, "", "")
                    end,
                    emit = function(self, output)
                        streamCallback(self, output, "")
                    end,
                }
                context.tasks[#context.tasks + 1] = task
                return task
            end,
        },
    }

    hs.application.watcher.new = function(callback)
        context.order[#context.order + 1] = "watcher-new"
        local watcher = {
            callback = callback,
            started = false,
            start = function(self)
                self.started = true
                context.order[#context.order + 1] = "watcher-start"
                return self
            end,
            stop = function(self)
                if self.started then
                    context.watcherStops = context.watcherStops + 1
                end
                self.started = false
            end,
            emit = function(self, eventType, application)
                callback(nil, eventType, application)
            end,
        }
        context.watcher = watcher
        return watcher
    end

    local spotify = {
        isRunning = function() return context.currentApplication ~= nil end,
        getVolume = function(cb) cb(true, 50) end,
        pressStep = function() return true, 9, true end,
        setVolume = function(_, cb) cb(true) end,
    }

    context.runtime = Runtime.start({
        hs = hs,
        osascript = {},
        helperPath = "/test/spotify-osd",
        statePath = "/test/state",
        spotify = spotify,
        transport = {setPID = function() end, shutdown = function() end, status = function() return {} end},
        store = {
            read = function() return 8 end,
            write = function(segment, cb)
                context.writes[#context.writes + 1] = segment
                cb(true)
            end,
        },
    })
    context.hs = hs
    return context
end

return {
    name = "runtime",
    tests = {
        {
            name = "watcher starts before initial process snapshot",
            run = function()
                local context = makeContext(100)
                equal(context.order[1], "watcher-new", "first operation")
                equal(context.order[2], "watcher-start", "second operation")
                equal(context.order[3], "application-get", "third operation")
                equal(#context.tasks, 1, "eager helper count")
                equal(context.runtime:status().spotify.pid, 100, "initial Spotify PID")
            end,
        },
        {
            name = "late termination for an old PID is ignored",
            run = function()
                local context = makeContext(100)
                local oldApplication = context.currentApplication
                local newApplication = makeApplication(200)
                context.currentApplication = newApplication
                context.watcher:emit(context.hs.application.watcher.launched, newApplication)
                context.watcher:emit(context.hs.application.watcher.terminated, oldApplication)
                equal(context.runtime:status().spotify.pid, 200, "replacement PID")
                equal(context.runtime:status().helper.desiredRunning, true, "helper desired state")
                equal(#context.tasks, 1, "helper was not duplicated")
            end,
        },
        {
            name = "current termination stops helper and persists state",
            run = function()
                local context = makeContext(100)
                local application = context.currentApplication
                context.currentApplication = nil
                context.watcher:emit(context.hs.application.watcher.terminated, application)
                equal(context.runtime:status().spotify.running, false, "Spotify stopped")
                equal(context.runtime:status().helper.desiredRunning, false, "helper stopped")
                equal(context.tasks[1].closed, true, "helper stdin closed")
                equal(#context.writes, 0, "unchanged state needs no write")
            end,
        },
        {
            name = "shutdown is idempotent and stops watcher once",
            run = function()
                local context = makeContext(100)
                context.runtime:shutdown()
                context.runtime:shutdown()
                equal(context.watcherStops, 1, "watcher stop count")
                equal(context.tasks[1].closed, true, "helper stdin closed")
                equal(#context.writes, 0, "unchanged shutdown state")
            end,
        },
    },
}
