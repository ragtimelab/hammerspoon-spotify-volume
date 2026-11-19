local Supervisor = {}
Supervisor.__index = Supervisor

local module = {}

local function logError(logger, formatString, ...)
    if not logger then
        return
    end
    if logger.ef then
        logger.ef(formatString, ...)
    elseif logger.e then
        logger.e(string.format(formatString, ...))
    end
end

function module.new(options)
    assert(type(options) == "table", "OSD supervisor options are required")
    assert(type(options.executable) == "string", "OSD executable is required")
    assert(type(options.taskFactory) == "function", "task factory is required")
    assert(type(options.timerFactory) == "function", "timer factory is required")

    return setmetatable({
        executable = options.executable,
        taskFactory = options.taskFactory,
        timerFactory = options.timerFactory,
        logger = options.logger,
        protocolVersion = options.protocolVersion or 1,
        expectedBuildID = options.buildID,
        ackTimeout = options.ackTimeout or 0.5,
        stopGrace = options.stopGrace or 0.25,
        stableDuration = options.stableDuration or 30,
        busyDelay = options.busyDelay or 0.1,
        readyTimeout = options.readyTimeout or 5,
        killTask = options.killTask,
        restartDelays = options.restartDelays or {0.25, 1, 4},

        desiredRunning = false,
        state = "stopped",
        task = nil,
        stoppingTask = nil,
        generation = 0,
        ready = false,
        inFlight = false,
        pendingSegment = nil,
        outputBuffer = "",
        busySeen = false,
        failureCount = 0,
        failureAfterStop = nil,

        ackTimer = nil,
        stopTimer = nil,
        stableTimer = nil,
        restartTimer = nil,
    }, Supervisor)
end

function Supervisor:_cancelTimer(field)
    local timer = self[field]
    if timer then
        timer:stop()
        self[field] = nil
    end
end

function Supervisor:_clearProtocolState()
    self:_cancelTimer("readyTimer")
    self:_cancelTimer("ackTimer")
    self:_cancelTimer("stableTimer")
    self.ready = false
    self.inFlight = false
    self.outputBuffer = ""
    self.busySeen = false
end

function Supervisor:_finishStopping(task)
    if self.stoppingTask ~= task then
        return
    end
    self:_cancelTimer("stopTimer")
    self:_cancelTimer("killTimer")
    self.stoppingTask = nil
    self.state = "stopped"
    local failure = self.failureAfterStop
    self.failureAfterStop = nil
    if failure and self.desiredRunning then
        self:_handleFailure(failure, false)
    else
        self:_reconcile()
    end
end

function Supervisor:_scheduleRestart(delay)
    self:_cancelTimer("restartTimer")
    self.state = "stopped"
    self.restartTimer = self.timerFactory(delay, function()
        self.restartTimer = nil
        self:_reconcile()
    end)
end

function Supervisor:_handleFailure(reason, busy)
    if not self.desiredRunning then
        self.state = "stopped"
        return
    end

    self.failureCount = self.failureCount + 1
    logError(self.logger, "spotify-osd failure %d: %s", self.failureCount, tostring(reason))

    local delay = self.restartDelays[self.failureCount]
    if delay then
        self:_scheduleRestart(delay)
    else
        self:_cancelTimer("restartTimer")
        self.state = "faulted"
        self.pendingSegment = nil
    end
end

function Supervisor:_taskExited(task, generation, exitCode, stdErr)
    if self.stoppingTask == task then
        self:_finishStopping(task)
        return
    end

    if self.task ~= task or self.generation ~= generation then
        return
    end

    local busy = self.busySeen or exitCode == 75
    self.task = nil
    self:_clearProtocolState()
    self.state = "stopped"
    self:_handleFailure(stdErr ~= "" and stdErr or ("exit code " .. tostring(exitCode)), busy)
end

function Supervisor:_handleLine(line, task, generation)
    if self.task ~= task or self.generation ~= generation then
        return
    end

    local readyVersion = line:match("^READY (%d+)")
    if readyVersion then
        local buildID = line:match("^READY %d+ ([%w%._+%-]+)$")
        if tonumber(readyVersion) ~= self.protocolVersion
            or (self.expectedBuildID and buildID ~= self.expectedBuildID) then
            self.failureAfterStop = string.format(
                "protocol mismatch: expected %d, got %s",
                self.protocolVersion,
                readyVersion
            )
            self:_stopActive()
            return
        end
        self.ready = true
        self.buildID = buildID
        self:_cancelTimer("readyTimer")
        self.state = "ready"
        self:_cancelTimer("stableTimer")
        self.stableTimer = self.timerFactory(self.stableDuration, function()
            self.stableTimer = nil
            if self.task == task and self.generation == generation and self.ready then
                self.failureCount = 0
            end
        end)
        self:_dispatch()
    elseif line == "BUSY" then
        self.busySeen = true
    elseif line:match("^OK %d+$") then
        self:_cancelTimer("ackTimer")
        self.inFlight = false
        self:_dispatch()
    elseif line:match("^ERR ") then
        self:_cancelTimer("ackTimer")
        self.inFlight = false
        logError(self.logger, "%s", line)
        self:_dispatch()
    end
end

function Supervisor:_consumeOutput(stdOut, task, generation)
    self.outputBuffer = self.outputBuffer .. stdOut
    if #self.outputBuffer > 65536 then
        self.failureAfterStop = "helper output overflow"
        self:_stopActive()
        return
    end
    while true do
        local newline = self.outputBuffer:find("\n", 1, true)
        if not newline then
            return
        end
        local line = self.outputBuffer:sub(1, newline - 1):gsub("\r$", "")
        self.outputBuffer = self.outputBuffer:sub(newline + 1)
        self:_handleLine(line, task, generation)
    end
end

function Supervisor:_start()
    if not self.desiredRunning or self.task or self.stoppingTask or self.state == "faulted" then
        return false
    end

    self:_cancelTimer("restartTimer")
    self.generation = self.generation + 1
    local generation = self.generation
    self.state = "starting"
    self:_clearProtocolState()

    local task
    task = self.taskFactory(
        self.executable,
        function(exitCode, _, stdErr)
            self:_taskExited(task, generation, exitCode, stdErr or "")
        end,
        function(streamTask, stdOut, stdErr)
            if stdErr and stdErr ~= "" then
                logError(self.logger, "spotify-osd: %s", stdErr:gsub("%s+$", ""))
            end
            if streamTask and stdOut and stdOut ~= "" then
                self:_consumeOutput(stdOut, task, generation)
            end
            return true
        end,
        {"--server"}
    )

    if not task then
        self.state = "stopped"
        self:_handleFailure("task creation failed", false)
        return false
    end

    self.task = task
    if not task:start() then
        self.task = nil
        self.state = "stopped"
        self:_handleFailure("task start failed", false)
        return false
    end
    self.readyTimer = self.timerFactory(self.readyTimeout, function()
        if self.task == task and not self.ready then
            self.failureAfterStop = "helper READY timeout"
            self:_stopActive()
        end
    end)
    return true
end

function Supervisor:_stopActive()
    self:_cancelTimer("readyTimer")
    self:_cancelTimer("restartTimer")
    self:_cancelTimer("stableTimer")
    self:_cancelTimer("ackTimer")
    self.pendingSegment = nil
    self.ready = false
    self.inFlight = false
    self.outputBuffer = ""
    self.busySeen = false

    if self.stoppingTask then
        self.state = "stopping"
        return
    end

    local task = self.task
    self.task = nil
    self.generation = self.generation + 1

    if not task then
        self.state = "stopped"
        return
    end

    self.state = "stopping"
    self.stoppingTask = task
    task:closeInput()
    self.stopTimer = self.timerFactory(self.stopGrace, function()
        self.stopTimer = nil
        if self.stoppingTask == task then
            if task:isRunning() then
                task:terminate()
                self.killTimer = self.timerFactory(self.stopGrace, function()
                    if self.stoppingTask == task and task:isRunning() and self.killTask then
                        self.killTask(task)
                    end
                end)
            else
                self:_finishStopping(task)
            end
        end
    end)
end

function Supervisor:_reconcile()
    if not self.desiredRunning then
        self:_stopActive()
        return
    end
    if self.state == "faulted" or self.task or self.stoppingTask or self.restartTimer then
        return
    end
    self:_start()
end

function Supervisor:_dispatch()
    if not self.desiredRunning or not self.task or not self.ready
        or self.inFlight or self.pendingSegment == nil then
        return
    end

    local task = self.task
    local generation = self.generation
    local segment = self.pendingSegment
    self.pendingSegment = nil
    self.inFlight = true
    task:setInput(string.format("SHOW %d\n", segment))

    self:_cancelTimer("ackTimer")
    self.ackTimer = self.timerFactory(self.ackTimeout, function()
        self.ackTimer = nil
        if self.task == task and self.generation == generation and self.inFlight then
            logError(self.logger, "spotify-osd acknowledgement timeout")
            self.failureAfterStop = "acknowledgement timeout"
            self:_stopActive()
        end
    end)
end

function Supervisor:setDesiredRunning(desired)
    desired = desired == true
    if desired ~= self.desiredRunning then
        self.desiredRunning = desired
        self.failureCount = 0
        if desired then
            if self.state == "faulted" then
                self.state = "stopped"
            end
        else
            self:_cancelTimer("restartTimer")
            self.failureAfterStop = nil
            if self.task or self.stoppingTask then
                self.state = "stopping"
            else
                self.state = "stopped"
            end
        end
    end
    self:_reconcile()
end

function Supervisor:show(segment)
    if not self.desiredRunning then
        return false
    end
    self.pendingSegment = math.max(0, math.min(16, math.floor(segment + 0.5)))
    self:_reconcile()
    self:_dispatch()
    return true
end

function Supervisor:shutdown()
    self.desiredRunning = false
    self.failureCount = 0
    self:_stopActive()
end

function Supervisor:status()
    local pid = nil
    if self.task and self.task.pid then
        pid = self.task:pid()
    end
    return {
        desiredRunning = self.desiredRunning,
        state = self.state,
        pid = pid,
        generation = self.generation,
        restartAttempts = self.failureCount,
        ready = self.ready,
        inFlight = self.inFlight,
        pendingSegment = self.pendingSegment,
        protocolVersion = self.protocolVersion,
        buildID = self.buildID,
    }
end

return module
