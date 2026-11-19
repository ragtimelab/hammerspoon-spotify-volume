#!/bin/zsh
set -euo pipefail
repository_root=${0:A:h:h:h}
test_root=$(mktemp -d "${TMPDIR:-/tmp}/spotify-volume-install-test.XXXXXX")
trap 'find "$test_root" -depth -delete' EXIT
mkdir -p "$test_root/source/scripts" "$test_root/config"
cp "$repository_root/scripts/lifecycle.rb" "$test_root/source/scripts/"
printf '%s\n' 'hs.hotkey.bind({}, "f5", function() end)' > "$test_root/original.lua"
cp "$test_root/original.lua" "$test_root/config/init.lua"
cat > "$test_root/source/scripts/build" <<'BUILD'
#!/bin/zsh
set -euo pipefail
/usr/bin/ditto "$TEST_ARTIFACT" "$1"
BUILD
chmod +x "$test_root/source/scripts/build"
export TEST_ARTIFACT="$repository_root/.build/artifacts"
export HSV_INSTALL_ROOT="$test_root/install"
export HSV_HAMMERSPOON_DIR="$test_root/config"
manager="$test_root/source/scripts/lifecycle.rb"
run() { /usr/bin/ruby "$manager" "$@"; }
link="$HSV_HAMMERSPOON_DIR/Spoons/SpotifyVolume.spoon"

run install --files-only
active=$(readlink "$link")
cmp "$test_root/original.lua" "$test_root/config/init.lua"
[[ "$(run status)" == *'installed, inactive'* ]]
[[ -x "$HSV_INSTALL_ROOT/spotify-volume" ]]
run install --files-only
[[ "$(readlink "$link")" == "$active" ]]

# The actual configure and recovery path, with a synthetic keyboard selection.
/usr/bin/ruby - "$manager" <<'RUBY'
require ARGV.fetch(0)
class TestLifecycle < Lifecycle
  def interactive?; true; end
  def yes?(_prompt); true; end
  def capture_selection(_target, _arguments)
    JSON.generate({
      "down" => {"modifiers" => ["ctrl"], "keyCode" => 34, "label" => "Ctrl + I"},
      "up" => {"modifiers" => ["ctrl"], "keyCode" => 31, "label" => "Ctrl + O"},
    })
  end
end
config = File.join(ENV.fetch("HSV_HAMMERSPOON_DIR"), "init.lua")
root = ENV.fetch("HSV_INSTALL_ROOT")
original = File.binread(config)
TestLifecycle.new.run("configure", [])
raise "Managed loader missing" unless File.read(config).include?(Lifecycle::MANAGED)
backup = Dir.glob(File.join(root, "state/init-backup-*.lua")).fetch(0)
raise "Incorrect backup" unless File.binread(backup) == original
raise "Unsafe backup mode" unless (File.stat(backup).mode & 0o777) == 0o600
TestLifecycle.new.run("rollback", [])
raise "Configuration was not restored" unless File.binread(config) == original
raise "New keys were not removed" if File.exist?(File.join(root, "state/hotkeys.json"))
referent = "#{config}.managed"
File.rename(config, referent)
File.symlink(referent, config)
TestLifecycle.new.run("configure", [])
raise "Symlink was replaced" unless File.symlink?(config)
raise "Referent was edited" unless File.binread(referent) == original
TestLifecycle.new.run("rollback", [])
File.unlink(config)
File.rename(referent, config)

RUBY

# A release must be rejected before reuse when local verification fails.
printf '\n-- harmless integrity test edit\n' >> "$active/init.lua"
if run install --files-only; then
    print -u2 "Damaged release accepted"
    exit 1
fi
cp "$TEST_ARTIFACT/SpotifyVolume.spoon/init.lua" "$active/init.lua"
touch "$active/extra.log"
if run status; then
    print -u2 "Unexpected release file accepted"
    exit 1
fi
unlink "$active/extra.log"
run uninstall
[[ ! -e "$link" && ! -L "$link" ]]
cmp "$test_root/original.lua" "$test_root/config/init.lua"
run install --files-only
run uninstall --purge-state
print "PASS files-only install, release reuse checks, integrity failure and uninstall"
