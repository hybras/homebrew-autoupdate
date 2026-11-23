# frozen_string_literal: true

module Homebrew
  module Cmd
    class Autoupdate < AbstractCommand
      class LogsSubcommand < AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            `autoupdate logs` [<options>]:
            Show the output of the latest autoupdate run.
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

          runs = ::Autoupdate::Core.runs
          # Names sort by time.
          latest = runs.glob("*.log").max
          if latest.nil?
            puts "No autoupdate runs have been logged in #{runs} yet."
            return
          end

          ohai latest
          system("tail", "-n", lines.to_s, *("-f" if args.follow?), latest.to_s)
        end
      end
    end
  end
end
