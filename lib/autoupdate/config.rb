# frozen_string_literal: true

require "json"
require_relative "interval"

module Autoupdate
  # The options chosen with `brew autoupdate start`, plus the environment
  # captured when it ran. They are saved so that every `start` can regenerate
  # the scripts from them, and so `status` can describe them.
  Config = Struct.new(
    :interval,    # Integer seconds, or an Interval::CalendarTime
    :run_at_load, # also run when the agent is loaded (`--immediate`)
    :upgrade,
    :greedy,
    :cleanup,
    :sudo,        # prompt for a password with pinentry-mac
    :leaves_only,
    :only,        # Array of package names, or nil
    :ac_only,
    :notify,      # "always", "error" or "never"
    :environment, # Hash of variables exported to every run
    keyword_init: true,
  )

  class Config
    # Bump when the saved format changes incompatibly.
    FORMAT_VERSION = 1

    def self.load(path)
      data = JSON.parse(File.read(path))
      version = data.delete("version")
      raise ArgumentError, "unsupported configuration version #{version.inspect}" if version != FORMAT_VERSION

      new(**data.transform_keys(&:to_sym)).tap do |config|
        config.interval = Autoupdate::Interval.parse(config.interval)
      end
    end

    def save(path)
      File.write(path, "#{JSON.pretty_generate({ "version" => FORMAT_VERSION, **to_h, interval: interval.to_s })}\n")
    end

    def summary(casks:)
      details = []
      details << if interval.is_a?(Integer)
        "Schedule: every #{Autoupdate::Interval.describe(interval)} (#{interval} seconds)"
      else
        "Schedule: every #{Autoupdate::Interval.describe(interval)}"
      end
      details << "Run at login: #{yes_no(run_at_load)}"
      details << "Upgrade: #{upgrade_summary(casks:)}"
      details << "Cleanup: #{yes_no(cleanup)}"
      details << "AC power only: #{yes_no(ac_only)}"
      details << "Greedy cask upgrades: yes" if upgrade && greedy
      details << "GUI sudo prompt: yes" if sudo
      details << "Notifications: #{{ "always" => "yes", "error" => "failures only" }.fetch(notify, "no")}"
      details
    end

    private

    def upgrade_summary(casks:)
      return "no" unless upgrade
      return "top-level formulae only" if leaves_only
      return "selected packages (#{only.join(", ")})" if only

      casks ? "formulae and casks" : "formulae only"
    end

    def yes_no(value)
      value ? "yes" : "no"
    end
  end
end
