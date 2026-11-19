# Troubleshooting

Use the installed `spotify-volume status` command from the path in the README.
If it reports that activation is pending, select **Reload Config** in Hammerspoon
and run `status --after-reload`. Shortcut setup can be resumed with `configure`.

If an enabled macOS or Hammerspoon shortcut conflicts, the installer keeps the
other chosen key available for retry. Test both new keys while another app is
frontmost. The system volume should stay unchanged.

If Spotify is open but volume synchronization fails, make sure Hammerspoon has
Accessibility access and check macOS Privacy & Security → Automation for the
Spotify control request. If the HUD shows an error but volume still changes,
the macOS HUD service may be unavailable. The HUD is independent of Spotify
volume control.

Use the version-specific install command to update. Use `rollback` to cancel a
pending change or select the previous verified release, then reload Hammerspoon.
