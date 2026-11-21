# frozen_string_literal: true

module Homebrew
  module Cmd
    class Autoupdate < AbstractCommand
      class LogsSubcommand < AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            `autoupdate logs` [<options>]:
            Show output from autoupdate runs.
          EOS

          switch "-f", "--follow",
                 description: "Follow the log as new output is written."
          flag "-n=", "--lines=",
               description: "Show this many lines from the end of the log. Defaults to 10."
          named_args :none
        end

        def run
          lines = args.lines.blank? ? 10 : Integer(args.lines, exception: false)
          raise UsageError, "`--lines` must be a positive integer." unless lines&.positive?

          log_file = File.join(::Autoupdate::Core.logs, "#{::Autoupdate::Core.name}.out")
          fallback_log_file = File.join(::Autoupdate::Core.fallback_logs, "#{::Autoupdate::Core.name}.out")
          file_to_read = [log_file, fallback_log_file].find { |file| File.exist?(file) }
          if file_to_read.nil?
            puts "No autoupdate log file found at `#{log_file}` or fallback `#{fallback_log_file}`."
            return
          end

          system("tail", "-n", lines.to_s, *("-f" if args.follow?), file_to_read)
        end
      end
    end
  end
end
