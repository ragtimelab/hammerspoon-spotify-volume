local scriptPath = debug.getinfo(1, "S").source:sub(2)
local testsDirectory = scriptPath:match("^(.*)/[^/]+$")
local repositoryDirectory = testsDirectory:match("^(.*)/Tests/Lua$") or "."
local spoonDirectory = repositoryDirectory .. "/Spoons/SpotifyVolume.spoon"

package.path = table.concat({
    spoonDirectory .. "/?.lua",
    spoonDirectory .. "/?/init.lua",
    package.path,
}, ";")

local suites = {
    dofile(testsDirectory .. "/transport_test.lua"),
    dofile(testsDirectory .. "/controller_test.lua"),
    dofile(testsDirectory .. "/osd_supervisor_test.lua"),
    dofile(testsDirectory .. "/runtime_test.lua"),
    dofile(testsDirectory .. "/spoon_test.lua"),
}

local passed = 0
local failed = 0

for _, suite in ipairs(suites) do
    for _, test in ipairs(suite.tests) do
        local ok, err = pcall(test.run)
        if ok then
            passed = passed + 1
            io.write(string.format("PASS %s: %s\n", suite.name, test.name))
        else
            failed = failed + 1
            io.stderr:write(string.format("FAIL %s: %s\n%s\n", suite.name, test.name, tostring(err)))
        end
    end
end

io.write(string.format("RESULT passed=%d failed=%d\n", passed, failed))
if failed > 0 then
    os.exit(1)
end
