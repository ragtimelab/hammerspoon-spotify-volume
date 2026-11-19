#!/bin/zsh
set -euo pipefail
root=${0:A:h:h:h}
cd "$root"
archive=$(./scripts/package)
stage=$(mktemp -d "${TMPDIR:-/tmp}/spotify-volume-source-test.XXXXXX")
trap 'find "$stage" -depth -delete' EXIT
(
    cd "${archive:h}"
    /usr/bin/shasum -a 256 -c "${archive:t}.sha256"
)
mkdir "$stage/source"
tar -xzf "$archive" -C "$stage/source"
[[ "$(<"$stage/source/SOURCE-COMMIT")" == "$(git rev-parse HEAD)" ]]
(
    cd "$stage/source"
    /usr/bin/shasum -a 256 -c SOURCE-SHA256SUMS >/dev/null
)
export HSV_INSTALL_ROOT="$stage/install"
export HSV_HAMMERSPOON_DIR="$stage/config"
"$stage/source/scripts/install" --files-only
manager="$HSV_INSTALL_ROOT/spotify-volume"
[[ "$("$manager" status)" == *'installed, inactive'* ]]
"$manager" uninstall
[[ "$("$manager" status)" == 'Not installed.' ]]
print "PASS checksummed source archive, native build, files-only installation and removal"
