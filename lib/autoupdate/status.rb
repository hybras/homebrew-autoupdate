# frozen_string_literal: true

module Homebrew
  module Cmd
    class Autoupdate < AbstractCommand
      class StatusSubcommand < AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            `autoupdate status`:
            Show whether autoupdate is running and describe its installed configuration.
          EOS
          named_args :none
        end

        def run
          running = ::Autoupdate::Launchd.loaded?
          config_file = ::Autoupdate::Core.config_file

          if config_file.exist?
            core = ::Autoupdate::Core
            puts "Autoupdate is installed and #{running ? "running" : "stopped"}."
            puts
            puts "Last started: #{config_file.mtime.strftime("%F")}"
            begin
              config = ::Autoupdate::Config.load(config_file)
            rescue JSON::ParserError, ArgumentError => e
              puts "Configuration: unable to read #{config_file} (#{e.message})"
              return
            end
            puts config.summary(casks: core.casks_installed?)
            puts "Logs: #{core.runs}"
            signature = Utils.popen_read("/usr/bin/codesign", "-dvv", core.app, err: :out)
            puts "App: #{core.app}, signed by #{signature[/^Authority=(.+)$/, 1] || "nobody (missing or unsigned)"}"
            if core.app_management_file.exist?
              puts "App Management at the last run: #{core.app_management_file.read.strip}"
            end
            if config.commit && config.commit != core.tap_commit
              puts
              puts ::Autoupdate::Script::RESTART_REMINDER
            end
          elsif running || File.exist?(::Autoupdate::Core.plist)
            puts <<~EOS
              Autoupdate cannot determine its status.
              Please feel free to file an issue with further information here:
              https://github.com/hybras/homebrew-autoupdate/issues
            EOS
          else
            puts "Autoupdate is not configured. Use `brew autoupdate start` to begin."
          end
        end
      end
    end
  end
end
