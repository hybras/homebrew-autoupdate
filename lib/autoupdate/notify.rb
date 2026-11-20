# frozen_string_literal: true

require "shellwords"

module Autoupdate
  # The command the updater script runs to report each run's result.
  module Notify
    module_function

    def script
      File.join(Autoupdate::Core.tap_dir, "app", "notify-result.sh")
    end

    def command(mode:)
      [
        Shellwords.escape(script),
        "\"$status\"",
        "\"$run_log\"",
        Shellwords.escape(mode),
        Shellwords.escape(Autoupdate::Core.app.to_s),
      ].join(" ")
    end
  end
end
