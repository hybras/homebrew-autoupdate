# frozen_string_literal: true

module Autoupdate
  module Core
    module_function

    def name
      "com.github.hybras.homebrew-autoupdate"
    end

    # Changing it resets the app's App Management and notification permission.
    def bundle_id
      "#{name}.autoupdater"
    end

    def plist
      File.expand_path("~/Library/LaunchAgents/#{name}.plist")
    end

    def brew
      HOMEBREW_PREFIX/"bin/brew"
    end

    def casks_installed?
      (HOMEBREW_PREFIX/"Caskroom").exist?
    end

    def logs
      File.expand_path("~/Library/Logs/#{name}")
    end

    def fallback_logs
      File.expand_path("..", logs)
    end

    def location
      Pathname.new(File.expand_path("~/Library/Application Support/#{name}"))
    end

    # The helper app that posts notifications and runs scheduled updates.
    # `start` builds and signs it here, so tap upgrades do not change it.
    def app
      location/"brew-autoupdate.app"
    end

    # Copied from the tap by `start`, like everything else a job runs.
    def notify_script
      location/"notify-result.sh"
    end

    def config_file
      location/"config.json"
    end

    def updater
      location/"brew_autoupdate"
    end

    # The app writes each run's exit status here, since `open -W` drops it.
    def status_file
      location/"brew_autoupdate.status"
    end

    # The checkout this code was loaded from, wherever it is tapped.
    def tap_dir
      Pathname.new(File.expand_path("../..", __dir__))
    end
  end
end
