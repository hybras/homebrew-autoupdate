# frozen_string_literal: true

require "minitest/autorun"
require "digest"
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

  def test_committed_app_matches_the_shared_version
    plist = File.join(ROOT, "app/brew-autoupdate.app/Contents/Info.plist")
    output, status = Open3.capture2(
      "/usr/bin/plutil",
      "-extract",
      "CFBundleShortVersionString",
      "raw",
      plist,
    )

    assert_predicate status, :success?
    assert_equal VERSION, output.strip
  end

  def test_committed_app_has_a_valid_signature
    app = File.join(ROOT, "app/brew-autoupdate.app")
    _stdout, stderr, status = Open3.capture3(
      "/usr/bin/codesign",
      "--verify",
      "--deep",
      "--strict",
      app,
    )

    assert_predicate status, :success?, stderr
  end

  def test_committed_app_was_built_from_the_current_sources
    plist = File.join(ROOT, "app/brew-autoupdate.app/Contents/Info.plist")
    output, = Open3.capture2("/usr/bin/plutil", "-extract", "BrewAutoupdateSourcesSHA256", "raw", plist)
    sources = %w[app/BrewAutoupdate.swift app/build.sh].map { |path| File.binread(File.join(ROOT, path)) }

    assert_equal Digest::SHA256.hexdigest(sources.join), output.strip,
                 "Rebuild the committed app with app/build.sh"
  end

  def test_committed_app_runs_as_a_background_ui_helper
    plist = File.join(ROOT, "app/brew-autoupdate.app/Contents/Info.plist")
    output, status = Open3.capture2(
      "/usr/bin/plutil",
      "-extract",
      "LSUIElement",
      "raw",
      plist,
    )

    assert_predicate status, :success?
    assert_equal "true", output.strip
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

  def test_the_old_notifier_path_forwards_to_the_renamed_script
    Tempfile.create("autoupdate-notify") do |log|
      log.write("Already up-to-date.\n")
      log.flush
      stdout, status = Open3.capture2(
        { "AUTOUPDATE_NOTIFY_PRINT" => "1" },
        File.join(ROOT, "notifier/notify.sh"), "0", log.path, "always", "/old/notifier/brew-autoupdate.app"
      )

      assert_predicate status, :success?
      assert_includes stdout, "Homebrew is already up-to-date."
    end
  end

  def test_app_failure_is_reported_without_failing_autoupdate
    output, status = invoke_fake_app(0, "Already up-to-date.\n", helper_status: 1)

    assert_predicate status, :success?
    assert_includes output, "Warning: could not display the update result."
  end

  def test_built_executable_rejects_invalid_arguments
    executable = File.join(ROOT, ".build/debug/brew-autoupdate")
    skip "run `swift build` first" unless File.executable?(executable)

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
