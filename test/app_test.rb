# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "open3"
require "tempfile"
require "tmpdir"

class AppTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__).freeze
  SCRIPT = File.expand_path("../app/notify-result.sh", __dir__).freeze
  VERSION = File.read(File.join(ROOT, "VERSION")).strip.freeze

  def test_reports_an_up_to_date_run
    output, status = summarize(0, "==> Updating Homebrew...\nAlready up-to-date.\n")

    assert_predicate status, :success?
    assert_includes output, "Homebrew autoupdate completed"
    assert_includes output, "Homebrew is already up-to-date."
  end

  def test_reports_an_upgrade_count
    output, status = summarize(0, "==> Upgrading 3 outdated packages:\nfoo\nbar\n")

    assert_predicate status, :success?
    assert_includes output, "==> Upgrading 3 outdated packages:"
  end

  def test_reports_a_generic_success
    output, status = summarize(0, "Updated Homebrew from abc123 to def456.\n")

    assert_predicate status, :success?
    assert_includes output, "Homebrew was updated successfully."
  end

  def test_failure_uses_only_the_current_run_tail
    log = (1..7).map { |number| "failure line #{number}" }.join("\n")
    output, status = summarize(2, log)

    assert_predicate status, :success?
    assert_includes output, "Homebrew autoupdate failed"
    assert_includes output, "Exit status 2"
    refute_includes output, "failure line 1"
    assert_includes output, "failure line 7"
  end

  def test_error_mode_suppresses_success_notifications
    output, status = summarize(0, "Already up-to-date.", mode: "error")

    assert_predicate status, :success?
    assert_empty output
  end

  def test_passes_the_summary_to_the_app
    output, status = invoke_fake_app(0, "Already up-to-date.\n")

    assert_predicate status, :success?
    assert_equal(
      [
        "<notify>",
        "<Homebrew autoupdate completed>",
        "<brew-autoupdate>",
        "<Homebrew is already up-to-date.>",
      ],
      output.lines(chomp: true),
    )
  end

  def test_app_failure_is_reported_without_failing_autoupdate
    output, status = invoke_fake_app(0, "Already up-to-date.\n", helper_status: 1)

    assert_predicate status, :success?
    assert_includes output, "Warning: could not display the update result."
  end

  def test_built_app_is_universal
    architectures, = Open3.capture2("/usr/bin/lipo", "-archs", File.join(built_app, "Contents/MacOS/brew-autoupdate"))

    assert_equal %w[arm64 x86_64], architectures.split.sort
  end

  def test_built_app_matches_the_shared_version
    assert_equal VERSION, info_plist_value("CFBundleShortVersionString")
  end

  def test_built_app_runs_as_a_background_ui_helper
    assert_equal "true", info_plist_value("LSUIElement")
  end

  def test_built_app_requires_macos_15
    assert_equal "15.0", info_plist_value("LSMinimumSystemVersion")
  end

  def test_built_executable_rejects_invalid_arguments
    executable = if (app = ENV.fetch("BREW_AUTOUPDATE_APP", nil))
      File.join(app, "Contents/MacOS/brew-autoupdate")
    else
      File.join(ROOT, ".build/debug/brew-autoupdate")
    end
    skip "run `swift build` or set BREW_AUTOUPDATE_APP" unless File.executable?(executable)

    [[], ["notify", "title"], ["run-updater", "/tmp/log"]].each do |arguments|
      _stdout, stderr, status = Open3.capture3(executable, *arguments)

      assert_equal 1, status.exitstatus
      assert_includes stderr, "usage: brew-autoupdate notify"
    end
    _stdout, stderr, status = Open3.capture3(executable, "run-updater", "/tmp/log", "not-a-pid")

    assert_equal 1, status.exitstatus
    assert_includes stderr, "invalid launcher PID"
  end

  private

  def built_app
    ENV.fetch("BREW_AUTOUPDATE_APP") { skip "set BREW_AUTOUPDATE_APP to an app built by app/build.sh" }
  end

  def info_plist_value(key)
    output, = Open3.capture2("/usr/bin/plutil", "-extract", key, "raw", File.join(built_app, "Contents/Info.plist"))
    output.strip
  end

  def summarize(exit_status, contents, mode: "always")
    Tempfile.create("autoupdate-notify") do |log|
      log.write(contents)
      log.flush
      stdout, stderr, status = Open3.capture3(
        { "AUTOUPDATE_NOTIFY_PRINT" => "1" },
        SCRIPT,
        exit_status.to_s,
        log.path,
        mode,
      )
      ["#{stdout}#{stderr}", status]
    end
  end

  def invoke_fake_app(exit_status, contents, helper_status: 0)
    Dir.mktmpdir("autoupdate-app") do |app|
      executable = File.join(app, "Contents/MacOS/brew-autoupdate")
      FileUtils.mkdir_p(File.dirname(executable))
      File.write(
        executable,
        <<~SH,
          #!/bin/bash
          printf '<%s>\\n' "$@"
          exit #{helper_status}
        SH
      )
      FileUtils.chmod(0755, executable)

      Tempfile.create("autoupdate-notify") do |log|
        log.write(contents)
        log.flush
        stdout, stderr, status = Open3.capture3(
          SCRIPT,
          exit_status.to_s,
          log.path,
          "always",
          app,
        )
        return ["#{stdout}#{stderr}", status]
      end
    end
  end
end
