# Compatibility

The first public release supports native Intel Macs with macOS 15 and
Hammerspoon 1.1.1. Apple Silicon source builds and files-only lifecycle checks
run in CI. Interactive Hammerspoon and Spotify acceptance on Apple Silicon
is pending.
Install Hammerspoon, Spotify Desktop, and Apple Command Line Tools before
running the published installation command. The installer builds its Swift
helpers directly on the host.

The system-like HUD uses a private Apple XPC service and can change across OS
updates. Volume control has a separate helper and should remain usable when HUD
display fails. Spotify Automation permission is granted by the user in macOS.
