# frozen_string_literal: true

module Homebrew
  module Cmd
    class Autoupdate < AbstractCommand
      class StopSubcommand < AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            `autoupdate stop`:
            Stop autoupdating while retaining the launch agent, configuration, and logs.
          EOS
          named_args :none
        end

        def run
          odie "Autoupdate is not currently running; cannot stop a command that is not running." unless ::Autoupdate::Launchd.loaded?

          ::Autoupdate::Launchd.unload
          puts "Homebrew will no longer autoupdate."
        end
      end
    end
  end
end
