# frozen_string_literal: true

module Homebrew
  module Cmd
    class Autoupdate < AbstractCommand
      class RestartSubcommand < AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            `autoupdate restart`:
            Start autoupdating again with the saved options.
            Stops it first if it is running, and uses this tap's current version.
          EOS
          named_args :none
        end

        def run
          config_file = ::Autoupdate::Core.config_file
          odie "Autoupdate has not been started. Use `brew autoupdate start` to begin." unless config_file.exist?

          ::Autoupdate::Launchd.unload
          ::Autoupdate::Setup.start(::Autoupdate::Config.load(config_file))
        end
      end
    end
  end
end
