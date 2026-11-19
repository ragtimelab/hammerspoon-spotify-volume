local scriptPath = debug.getinfo(1, "S").source:sub(2)
local testsDirectory = scriptPath:match("^(.*)/[^/]+$")
local repositoryDirectory = testsDirectory:match("^(.*)/Tests/Lua$") or "."
local spoonDirectory = repositoryDirectory .. "/Spoons/SpotifyVolume.spoon"

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

return {
    name = "spoon",
    tests = {
        {
            name = "resolves modules and helper from the Spoon root",
            run = function()
                local originalHs = rawget(_G, "hs")
                local originalPackagePath = package.path
                local originalLoadfile = loadfile
                local scriptPathCalls = 0
                local resourcePathCalls = 0

                local ok, err = xpcall(function()
                    -- LuaJIT exposes the Lua 5.1 loadfile API.
                    if setfenv then
                        _G.loadfile = function(path, _, environment)
                            return setfenv(assert(originalLoadfile(path)), environment)
                        end
                    end
                    _G.hs = {
                        fs = {pathToAbsolute = function(path) return path end},
                        spoons = {
                            scriptPath = function()
                                scriptPathCalls = scriptPathCalls + 1
                                return spoonDirectory .. "/"
                            end,
                            resourcePath = function()
                                resourcePathCalls = resourcePathCalls + 1
                                error("resourcePath must not be used to resolve the Spoon root")
                            end,
                        },
                        logger = {
                            new = function() return {} end,
                        },
                    }

                    local spoon = dofile(spoonDirectory .. "/init.lua")
                    spoon:init()

                    equal(scriptPathCalls, 1, "scriptPath call count")
                    equal(resourcePathCalls, 0, "resourcePath call count")
                    equal(spoon.helperPath, spoonDirectory .. "/bin/spotify-osd", "helper path")
                    equal(package.path, originalPackagePath, "shared module search path")
                    equal(#spoon._hotkeys, 0, "no registered hotkeys")
                    equal(pcall(function() spoon:start() end), false, "start requires chosen hotkeys")

                end, debug.traceback)

                _G.loadfile = originalLoadfile
                package.path = originalPackagePath
                _G.hs = originalHs
                if not ok then
                    error(err, 0)
                end
            end,
        },
    },
}
