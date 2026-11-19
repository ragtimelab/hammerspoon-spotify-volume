require("hs.ipc")

hs.loadSpoon("SpotifyVolume")

spoon.SpotifyVolume:bindHotkeys({
    down = {{}, "f11"},
    up = {{}, "f12"},
})

spoon.SpotifyVolume:start()

-- Unrelated configuration must survive installation and removal.
hs.hotkey.bind({}, "f5", function() end)
