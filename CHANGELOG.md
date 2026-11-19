# Changelog

## 0.2.1

- Reach the actual 0% and 100% Spotify volume when a fresh press starts near an endpoint.
- Preserve the existing 16-step mapping, key repeat, and intermediate volume behavior.

## 0.2.0

- Add verified source installation for native Intel and Apple Silicon.
- Let each user choose their own two global shortcuts.
- Validate the actual release before activation or rollback.

## 0.1.1 - 2026-09-09

- Preserve native hotkey repeat timing, segment mapping, HUD and sound while moving Spotify Apple events into a persistent serial worker.
- Reject stale repeats after synchronization failure and ignore old process generations.
- Bound READY/BUSY recovery, use atomic checked state writes, and flush confirmed state on worker termination.
- Verify running build identity and worker ownership; serialize lifecycle operations and preserve other configuration after uninstall.

This project uses Semantic Versioning.

## 0.1.0 - 2026-09-05

- 16-step AppleScript volume controller for Spotify
- Native Hammerspoon key repeat handling
- Spotify PID-based HUD helper lifecycle
- Versioned stdin protocol and helper singleton
- Hammerspoon Spoon packaging
- Atomic installation, rollback, and uninstallation
- Regression tests for the Lua runtime and Swift protocol
