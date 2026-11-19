#!/usr/bin/ruby
require "digest"
require "fileutils"
require "find"
require "json"
require "open3"
require "securerandom"
require "tmpdir"

class Lifecycle
  ROOT = File.expand_path("..", __dir__)
  MANAGED = <<~LUA.freeze
    -- BEGIN SpotifyVolume managed loader
    do
      local entry = hs.configdir .. "/Spoons/SpotifyVolume.spoon/init.lua"
      if hs.fs.attributes(entry, "mode") == "file" then
        local ok, err = pcall(function()
          assert(hs.loadSpoon("SpotifyVolume")):startConfigured()
        end)
        if not ok then hs.printf("SpotifyVolume: %s", tostring(err)) end
      end
    end
    -- END SpotifyVolume managed loader
  LUA

  def initialize
    File.umask(0o077)
    @root = File.expand_path(ENV.fetch("HSV_INSTALL_ROOT", "~/Library/Application Support/Hammerspoon/SpotifyVolume"))
    @config = File.expand_path(ENV.fetch("HSV_HAMMERSPOON_DIR", "~/.hammerspoon"))
    @releases = File.join(@root, "releases")
    @state = File.join(@root, "state")
    @link = File.join(@config, "Spoons", "SpotifyVolume.spoon")
    @init = File.join(@config, "init.lua")
    @keys = File.join(@state, "hotkeys.json")
    @status = File.join(@state, "runtime.json")
    @previous = File.join(@root, "previous-release")
    @pending = File.join(@root, "pending-install.json")
  end

  def run(operation, args)
    private_directory(@root)
    File.open(File.join(@root, ".lifecycle.lock"), File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |lock|
      raise "Unsafe lifecycle lock" unless lock.stat.file? && lock.stat.uid == Process.uid && lock.stat.nlink == 1
      raise "Another lifecycle operation is in progress" unless lock.flock(File::LOCK_EX | File::LOCK_NB)
      private_directory(@releases)
      private_directory(@state)
      unless operation == "status"
        FileUtils.mkdir_p(File.dirname(@link))
        [@config, File.dirname(@link)].each do |directory|
          stat = File.lstat(directory)
          raise "Unsafe Hammerspoon directory: #{directory}" unless stat.directory? &&
            stat.uid == Process.uid && (stat.mode & 0o022).zero?
        end
      end
      settle if entry?(@pending) && operation != "rollback"
      if entry?(@pending) && !%w[status rollback].include?(operation)
        raise "Reload Hammerspoon and run status, or use rollback to cancel the pending change"
      end
      case operation
      when "install" then install(args)
      when "configure" then configure
      when "status" then status(args)
      when "rollback" then rollback
      when "uninstall" then uninstall(args)
      else raise "Use install, configure, status, rollback or uninstall"
      end
    end
  end

  def entry?(path)
    File.exist?(path) || File.symlink?(path)
  end

  def private_directory(path)
    FileUtils.mkdir_p(path)
    stat = File.lstat(path)
    raise "Unsafe directory: #{path}" unless stat.directory? && stat.uid == Process.uid
    File.chmod(0o700, path) unless (stat.mode & 0o777) == 0o700
  end

  def read_regular(path)
    File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
      stat = file.stat
      raise "Unsafe file: #{path}" unless stat.file? && stat.uid == Process.uid && stat.nlink == 1
      file.read
    end
  end

  def atomic(path, contents, mode = 0o600)
    temporary = File.join(File.dirname(path), ".spotify-volume-#{SecureRandom.hex(12)}")
    File.open(temporary, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
      file.write(contents)
      file.chmod(mode)
      file.flush
      file.fsync
    end
    File.rename(temporary, path)
  ensure
    File.unlink(temporary) if temporary && File.exist?(temporary)
  end

  def value(path)
    entry?(path) ? read_regular(path) : nil
  end

  def resolved_link
    return nil unless entry?(@link)
    raise "Refusing to replace an unmanaged Spoon directory" unless File.symlink?(@link)
    File.readlink(@link)
  end

  def release_id(bundle)
    return nil unless bundle
    match = %r{\A#{Regexp.escape(@releases)}/([a-zA-Z0-9][a-zA-Z0-9.+_-]*)/SpotifyVolume\.spoon\z}.match(bundle)
    raise "Spoon target is outside the managed releases" unless match
    match[1]
  end

  def bundle(id)
    raise "Invalid release ID" unless /\A[a-zA-Z0-9][a-zA-Z0-9.+_-]*\z/.match?(id.to_s)
    File.join(@releases, id, "SpotifyVolume.spoon")
  end

  def verify(destination)
    release_id(destination)
    verify_content(destination)
  end

  def verify_content(destination)
    [File.dirname(destination), destination].each do |folder|
      stat = File.lstat(folder)
      raise "Unsafe release directory" unless stat.directory? && stat.uid == Process.uid && (stat.mode & 0o022).zero?
    end
    raw = read_regular(File.join(File.dirname(destination), "SHA256SUMS"))
    entries = {}
    raw.each_line do |line|
      match = /\A([a-f0-9]{64})  \.\/([A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+)*)\n?\z/.match(line)
      raise "Invalid release manifest" unless match && (match[2].split("/") & %w[. ..]).empty? && !entries.key?(match[2])
      entries[match[2]] = match[1]
    end
    expected = %w[BUILD-INFO.json init.lua spotify/controller.lua spotify/osd_supervisor.lua
                  spotify/runtime.lua spotify/transport.lua bin/spotify-osd bin/spotify-control bin/spotify-volume-keys]
    raise "Unexpected release manifest" unless entries.keys.sort == expected.sort
    directories = [destination, File.join(destination, "spotify"), File.join(destination, "bin")]
    directories.each do |directory|
      stat = File.lstat(directory)
      raise "Unsafe release directory" unless stat.directory? && stat.uid == Process.uid && (stat.mode & 0o022).zero?
    end
    actual = Dir.children(destination).grep_v(/\A(?:bin|spotify)\z/) +
      Dir.children(directories[1]).map { |name| "spotify/#{name}" } +
      Dir.children(directories[2]).map { |name| "bin/#{name}" }
    raise "Unexpected installed files" unless actual.sort == expected.sort
    entries.each do |path, digest|
      file = File.join(destination, path)
      raise "Release file mismatch: #{path}" unless Digest::SHA256.hexdigest(read_regular(file)) == digest
      raise "Release helper is not executable: #{path}" if path.start_with?("bin/") && !File.executable?(file)
    end
    info = JSON.parse(read_regular(File.join(destination, "BUILD-INFO.json")))
    raise "Architecture mismatch" unless info["architecture"] == IO.popen(["/usr/bin/uname", "-m"], &:read).strip
    [info.fetch("buildID"), Digest::SHA256.hexdigest(raw)]
  end

  def registered(target)
    id = release_id(target)
    identity, digest = verify(target)
    raise "Release is not registered or has been changed" unless
      value(File.join(@releases, "#{id}.sha256")) == digest && identity == id
    id
  end

  def switch_link(target)
    if target.nil?
      File.unlink(@link) if entry?(@link)
      return
    end
    temporary = File.join(File.dirname(@link), ".SpotifyVolume.#{SecureRandom.hex(12)}")
    File.symlink(target, temporary)
    File.rename(temporary, @link)
  ensure
    File.unlink(temporary) if temporary && File.symlink?(temporary)
  end

  def install(args)
    raise "Usage: install [--files-only]" unless args.empty? || args == ["--files-only"]
    current = resolved_link
    release_id(current)
    build = File.join(ROOT, "scripts", "build")
    raise "Use the version-specific installer to install a release" unless File.executable?(build)
    Dir.mktmpdir("spotify-build-", @root) do |stage|
      output = File.join(stage, "artifact")
      raise "Build failed" unless system(build, output, out: $stderr)
      source = File.join(output, "SpotifyVolume.spoon")
      id, digest = verify_content(source)
      target = bundle(id)
      if entry?(File.dirname(target)) && !entry?(File.join(@releases, "#{id}.sha256"))
        raise "Active release is missing its registration" if current == target
        # A crash after moving a new release can leave an unregistered directory.
        # Preserve it for inspection and install a fresh verified build.
        File.rename(File.dirname(target), File.join(@releases, ".incomplete-#{SecureRandom.hex(12)}"))
      end
      if entry?(File.dirname(target))
        registered(target)
      else
        File.rename(output, File.dirname(target))
        atomic(File.join(@releases, "#{id}.sha256"), digest)
      end
      registered(target)
      atomic(File.join(@root, "spotify-volume"), read_regular(__FILE__), 0o700)
      active = (value(@init)&.include?(MANAGED) rescue false) && entry?(@keys)
      stage_change(target, current, {}) unless current == target
      if current != target && active
        puts "Installed #{id}. Reload Config in Hammerspoon, then run status --after-reload."
      else
        settle if entry?(@pending)
        puts "Installed #{id}."
        if !active && args.empty? && $stdin.tty? && yes?("Configure shortcuts now?")
          configure
        elsif !active
          puts "Run configure to choose shortcuts when ready."
        end
      end
    end
  end

  def yes?(prompt)
    print "#{prompt} [y/N] "
    $stdout.flush
    $stdin.gets.to_s.strip.casecmp("y").zero?
  end

  def interactive?
    $stdin.tty?
  end

  def capture_selection(target, arguments)
    output, result = Open3.capture2(File.join(target, "bin", "spotify-volume-keys"), *arguments)
    return nil if result.exitstatus == 2
    raise "Could not capture shortcuts" unless result.success?
    output
  end

  def configure
    target = resolved_link
    id = registered(target)
    raise "Configure needs an interactive terminal" unless interactive?
    retry_path = File.join(@state, "shortcut-retry.json")
    arguments = entry?(retry_path) ? [read_regular(retry_path)] : []
    output = capture_selection(target, arguments)
    return puts "Shortcut setup cancelled." unless output
    selection = JSON.parse(output)
    manual_config = File.symlink?(@init)
    original = manual_config ? nil : value(@init)
    managed = original&.include?(MANAGED)
    manual_config ||= !managed && original.to_s.include?("SpotifyVolume")
    puts "Volume down: #{selection.fetch("down").fetch("label")}"
    puts "Volume up: #{selection.fetch("up").fetch("label")}"
    puts "\n#{MANAGED}" unless managed
    puts "Apply the displayed loader yourself in your managed Hammerspoon configuration." if manual_config
    return puts "Configuration unchanged." unless yes?("Apply these shortcuts?")
    raise "Configuration changed during review" unless manual_config || value(@init) == original
    changes = {@keys => output}
    if !managed && !manual_config
      if original
        backup = File.join(@state, "init-backup-#{SecureRandom.hex(8)}.lua")
        File.open(backup, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
          file.write(original)
          file.fsync
        end
      end
      changes[@init] = original.to_s + "\n" + MANAGED
    end
    stage_change(target, target, changes, true)
    File.unlink(retry_path) if entry?(retry_path)
    puts "#{id}: Reload Config from Hammerspoon, then run status --after-reload and test both shortcuts."
  end

  def stage_change(target, current, changes, force_activation = false)
    previous_id = release_id(current)
    previous_id = nil unless previous_id && entry?(File.join(@releases, "#{previous_id}.sha256"))
    managed = (value(@init)&.include?(MANAGED) rescue false)
    record = {
      "target" => target, "current" => current, "previous" => value(@previous),
      "next_previous" => current == target ? value(@previous) : previous_id,
      "activation" => force_activation || (managed && entry?(@keys)),
      "started" => Time.now.to_f, "changes" => changes.each_with_object({}) do |(path, after), entries|
        entries[path] = {
          "before" => value(path), "after" => after,
          "mode" => entry?(path) ? File.stat(path).mode & 0o777 : 0o600,
        }
      end
    }
    atomic(@pending, JSON.generate(record))
    begin
      changes.each { |path, contents| atomic(path, contents, record["changes"][path]["mode"]) }
      switch_link(target) if target != current
    rescue StandardError
      restore(record)
      raise
    end
  end

  def restore(record)
    actual = resolved_link
    raise "Spoon link changed outside the installer" unless [record["target"], record["current"]].include?(actual)
    record.fetch("changes").each do |path, change|
      actual_contents = value(path)
      next if actual_contents == change["before"]
      raise "Configuration changed outside the installer: #{path}" unless actual_contents == change["after"]
    end
    previous_target = record["current"]
    previous_id = release_id(previous_target)
    registered(previous_target) if previous_id && entry?(File.join(@releases, "#{previous_id}.sha256"))
    record.fetch("changes").each do |path, change|
      next if value(path) == change["before"]
      change["before"] ? atomic(path, change["before"], change["mode"]) : File.unlink(path)
    end
    switch_link(record["current"]) unless actual == record["current"]
    File.unlink(@pending)
  end

  def observed_runtime
    raw = value(@status)
    raw && JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end

  def settle
    record = JSON.parse(read_regular(@pending))
    target = record.fetch("target")
    id = registered(target)
    applied = resolved_link == target && record.fetch("changes").all? do |path, change|
      value(path) == change["after"]
    end
    unless applied
      restore(record)
      return
    end
    if record.fetch("activation")
      runtime = observed_runtime
      return unless runtime && runtime["buildID"] == id && runtime["loadedAt"].to_f >= record.fetch("started")
      return unless live_process?(runtime["hammerspoonPID"], "Hammerspoon")
      if runtime["configurationError"]
        candidate = record.dig("changes", @keys, "after")
        direction = runtime["configurationError"][/volume (down|up)\z/, 1]
        if candidate && direction
          atomic(File.join(@state, "shortcut-retry.json"), JSON.generate({
            "selection" => JSON.parse(candidate), "direction" => direction,
          }))
        end
        restore(record)
        raise "#{runtime['configurationError']}. Previous configuration restored. Reload Config and run configure again."
      end
      return unless runtime["started"] == true
    end
    atomic(@previous, record["next_previous"].to_s)
    File.unlink(@pending)
  end

  def live_process?(pid, name, parent = nil, path = nil)
    return false unless pid.is_a?(Integer) && pid > 1
    data, result = Open3.capture2("/bin/ps", "-p", pid.to_s, "-o", "uid=,ppid=,comm=")
    uid, ppid, executable = data.strip.split(/\s+/, 3)
    result.success? && uid == Process.uid.to_s && executable && File.basename(executable) == name &&
      (!parent || ppid == parent.to_s) && (!path || executable == path)
  end

  def status(args)
    raise "Usage: status [--after-reload]" unless args.empty? || args == ["--after-reload"]
    if args == ["--after-reload"] && entry?(@pending)
      5.times do
        sleep 1
        settle
        break unless entry?(@pending)
      end
      if entry?(@pending)
        restore(JSON.parse(read_regular(@pending)))
        raise "No new runtime reported after reload. Previous configuration restored. Reload Config again."
      end
    end
    target = resolved_link
    return puts "Not installed." unless target
    id = registered(target)
    return puts "#{id}: activation pending. Reload Config in Hammerspoon." if entry?(@pending)
    runtime = observed_runtime
    return puts "#{id}: installed, inactive. Run configure to activate." unless
      runtime && runtime["buildID"] == id && live_process?(runtime["hammerspoonPID"], "Hammerspoon")
    return puts "#{id}: #{runtime["configurationError"]}" if runtime["configurationError"]
    unless runtime.dig("spotify", "running")
      puts "#{id}: active, waiting for Spotify."
      return
    end
    parent = runtime["hammerspoonPID"]
    control = runtime.fetch("control")
    if runtime.dig("volume", "synchronized") && control["ready"] &&
       live_process?(control["pid"], "spotify-control", parent, File.join(target, "bin", "spotify-control"))
      puts "#{id}: active. Spotify volume control ready."
    else
      puts "#{id}: active. Spotify synchronization pending or failed."
      message = control["lastError"] || runtime.dig("volume", "lastError")
      puts "Spotify Automation or worker error: #{message}" if message
    end
  end

  def rollback
    if entry?(@pending)
      restore(JSON.parse(read_regular(@pending)))
      return puts "Pending change reverted. Reload Config in Hammerspoon."
    end
    id = value(@previous)
    target = bundle(id)
    registered(target)
    stage_change(target, resolved_link, {})
    puts "Selected #{id}. Reload Config in Hammerspoon, then run status --after-reload."
  end

  def uninstall(args)
    raise "Usage: uninstall [--purge-state]" unless args.empty? || args == ["--purge-state"]
    current = resolved_link
    registered(current) if current
    if args == ["--purge-state"]
      runtime = observed_runtime
      if runtime && %w[control helper].any? do |worker|
           name = worker == "control" ? "spotify-control" : "spotify-osd"
           live_process?(runtime.dig(worker, "pid"), name, runtime["hammerspoonPID"])
         end
        raise "Detach the Spoon and reload Hammerspoon before purging state"
      end
    end
    original = File.symlink?(@init) ? nil : value(@init)
    atomic(@init, original.sub(MANAGED, ""), File.stat(@init).mode & 0o777) if original&.include?(MANAGED)
    switch_link(nil) if current
    if args == ["--purge-state"]
      [@keys, @status, File.join(@state, "segment")].each { |path| File.unlink(path) if entry?(path) }
    end
    puts "SpotifyVolume files detached. Reload Config in Hammerspoon. Verified releases retained."
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    Lifecycle.new.run(ARGV.shift, ARGV)
  rescue StandardError => error
    warn "SpotifyVolume: #{error.message}"
    exit 1
  end
end
