local OSDSupervisor = require("spotify.osd_supervisor")

local function equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "values differ", tostring(expected), tostring(actual)), 2)
    end
end

local function makeContext()
    local context = {
        tasks = {},
        timers = {},
        nextPID = 100,
    }

    local supervisor = OSDSupervisor.new({
        executable = "/test/spotify-osd",
        taskFactory = function(_, terminationCallback, streamCallback)
            context.nextPID = context.nextPID + 1
            local task = {
                running = false,
                inputs = {},
                closed = false,
                terminated = false,
                processID = context.nextPID,
                start = function(self)
                    self.running = true
                    return true
                end,
                setInput = function(self, input)
                    self.inputs[#self.inputs + 1] = input
                    return self
                end,
                closeInput = function(self)
                    self.closed = true
                    return self
                end,
                isRunning = function(self)
                    return self.running
                end,
                terminate = function(self)
                    self.terminated = true
                    self.running = false
                    return self
                end,
                pid = function(self)
                    return self.processID
                end,
                emit = function(self, output)
                    streamCallback(self, output, "")
                end,
                exit = function(self, code, stderr)
                    self.running = false
                    terminationCallback(code or 0, "", stderr or "")
                end,
            }
            context.tasks[#context.tasks + 1] = task
            return task
        end,
        timerFactory = function(delay, callback)
            local timer = {
                delay = delay,
                stopped = false,
                fire = function(self)
                    if not self.stopped then
                        self.stopped = true
                        callback()
                    end
                end,
                stop = function(self)
                    self.stopped = true
                end,
            }
            context.timers[#context.timers + 1] = timer
            return timer
        end,
    })

    context.supervisor = supervisor
    return context
end

local function latestLiveTimer(context, delay)
    for index = #context.timers, 1, -1 do
        local timer = context.timers[index]
        if not timer.stopped and (delay == nil or timer.delay == delay) then
            return timer
        end
    end
    error("live timer not found", 2)
end

return {
    name = "osd_supervisor",
    tests = {
        {
            name = "missing READY times out and consumes restart budget",
            run = function()
                local c = makeContext()
                c.supervisor:setDesiredRunning(true)
                latestLiveTimer(c, 5):fire()
                equal(c.tasks[1].closed, true, "startup stdin closed")
                c.tasks[1]:exit(0)
                equal(c.supervisor:status().restartAttempts, 1, "startup failure")
            end,
        },
        {
            name = "continuous BUSY terminates after bounded retries",
            run = function()
                local c = makeContext()
                c.supervisor:setDesiredRunning(true)
                for n = 1,4 do
                    c.tasks[n]:emit("BUSY\n")
                    c.tasks[n]:exit(75)
                    if n < 4 then latestLiveTimer(c, ({0.25,1,4})[n]):fire() end
                end
                equal(#c.tasks, 4, "bounded task count")
                equal(c.supervisor:status().state, "faulted", "busy fault")
            end,
        },
        {
            name = "desired running starts eagerly and is idempotent",
            run = function()
                local context = makeContext()
                context.supervisor:setDesiredRunning(true)
                equal(#context.tasks, 1, "task count after start")
                equal(context.supervisor:status().state, "starting", "starting state")
                context.supervisor:setDesiredRunning(true)
                equal(#context.tasks, 1, "task count after duplicate start")
            end,
        },
        {
            name = "READY dispatches one command and ACK dispatches latest pending",
            run = function()
                local context = makeContext()
                context.supervisor:setDesiredRunning(true)
                local task = context.tasks[1]
                context.supervisor:show(3)
                equal(#task.inputs, 0, "input before READY")
                task:emit("READY 1\n")
                equal(task.inputs[1], "SHOW 3\n", "first SHOW")
                context.supervisor:show(4)
                context.supervisor:show(5)
                equal(#task.inputs, 1, "input before ACK")
                task:emit("OK 3\n")
                equal(task.inputs[2], "SHOW 5\n", "latest pending SHOW")
            end,
        },
        {
            name = "desired stopped closes input and forces termination after grace",
            run = function()
                local context = makeContext()
                context.supervisor:setDesiredRunning(true)
                local task = context.tasks[1]
                context.supervisor:setDesiredRunning(false)
                equal(task.closed, true, "stdin closed")
                equal(context.supervisor:status().state, "stopping", "stopping state")
                latestLiveTimer(context, 0.25):fire()
                equal(task.terminated, true, "forced termination")
                task:exit(0)
                equal(context.supervisor:status().state, "stopped", "stopped state")
            end,
        },
        {
            name = "show does not lazy-start when desired state is false",
            run = function()
                local context = makeContext()
                equal(context.supervisor:show(8), false, "show result")
                equal(#context.tasks, 0, "task count")
            end,
        },
        {
            name = "unexpected exits use fixed restart delays",
            run = function()
                local context = makeContext()
                context.supervisor:setDesiredRunning(true)
                context.tasks[1]:exit(1, "crash one")
                equal(context.supervisor:status().restartAttempts, 1, "first failure")
                latestLiveTimer(context, 0.25):fire()
                context.tasks[2]:exit(1, "crash two")
                equal(context.supervisor:status().restartAttempts, 2, "second failure")
                latestLiveTimer(context, 1):fire()
                context.tasks[3]:exit(1, "crash three")
                equal(context.supervisor:status().restartAttempts, 3, "third failure")
                latestLiveTimer(context, 4):fire()
                context.tasks[4]:exit(1, "crash four")
                equal(context.supervisor:status().state, "faulted", "faulted state")
                equal(context.supervisor:status().restartAttempts, 4, "fault count")
            end,
        },
        {
            name = "stable READY resets failure count",
            run = function()
                local context = makeContext()
                context.supervisor:setDesiredRunning(true)
                context.tasks[1]:exit(1, "crash")
                latestLiveTimer(context, 0.25):fire()
                context.tasks[2]:emit("READY 1\n")
                latestLiveTimer(context, 30):fire()
                equal(context.supervisor:status().restartAttempts, 0, "stable failure count")
            end,
        },
        {
            name = "ACK timeout stops task before scheduling restart",
            run = function()
                local context = makeContext()
                context.supervisor:setDesiredRunning(true)
                local task = context.tasks[1]
                task:emit("READY 1\n")
                context.supervisor:show(7)
                latestLiveTimer(context, 0.5):fire()
                equal(task.closed, true, "timeout stdin close")
                task:exit(0)
                equal(context.supervisor:status().restartAttempts, 1, "timeout failure count")
                equal(latestLiveTimer(context, 0.25).delay, 0.25, "timeout restart delay")
            end,
        },
        {
            name = "Spotify lifecycle resets fault state",
            run = function()
                local context = makeContext()
                context.supervisor:setDesiredRunning(true)
                for failure = 1, 4 do
                    context.tasks[failure]:exit(1, "crash")
                    if failure < 4 then
                        latestLiveTimer(context, ({0.25, 1, 4})[failure]):fire()
                    end
                end
                equal(context.supervisor:status().state, "faulted", "faulted before lifecycle")
                context.supervisor:setDesiredRunning(false)
                context.supervisor:setDesiredRunning(true)
                equal(context.supervisor:status().state, "starting", "state after lifecycle")
                equal(context.supervisor:status().restartAttempts, 0, "failure count after lifecycle")
            end,
        },
        {
            name = "protocol mismatch stops helper and counts a failure",
            run = function()
                local context = makeContext()
                context.supervisor:setDesiredRunning(true)
                local task = context.tasks[1]
                task:emit("READY 2\n")
                equal(task.closed, true, "mismatched helper stdin closed")
                task:exit(0)
                equal(context.supervisor:status().restartAttempts, 1, "protocol failure count")
                equal(latestLiveTimer(context, 0.25).delay, 0.25, "protocol restart delay")
            end,
        },
    },
}
