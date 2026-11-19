# Deployment

Publish only the reviewed source archive, its checksum, and the version-specific
install instructions. Run `make verify` on Intel and Apple Silicon and
`make package` from the approved commit. Package creation reads the Git tree,
not ignored files or generated executables. Inspect the resulting member list.

The install command verifies the published source archive before extraction and
builds on the user's Mac. Its published checksum detects mismatched downloads.
The user trusts the instructions from this repository as the source for that
checksum. The local release manifest checks the files installed on disk.

The installer keeps releases under
`~/Library/Application Support/Hammerspoon/SpotifyVolume/releases/` and
switches the Hammerspoon Spoon link after validating the selected release.
Shortcut preferences and volume state live in the sibling `state` directory.
After a configuration change or update, use **Reload Config** in Hammerspoon and
run `spotify-volume status --after-reload` from the installed manager path shown in the README.

If a pending change needs to be cancelled, use `rollback` and reload. A regular
rollback selects the previous registered release. Keep legacy private
installations and their local recovery copies separate from the public history.
