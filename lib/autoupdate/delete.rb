# frozen_string_literal: true

module Homebrew
  module Cmd
    class Autoupdate < AbstractCommand
      class DeleteSubcommand < AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            `autoupdate delete`:
            Stop autoupdating and delete everything `start` created: the launch agent,
            app, signing certificate, configuration, and logs.
          EOS
          named_args :none
        end

        def run
          ::Autoupdate::Launchd.unload
          ::Autoupdate::Signing.delete
          FileUtils.rm_f Dir[File.join(::Autoupdate::Core.fallback_logs, "#{::Autoupdate::Core.name}.*")]
          FileUtils.rm_f ::Autoupdate::Core.plist
          FileUtils.rm_rf ::Autoupdate::Core.location
          FileUtils.rm_rf ::Autoupdate::Core.logs

          puts "Homebrew will no longer autoupdate and the plist has been deleted."
        end
      end
    end
  end
end
