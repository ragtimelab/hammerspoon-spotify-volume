# SpotifyVolume contributor instructions

Make changes in this repository's source and scripts. Do not patch the installed Spoon, the installed management tool, or personal Hammerspoon configuration directly. If the documentation and command behavior disagree, inspect the definitions and tests and resolve the underlying cause. Use `date` to verify times when checking or recording them.

## Code verification

- Run `make verify` from the repository root. It runs source checks, Lua and Swift tests, a native build that treats warnings as errors, and installation lifecycle tests in temporary paths. CI runs these checks and `./Tests/Shell/source_release_test.zsh` on Intel and Apple Silicon. [Makefile](Makefile) · [Test entry point](scripts/test) · [CI](.github/workflows/verify.yml)
- Key repeat uses Hammerspoon's press, repeat, and release callbacks and an asynchronous FIFO. Do not add a Lua repeat timer. Update volume state and the HUD after Spotify confirms the write, and discard responses from the previous generation when the PID changes. Handle HUD failures independently of volume control. [Architecture](docs/architecture.md) · [Controller tests](Tests/Lua/controller_test.lua)

## Release packaging

- Verify the approved commit's full SHA and the CI results for that SHA on both architectures, then run `./scripts/package <commit>`. `make package` uses the current `HEAD`. Packaging uses the allowed paths in the specified Git tree. Before uploading to a release, check the archive member list and cross-check its internal `SOURCE-COMMIT` and `SOURCE-SHA256SUMS`, the external SHA-256 checksum, and the digest in `Install-v<version>.txt`. Distribute the reviewed source archive, its external checksum, and the version-specific installation instructions. [Deployment](docs/deployment.md) · [Packaging](scripts/package) · [Bootstrap](scripts/bootstrap)

## Installation and activation

- For isolated verification, set `HSV_INSTALL_ROOT` and `HSV_HAMMERSPOON_DIR` to separate temporary paths and use `./scripts/install --files-only`. To verify the source distribution, extract the archive, build natively, and check for `installed, inactive` after installation and `Not installed.` after removal. Set both paths because `--files-only` writes to the installation directory and creates the Spoon link. Follow the [compatibility documentation](docs/compatibility.md) for the scope of Apple Silicon CI build and files-only installation checks and interactive Hammerspoon and Spotify support. [Installation test](Tests/Lua/install_test.zsh) · [Source release test](Tests/Shell/source_release_test.zsh)
- Perform operational installation, configuration changes, and reloads within the scope the user has approved. Use the installed `spotify-volume` management tool shown in the [README](README.md). After **Reload Config**, confirm activation of the target build with `status --after-reload`. A plain `status` can also finalize pending changes. The `--after-reload` flag can restore the previous configuration if the new runtime fails to report in. Launch Spotify and confirm that volume control is ready. Complete interactive verification by testing brief presses and holds of the actual shortcuts and checking the HUD and system volume. When needed, use the management tool's `rollback` command to cancel pending changes or select the previously registered release. [Installation manager](scripts/lifecycle.rb) · [Troubleshooting](docs/troubleshooting.md)

## Public repository boundaries

- Keep personal configuration, shortcut and volume state, local backups and recovery copies, and legacy private installation history outside public Git history and release artifacts. Use temporary paths and synthetic data in public source and tests in place of personal absolute paths. Use local registered releases and backups for operational recovery. [Deployment](docs/deployment.md) · [Source checks](scripts/check-source) · [Installation manager](scripts/lifecycle.rb)
