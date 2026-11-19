# SpotifyVolume

**Use your own global shortcuts to adjust the Spotify desktop app's volume while you work in other apps.** macOS system volume and audio from other apps stay at their current levels. You can turn down the music while browsing or writing without switching to Spotify.

## Supported environment

- macOS 15, Hammerspoon 1.1.1, and the Spotify desktop app
- Intel Macs (`x86_64`) are supported. Apple Silicon has passed automated native builds and files-only installation checks. Interactive testing with Hammerspoon and Spotify is pending.
- Apple Command Line Tools. Run `xcode-select --install` in Terminal for initial setup.

## Installation

Open `Install-v<version>.txt` for the version you want on the [official releases page](https://github.com/ragtimelab/hammerspoon-spotify-volume/releases). Paste the command block into Terminal once to download that version's source, verify its SHA-256 checksum, and build and install it on your Mac.

## Shortcut setup

Set up the shortcuts after installation or resume setup later with `configure`. Press your volume-down and volume-up shortcuts once each, review the proposed Hammerspoon configuration, and apply it. Choose **Reload Config** from the Hammerspoon menu, confirm activation with `status --after-reload`, and test both shortcuts.

There are no default shortcuts. One setup on an Apple Magic Keyboard with Numeric Keypad assigns `fn`+F11 and `fn`+F12 to Spotify and uses F11 and F12 alone for macOS system volume. The behavior depends on your keyboard and macOS function-key settings.

Spotify volume has 16 steps. Hold a shortcut to repeat the adjustment one step at a time. A volume HUD appears on supported setups. Grant the Automation permission for Spotify control in macOS Settings.

## Management

```sh
"$HOME/Library/Application Support/Hammerspoon/SpotifyVolume/spotify-volume" status
"$HOME/Library/Application Support/Hammerspoon/SpotifyVolume/spotify-volume" configure
"$HOME/Library/Application Support/Hammerspoon/SpotifyVolume/spotify-volume" rollback
"$HOME/Library/Application Support/Hammerspoon/SpotifyVolume/spotify-volume" uninstall
```

To update, run the installation command from the new release. Uninstalling retains state and verified releases. To delete state, use `uninstall --purge-state`.

## Development

Local development and CI verification require Command Line Tools, Lua or LuaJIT, and ripgrep. Run `make verify` to verify the project and `make package` to package committed source for distribution.

[Architecture](docs/architecture.md) · [Deployment](docs/deployment.md) · [Compatibility](docs/compatibility.md) · [Troubleshooting](docs/troubleshooting.md) · [MIT](LICENSE)
