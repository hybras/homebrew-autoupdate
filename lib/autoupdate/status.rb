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
            puts "Autoupdate is installed and #{running ? "running" : "stopped"}."
            puts
            puts "Last started: #{config_file.mtime.strftime("%F")}"
            begin
              puts ::Autoupdate::Config.load(config_file).summary(casks: ::Autoupdate::Core.casks_installed?)
            rescue JSON::ParserError, ArgumentError => e
              puts "Configuration: unable to read #{config_file} (#{e.message})"
            end
            puts "Logs: #{::Autoupdate::Core.logs}"
            if (Date.today - config_file.mtime.to_date).to_i >= 90
              puts
              puts <<~EOS
                The updater script was generated more than 90 days ago. Run
                `brew autoupdate restart` to regenerate it with the latest
                improvements; your options are kept.
              EOS
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
