# frozen_string_literal: true

require "shellwords"

module Autoupdate
  # The command the updater script runs to report each run's result.
  module Notify
    module_function

    def command(mode:)
      [
        Shellwords.escape(Autoupdate::Core.notify_script.to_s),
        "\"$status\"",
        "\"$run_log\"",
        Shellwords.escape(mode),
        Shellwords.escape(Autoupdate::Core.app.to_s),
        "\"$reminder\"",
      ].join(" ")
    end
  end
end
