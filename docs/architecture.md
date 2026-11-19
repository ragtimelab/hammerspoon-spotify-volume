# Architecture

## Component boundaries

`SpotifyVolume.spoon` integrates with Hammerspoon and handles global shortcut events at runtime. Three Swift executables provide native integration.

- `spotify-control` controls the Spotify process by sending serial Apple events to its PID.
- `spotify-osd` presents the volume HUD and plays its feedback sound.
- `spotify-volume-keys` captures the user's chosen shortcuts during configuration.

```text
Configured shortcut (for example, F11/F12)
  → hs.hotkey pressed/repeat/released callback
  → controller
  → input FIFO and asynchronous adapter
  → spotify-control (serial Apple events targeting the Spotify PID)
  → Spotify sound volume

controller
  → OSD supervisor
  → persistent spotify-osd --server
  → com.apple.OSDUIHelper
```

The controller commits its volume state and requests a HUD update only after a confirmed Spotify write. The OSD supervisor handles HUD helper failures with bounded restarts while Spotify volume control continues independently.

## HUD helper lifecycle

- Start the application watcher before taking the initial process snapshot.
- The helper's desired state is running only while a Spotify PID exists.
- When Spotify exits, request a graceful shutdown through stdin EOF and terminate the helper if it is still running after 250 ms.
- After helper crashes, retry with backoffs of 0.25, 1, and 4 seconds, then enter the fault state if the retries are exhausted.
- `BUSY` conflicts use the same retry budget, and `READY` must arrive within 5 seconds.
- Reset the failure count after 30 seconds of stable operation.
- A `CFMessagePort` singleton prevents two servers from running simultaneously during a reload race.

## HUD protocol

```text
READY 1 <buildID>
SHOW 0
OK 0
BUSY
ERR <code> <message>
```

`OK <segment>` acknowledges that the helper accepted the HUD request. The XPC display request is asynchronous, so rendering remains unconfirmed.

If Lua and the helper use different protocol versions, the supervisor stops the helper and follows its restart policy.

## Spotify control worker and state

`spotify-control` handles `get`, `set`, and `write` over JSON Lines.
It validates each request's `id`, `generation`, `pid`, and `operation`. Responses
echo the `id` and `generation` and include `ok` with either `value` or
`error` and `code`. Lua waits for a response before sending the next frame,
because `hs.task:setInput` replaces input that has yet to be sent. The input FIFO
holds up to 4096 entries and the receive buffer holds up to 64 KiB. Exceeding
either limit produces an error.

Each command has a 120-second Apple event timeout, and the parent process has a
125-second response watchdog. Spotify may still complete the operation after a
timeout, so the controller avoids resending the write. It blocks repeats from
the failed press and reads the actual volume on the next fresh press. PID
replacement or exit invalidates the generation, so a stale response cannot
overwrite new state.

The worker persists confirmed writes on a separate queue with a 250 ms debounce.
A release-triggered save request, EOF, or SIGTERM flushes the last confirmed
value. The worker creates files with `O_EXCL` and `O_NOFOLLOW` and mode `0600`
and checks that `fsync`, `close`, and `rename` succeed. Hammerspoon input callbacks
do not spawn a `chmod` process.

## References

- [Apple NSEvent keyRepeatDelay](https://developer.apple.com/documentation/appkit/nsevent/keyrepeatdelay)
- [Hammerspoon 1.1.1 hotkey implementation](https://github.com/Hammerspoon/hammerspoon/blob/1.1.1/extensions/hotkey/libhotkey.m)
- [hs.task input and streaming callbacks](https://www.hammerspoon.org/docs/hs.task.html)
- [Apple PID descriptor](https://developer.apple.com/documentation/foundation/nsappleeventdescriptor/init(processidentifier:))
- [Sending Apple events](https://developer.apple.com/documentation/foundation/nsappleeventdescriptor/sendevent(options:timeout:))
- [AppleScript timeouts and cancellation](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/reference/ASLR_control_statements.html)
