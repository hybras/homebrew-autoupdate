# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "open3"
require "timeout"
require "tmpdir"
require_relative "../lib/autoupdate/launcher"

class LauncherTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("autoupdate-launcher")
    @location = File.join(@dir, "support")
    @log = File.join(@dir, "logs", "autoupdate.out")
    @app = File.join(@dir, "brew-autoupdate.app")
    FileUtils.mkdir_p([@location, File.dirname(@log), File.join(@app, "Contents")])
    write_executable(File.join(@location, "brew_autoupdate"), "#!/bin/sh\necho ran-directly\nexit 3\n")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_detects_the_run_updater_capability
    write_info_plist(capable: false)

    refute Autoupdate::Launcher.app_supports_run_updater?(@app)

    write_info_plist(capable: true)

    assert Autoupdate::Launcher.app_supports_run_updater?(@app)
    refute Autoupdate::Launcher.app_supports_run_updater?(File.join(@dir, "missing.app"))
  end

  def test_runs_the_updater_directly_when_the_app_lacks_support
    write_info_plist(capable: false)
    stdout, _stderr, status = run_launcher(fake_open("echo open-called; exit 0"))

    assert_equal 3, status.exitstatus
    assert_equal "ran-directly\n", stdout
  end

  def test_opens_the_app_in_updater_mode_and_returns_its_status
    write_info_plist(capable: true)
    open = fake_open(<<~SH)
      printf '<%s>\\n' "$@"
      echo 7 > #{Shellwords.escape(File.join(@location, "brew_autoupdate.status"))}
    SH
    stdout, _stderr, status = run_launcher(open)

    assert_equal 7, status.exitstatus
    assert_equal(
      ["<-W>", "<-g>", "<-n>", "<#{@app}>", "<--args>", "<--run-updater>", "<#{@log}>"],
      stdout.lines(chomp: true),
    )
  end

  def test_reports_failure_when_the_app_exits_without_a_status
    write_info_plist(capable: true)
    File.write(File.join(@location, "brew_autoupdate.status"), "0\n")
    _stdout, _stderr, status = run_launcher(fake_open("exit 0"))

    assert_equal 1, status.exitstatus
  end

  def test_falls_back_to_the_updater_when_the_app_cannot_be_opened
    write_info_plist(capable: true)
    stdout, stderr, status = run_launcher(fake_open("exit 1"))

    assert_equal 3, status.exitstatus
    assert_equal "ran-directly\n", stdout
    assert_includes stderr, "running the updater directly"
  end

  def test_stopping_the_launcher_stops_the_running_app
    write_info_plist(capable: true)
    # `ps -o comm=` reports argv[0], so this stands in for the running app.
    app_process = File.join(@dir, "brew-autoupdate-notifier")
    pid_file = File.join(@location, "brew_autoupdate.pid")
    open = fake_open(<<~SH)
      /bin/bash -c 'exec -a "$0" /bin/sleep 30' #{Shellwords.escape(app_process)} &
      echo "$!" > #{Shellwords.escape(pid_file)}
      wait "$!"
    SH

    launcher = launcher_path(open)
    pid = Process.spawn(launcher, out: File::NULL, err: File::NULL)
    Timeout.timeout(10) { sleep 0.1 until File.size?(pid_file) }
    app_pid = File.read(pid_file).to_i
    Process.kill("TERM", pid)
    _, launcher_status = Timeout.timeout(10) { Process.wait2(pid) }

    assert_equal 143, launcher_status.exitstatus
    Timeout.timeout(10) do
      sleep 0.1 while process_alive?(app_pid)
    end
  ensure
    begin
      Process.kill("KILL", app_pid) if app_pid && process_alive?(app_pid)
    rescue Errno::ESRCH
      nil
    end
  end

  private

  def write_executable(path, contents)
    File.write(path, contents)
    FileUtils.chmod(0755, path)
  end

  def write_info_plist(capable:)
    capabilities = capable ? "<key>BrewAutoupdateCapabilities</key><array><string>run-updater</string></array>" : ""
    File.write(File.join(@app, "Contents", "Info.plist"), <<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict>#{capabilities}</dict></plist>
    XML
  end

  def fake_open(body)
    path = File.join(@dir, "open")
    write_executable(path, "#!/bin/sh\n#{body}\n")
    path
  end

  def launcher_path(open)
    path = Autoupdate::Launcher.path(@location)
    contents = Autoupdate::Launcher.script(app: @app, location: @location, log: @log, open:)
    write_executable(path, contents)
    path
  end

  def run_launcher(open)
    Open3.capture3(launcher_path(open))
  end

  # A terminated child stays a zombie until its parent reaps it, so check the
  # process state rather than whether the PID still exists.
  def process_alive?(pid)
    state, = Open3.capture2("/bin/ps", "-o", "stat=", "-p", pid.to_s)
    !state.strip.empty? && !state.start_with?("Z")
  end
end
