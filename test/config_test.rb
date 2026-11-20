# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/autoupdate/config"

class ConfigTest < Minitest::Test
  def test_round_trips_through_the_saved_file
    [86_400, Autoupdate::Interval.parse("02:23")].each do |interval|
      config = config(interval:, only: %w[wget firefox], environment: { "PATH" => "/bin" })

      Dir.mktmpdir do |dir|
        path = File.join(dir, "config.json")
        config.save(path)

        assert_equal config, Autoupdate::Config.load(path)
      end
    end
  end

  def test_rejects_an_unknown_format_version
    Dir.mktmpdir do |dir|
      path = File.join(dir, "config.json")
      File.write(path, '{"version": 99}')

      error = assert_raises(ArgumentError) { Autoupdate::Config.load(path) }
      assert_includes error.message, "99"
    end
  end

  def test_summarizes_the_options
    summary = config(interval: Autoupdate::Interval.parse("02:23"), upgrade: true, greedy: true,
                     sudo: true, notify: "error").summary(casks: true)

    assert_equal [
      "Schedule: every day at 02:23",
      "Run at login: no",
      "Upgrade: formulae and casks",
      "Cleanup: no",
      "AC power only: no",
      "Greedy cask upgrades: yes",
      "GUI sudo prompt: yes",
      "Notifications: failures only",
    ], summary
  end

  def test_summarizes_what_is_upgraded
    assert_includes config.summary(casks: true), "Upgrade: no"
    assert_includes config(upgrade: true).summary(casks: false), "Upgrade: formulae only"
    assert_includes config(upgrade: true, leaves_only: true).summary(casks: true), "Upgrade: top-level formulae only"
    assert_includes config(upgrade: true, only: %w[wget git]).summary(casks: true),
                    "Upgrade: selected packages (wget, git)"
    assert_includes config(interval: 3600).summary(casks: true), "Schedule: every 1 hour (3600 seconds)"
  end

  private

  def config(**options)
    Autoupdate::Config.new(
      interval: 86_400, run_at_load: false, upgrade: false, greedy: false, cleanup: false,
      sudo: false, leaves_only: false, only: nil, ac_only: false, notify: "always",
      environment: {}, **options
    )
  end
end
