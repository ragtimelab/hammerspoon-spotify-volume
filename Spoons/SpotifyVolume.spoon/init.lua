local obj = {}
obj.__index = obj

obj.name = "SpotifyVolume"
obj.version = "development"
obj.author = "ragtimelab"
obj.homepage = "https://github.com/ragtimelab/hammerspoon-spotify-volume"
obj.license = "MIT"

-- scriptPath() resolves the directory of this Spoon. resourcePath() expects a
-- path *inside* that directory, so passing the Spoon name would add an invalid
-- extra path component and could silently fall through to legacy Lua modules.
local scriptRoot = hs.spoons.scriptPath():gsub("/$", "")
local resourceRoot = assert(hs.fs.pathToAbsolute(scriptRoot), "Cannot resolve SpotifyVolume release")
-- Load only modules in this release. Do not modify the shared Lua loader.
local modules = {}
local function loadModule(name)
    if modules[name] then return modules[name] end
    assert(name:match("^spotify%.[a-z_]+$"), "Invalid SpotifyVolume module")
    local environment = setmetatable({require = loadModule}, {__index = _G})
    local chunk = assert(loadfile(resourceRoot .. "/" .. name:gsub("%.", "/") .. ".lua", "t", environment))
    local module = chunk()
    modules[name] = module
    return module
end
local Runtime = loadModule("spotify.runtime")

local function ensureDirectory(path)
    if hs.fs.attributes(path, "mode") == "directory" then
        return true
    end

    local parent = path:match("^(.*)/[^/]+$")
    if parent and parent ~= path and hs.fs.attributes(parent, "mode") ~= "directory" then
        local ok, err = ensureDirectory(parent)
        if not ok then
            return false, err
        end
    end

    local ok, err = hs.fs.mkdir(path)
    if ok or hs.fs.attributes(path, "mode") == "directory" then
        return true
    end
    return false, err
end

local function normalizeBinding(binding, name)
    assert(type(binding) == "table", name .. " hotkey must be a table")
    assert(type(binding[1]) == "table", name .. " modifiers must be a table")
    assert(type(binding[2]) == "string" or type(binding[2]) == "number", name .. " key must be a name or keycode")
    return binding[1], binding[2]
end

function obj:init()
    self._runtime = nil
    self._hotkeys = {}
    self._started = false
    self._shutdownCallback = nil
    self._previousShutdownCallback = nil
    self.logger = hs.logger.new("SpotifyVolume", "warning")
    self.stateDirectory = os.getenv("HOME")
        .. "/Library/Application Support/Hammerspoon/SpotifyVolume/state"
    self.statePath = self.stateDirectory .. "/segment"
    self.helperPath = resourceRoot .. "/bin/spotify-osd"
    self.controlPath = resourceRoot .. "/bin/spotify-control"
    -- Capture identity once; never read through a changed install symlink later.
    local metadataFile = io.open(resourceRoot .. "/BUILD-INFO.json", "r")
    if metadataFile then
        local metadata = hs.json.decode(metadataFile:read("*a"))
        metadataFile:close()
        self.buildID = assert(metadata.buildID, "bundle build identity is missing")
        self.version = metadata.version
    else self.buildID = "development" end

end

function obj:_publishStatus(configurationError)
    local state = self:status()
    state.hammerspoonPID = hs.processInfo.processID
    state.buildID = self.buildID
    state.loadedAt = self._loadedAt
    state.configurationError = configurationError
    local path = self.stateDirectory .. "/runtime.json"
    local data = hs.json.encode(state)
    if data == self._lastStatus then return end
    local temporary = path .. "." .. tostring(state.hammerspoonPID)
    local file = io.open(temporary, "w")
    if file then
        file:write(data)
        file:close()
        if os.rename(temporary, path) then self._lastStatus = data end
    end
end

function obj:startConfigured()
    self._loadedAt = hs.timer.secondsSinceEpoch()
    local ok, err = pcall(function()
        local file = assert(io.open(self.stateDirectory .. "/hotkeys.json", "r"), "choose shortcuts with configure")
        local data = file:read(16385)
        file:close()
        assert(data and #data <= 16384, "invalid shortcut configuration")
        local selection = hs.json.decode(data)
        local mapping = {}
        local modifiers = {cmd = "⌘", ctrl = "⌃", alt = "⌥", shift = "⇧"}
        local used = {}
        for _, direction in ipairs({"down", "up"}) do
            local binding = selection[direction]
            local key = binding.keyCode
            assert(type(key) == "number" and key >= 0 and key <= 127 and key % 1 == 0, "Invalid key code")
            local requested = {}
            for _, modifier in ipairs(binding.modifiers) do
                assert(modifiers[modifier] and not requested[modifier], "Invalid shortcut modifier")
                requested[modifier] = true
            end
            local prefix = {}
            for _, modifier in ipairs({"cmd", "ctrl", "alt", "shift"}) do
                if requested[modifier] then prefix[#prefix + 1] = modifiers[modifier] end
            end
            local keyName = hs.keycodes.map[key]
            local combination = (#prefix == 4 and "✧" or table.concat(prefix))
                .. (keyName and string.upper(keyName) or ("[#" .. tostring(key) .. "]"))
            assert(not used[combination], "Shortcut conflict for volume " .. direction)
            used[combination] = true
            for _, hotkey in ipairs(hs.hotkey.getHotkeys()) do
                assert(hotkey.idx ~= combination, "Shortcut conflict for volume " .. direction)
            end
            local assigned = hs.hotkey.systemAssigned(binding.modifiers, key)
            assert(not (assigned and assigned.enabled), "Shortcut conflict for volume " .. direction)
            assert(hs.hotkey.assignable(binding.modifiers, key), "Shortcut unavailable for volume " .. direction)
            mapping[direction] = {binding.modifiers, key}
        end
        self:bindHotkeys(mapping):start()
    end)
    if not ok then
        self:stop()
        self:_publishStatus(tostring(err):match("([^:]+)$") or tostring(err))
        return self
    end
    self:_publishStatus()
    self._statusTimer = hs.timer.new(2, function() self:_publishStatus() end):start()
    return self
end

function obj:_setHotkeysEnabled(enabled)
    for _, hotkey in ipairs(self._hotkeys) do
        if enabled then
            assert(hotkey:enable(), "Cannot enable chosen SpotifyVolume shortcut")
        else
            hotkey:disable()
        end
    end
end

function obj:_deleteHotkeys()
    for _, hotkey in ipairs(self._hotkeys) do
        hotkey:delete()
    end
    self._hotkeys = {}
end

function obj:bindHotkeys(mapping)
    assert(type(mapping) == "table", "Choose both SpotifyVolume hotkeys first")
    local downModifiers, downKey = normalizeBinding(mapping.down, "down")
    local upModifiers, upKey = normalizeBinding(mapping.up, "up")

    self:_deleteHotkeys()
    self._hotkeys = {
        hs.hotkey.new(
            downModifiers,
            downKey,
            function() if self._runtime then self._runtime:pressed(-1) end end,
            function() if self._runtime then self._runtime:released() end end,
            function() if self._runtime then self._runtime:repeated(-1) end end
        ),
        hs.hotkey.new(
            upModifiers,
            upKey,
            function() if self._runtime then self._runtime:pressed(1) end end,
            function() if self._runtime then self._runtime:released() end end,
            function() if self._runtime then self._runtime:repeated(1) end end
        ),
    }
    self:_setHotkeysEnabled(self._started)
    return self
end

function obj:start()
    if self._started then
        return self
    end

    assert(#self._hotkeys == 2, "Choose both SpotifyVolume hotkeys before starting")
    local ok, err = ensureDirectory(self.stateDirectory)
    assert(ok, "failed to create SpotifyVolume state directory: " .. tostring(err))

    self._runtime = Runtime.start({
        hs = hs,
        logger = self.logger,
        bundleID = "com.spotify.client",
        helperPath = self.helperPath,
        controlPath = self.controlPath,
        buildID = self.buildID,
        statePath = self.statePath,
        protocolVersion = 1,
    })
    self._started = true
    self:_setHotkeysEnabled(true)

    self._previousShutdownCallback = hs.shutdownCallback
    self._shutdownCallback = function()
        if self._statusTimer then self._statusTimer:stop(); self._statusTimer = nil end
        if self._runtime then
            self._runtime:shutdown()
            self._runtime = nil
        end
        self._started = false
        if self._previousShutdownCallback then
            self._previousShutdownCallback()
        end
    end
    hs.shutdownCallback = self._shutdownCallback
    return self
end

function obj:stop()
    if self._statusTimer then self._statusTimer:stop(); self._statusTimer = nil end
    if self._runtime then
        self._runtime:shutdown()
        self._runtime = nil
    end
    self._started = false
    self:_setHotkeysEnabled(false)

    if hs.shutdownCallback == self._shutdownCallback then
        hs.shutdownCallback = self._previousShutdownCallback
    end
    self._shutdownCallback = nil
    self._previousShutdownCallback = nil
    return self
end

function obj:status()
    if not self._runtime then
        return {
            started = false,
            statePath = self.statePath,
            helperPath = self.helperPath,
        }
    end

    local status = self._runtime:status()
    status.started = self._started
    status.statePath = self.statePath
    status.helperPath = self.helperPath
    return status
end

return obj
