# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "open3"
require "tmpdir"
require_relative "../lib/autoupdate/config"
require_relative "../lib/autoupdate/interval"
require_relative "../lib/autoupdate/launch_agent"
require_relative "../lib/autoupdate/script"

class ScriptTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("autoupdate-script")
    @brew = File.join(@dir, "brew")
    # Records each invocation; `upgrade` fails when FAIL_UPGRADE is set.
    write_executable(@brew, <<~SH)
      #!/bin/sh
      echo "brew $*" >&2
      [ "$1" = leaves ] && printf 'wget\\ngit\\n'
      [ "$1" = upgrade ] && [ -n "${FAIL_UPGRADE:-}" ] && exit 2
      # Like `brew outdated <names>` when something is outdated.
      [ "$1" = outdated ] && echo '{"formulae":[],"casks":[]}' && exit 1
      exit 0
    SH
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_update_only_runs_brew_update
    output, status = run_updater(config)

    assert_predicate status, :success?
    assert_equal ["brew update"], brew_calls(output)
  end

  def test_upgrade_runs_non_interactive_formula_and_cask_upgrades
    output, = run_updater(config(upgrade: true, greedy: true, cleanup: true))

    assert_equal [
      "brew update",
      "brew outdated --json=v2 --greedy",
      "brew upgrade --no-ask --formula -v",
      "brew upgrade --no-ask --cask -v --greedy",
      "brew cleanup",
    ], brew_calls(output)
  end

  def test_casks_are_skipped_when_none_are_installed
    output, = run_updater(config(upgrade: true), casks: false)

    assert_equal ["brew update", "brew outdated --json=v2 --formula", "brew upgrade --no-ask --formula -v"],
                 brew_calls(output)
  end

  def test_only_upgrades_the_listed_packages
    output, = run_updater(config(upgrade: true, greedy: true, only: %w[wget firefox]))

    assert_equal ["brew update", "brew outdated --json=v2 --greedy wget firefox",
                  "brew upgrade --no-ask -v --greedy wget firefox"], brew_calls(output)
  end

  def test_leaves_only_upgrades_top_level_formulae
    output, status = run_updater(config(upgrade: true, leaves_only: true), casks: false)

    assert_predicate status, :success?
    assert_equal ["brew update", "brew leaves", "brew outdated --json=v2 --formula wget git",
                  "brew upgrade --no-ask --formula -v wget git"], brew_calls(output)
  end

  def test_outdated_packages_do_not_stop_the_run
    output, status = run_updater(config(upgrade: true, only: %w[wget]))

    assert_predicate status, :success?
    assert_includes brew_calls(output), "brew upgrade --no-ask -v wget"
  end

  def test_leaves_only_reports_failed_upgrades
    output, status = run_updater(config(upgrade: true, leaves_only: true), casks: false,
                                                                           env:   { "FAIL_UPGRADE" => "1" })

    assert_equal 2, status.exitstatus
    assert_includes output, "notify 2"
  end

  def test_a_failed_step_stops_the_run_and_is_reported
    output, status = run_updater(config(upgrade: true, cleanup: true), env: { "FAIL_UPGRADE" => "1" })

    assert_equal 2, status.exitstatus
    assert_equal ["brew update", "brew outdated --json=v2", "brew upgrade --no-ask --formula -v"], brew_calls(output)
    assert_includes output, "notify 2"
  end

  def test_each_run_writes_its_own_log
    output, = run_updater(config)

    assert_match(%r{exit status 0; see #{Regexp.escape(@dir)}/runs/\d{4}-\d\d-\d\d-\d{6}\.log}, output)
  end

  def test_only_the_newest_runs_are_kept
    FileUtils.mkdir_p(File.join(@dir, "runs"))
    (1..Autoupdate::Script::KEPT_RUNS).each do |day|
      FileUtils.touch(File.join(@dir, "runs", format("2000-01-%02d-000000.log", day)))
    end
    run_updater(config)

    assert_equal Autoupdate::Script::KEPT_RUNS, run_logs.length
    refute_includes run_logs, File.join(@dir, "runs", "2000-01-01-000000.log")
  end

  def test_reminds_to_restart_when_the_tap_has_changed
    output, = run_updater(config(commit: "0" * 40))

    assert_includes output, "notify 0 #{Autoupdate::Script::RESTART_REMINDER}"
  end

  def test_does_not_remind_at_the_commit_the_job_was_started_from
    tap = File.join(@dir, "tap")
    system("git", "init", "--quiet", tap, exception: true)
    system("git", "-C", tap, "-c", "user.name=t", "-c", "user.email=t@example.com",
           "commit", "--quiet", "--allow-empty", "--message=t", exception: true)
    output, = run_updater(config(commit: `git -C #{tap} rev-parse HEAD`.strip))

    refute_includes output, Autoupdate::Script::RESTART_REMINDER
  end

  def test_records_whether_the_run_had_app_management
    # Checked before /Applications; outside it, macOS does not protect apps.
    FileUtils.mkdir_p(File.join(@dir, "Applications", "Example.app"))
    run_updater(config(upgrade: true), env: { "HOME" => @dir, "BREW_AUTOUPDATE_RUN_BY_APP" => "1" })

    assert_match(/\Agranted \(/, File.read(File.join(@dir, "app_management")))
  end

  def test_does_not_check_app_management_outside_the_app
    run_updater(config(upgrade: true), env: { "BREW_AUTOUPDATE_RUN_BY_APP" => nil })

    assert_match(/\Anot checked: this run did not go through/, File.read(File.join(@dir, "app_management")))
  end

  def test_exports_the_captured_environment
    environment = { "PATH" => "/usr/bin:/bin", "HOMEBREW_CASK_OPTS" => "--appdir=~/My Apps" }
    script = Autoupdate::Script.updater(config(environment:), **paths)

    assert_includes script, "export HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK=1"
    output, = Open3.capture2e("/bin/sh", "-c", "#{exports(script)}\necho \"$HOMEBREW_CASK_OPTS\"")

    assert_equal "--appdir=~/My Apps\n", output
  end

  def test_sudo_points_sudo_askpass_at_the_generated_prompt
    script = Autoupdate::Script.updater(config(sudo: true), **paths)
    output, = Open3.capture2e("/bin/sh", "-c", "#{exports(script)}\necho \"$SUDO_ASKPASS\"")

    assert_equal "#{@dir}/sudo askpass\n", output
  end

  def test_ac_only_skips_the_run_on_battery_power
    assert_includes Autoupdate::Script.updater(config(ac_only: true), **paths), "/usr/bin/pmset -g ps"
    refute_includes Autoupdate::Script.updater(config, **paths), "pmset"
  end

  def test_sudo_askpass_prints_the_decoded_pin
    prefix = File.join(@dir, "prefix")
    FileUtils.mkdir_p(File.join(prefix, "bin"))
    write_executable(File.join(prefix, "bin", "pinentry-mac"), <<~SH)
      #!/bin/sh
      /bin/cat >/dev/null
      printf 'OK\\nD p%%25ss w0rd\\nOK\\n'
    SH
    askpass = File.join(@dir, "askpass")
    write_executable(askpass, Autoupdate::Script.sudo_askpass(prefix:, icon: "/icon.icns"))
    output, status = Open3.capture2(askpass)

    assert_predicate status, :success?
    assert_equal "p%ss w0rd\n", output
  end

  def test_launch_agent_runs_the_program_on_the_requested_schedule
    daily = plist(interval: Autoupdate::Interval.parse("02:23"), run_at_load: true)
    relative = plist(interval: 3600, run_at_load: false)

    assert_equal "/support/brew_autoupdate_launcher", daily.fetch("Program")
    assert_equal ["/support/brew_autoupdate_launcher"], daily.fetch("ProgramArguments")
    assert_equal({ "Hour" => 2, "Minute" => 23 }, daily.fetch("StartCalendarInterval"))
    assert daily.fetch("RunAtLoad")
    assert_equal 3600, relative.fetch("StartInterval")
    refute relative.key?("RunAtLoad")
    assert_equal "Background", relative.fetch("ProcessType")
  end

  private

  def config(**options)
    Autoupdate::Config.new(
      interval: 86_400, run_at_load: false, upgrade: false, greedy: false, cleanup: false,
      sudo: false, leaves_only: false, only: nil, ac_only: false, notify: "always",
      environment: { "PATH" => "/usr/bin:/bin" }, **options
    )
  end

  def paths(casks: true)
    {
      brew:                @brew,
      casks:,
      sudo_askpass:        File.join(@dir, "sudo askpass"),
      notify_command:      'echo "notify $status $reminder"',
      runs:                File.join(@dir, "runs"),
      tap:                 File.join(@dir, "tap"),
      app_management_file: File.join(@dir, "app_management"),
    }
  end

  # Returns the updater's own output followed by the latest run's log.
  def run_updater(config, casks: true, env: {})
    updater = File.join(@dir, "updater")
    write_executable(updater, Autoupdate::Script.updater(config, **paths(casks:)))
    output, status = Open3.capture2e(env, updater)
    ["#{output}#{run_logs.last&.then { |log| File.read(log) }}", status]
  end

  def run_logs
    Dir[File.join(@dir, "runs", "*.log")]
  end

  def brew_calls(output)
    output.lines(chomp: true).grep(/\Abrew /).map { |line| line.sub(@brew, "brew") }
  end

  def exports(script)
    script.lines.grep(/\Aexport /).join
  end

  def plist(**options)
    xml = Autoupdate::LaunchAgent.plist(
      label: "test", program: "/support/brew_autoupdate_launcher", log: "/logs/out", **options,
    )
    json, = Open3.capture2("/usr/bin/plutil", "-convert", "json", "-o", "-", "-", stdin_data: xml)
    JSON.parse(json)
  end

  def write_executable(path, contents)
    File.write(path, contents)
    FileUtils.chmod(0755, path)
  end
end
