#!/bin/zsh
set -euo pipefail
repository_root=${0:A:h:h:h}
test_root=$(mktemp -d /tmp/spotify-volume-source-test.XXXXXX)
trap 'find "$test_root" -depth -delete' EXIT

check_exit() {
    local expected=$1 first=$2 second=$3 actual=0
    PATH="$test_root" HSV_TEST_RG_EXIT="$first" HSV_TEST_RG_SECOND_EXIT="$second" \
        /bin/zsh "$repository_root/scripts/check-source" >"$test_root/output" 2>&1 || actual=$?
    if [[ "$actual" != "$expected" ]]; then
        print -u2 "Source check expected exit $expected, got $actual"
        return 1
    fi
}

check_exit 127 1 1 # Missing executable must not pass.
ln -s "$repository_root/Tests/Fixtures/rg-exit" "$test_root/rg"
check_exit 0 1 1 # Both scans completed without matches.
check_exit 1 0 1 # First scan found a forbidden pattern.
check_exit 1 1 0 # Second scan found a forbidden pattern.
check_exit 2 2 1 # First scan failed.
check_exit 2 1 2 # Second scan failed.
check_exit 127 127 1 # Executable itself failed to start a dependency.
print "PASS source checks: missing tool, no matches, matches and scan errors (7 cases)"
