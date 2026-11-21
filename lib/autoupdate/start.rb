# frozen_string_literal: true

module Homebrew
  module Cmd
    class Autoupdate < AbstractCommand
      class StartSubcommand < AbstractSubcommand
        # Options other than the interval. Without any of them, `start` after
        # `stop` reuses the saved options.
        SWITCHES = %w[upgrade greedy cleanup immediate sudo leaves_only ac_only notify_on_error no_notify].freeze

        subcommand_args do
          usage_banner <<~EOS
            `autoupdate start` [<interval>] [<options>]:
            Start autoupdating in the background.
            The interval defaults to 24 hours and accepts seconds or a suffix such as
            `30m`, `12h`, or `1d`, or a 24-hour clock time such as `00:00` to run daily
            at that specific time.
            After `stop`, running `start` with no interval or options resumes with the
            saved options; otherwise the given ones replace them.
          EOS

          switch "--upgrade",
                 description: "Automatically upgrade installed formulae and casks."
          switch "--greedy",
                 depends_on:  "--upgrade",
                 description: "Include auto-updating casks when upgrading."
          switch "--cleanup",
                 description: "Automatically clean Homebrew's cache and logs."
          switch "--immediate",
                 description: "Run immediately and on login instead of waiting for the first interval."
          switch "--sudo",
                 depends_on:  "--upgrade",
                 description: "Open a GUI password prompt when a cask upgrade requires `sudo`. " \
                              "Requires `pinentry-mac` to be installed."
          switch "--leaves-only",
                 depends_on:  "--upgrade",
                 description: "Upgrade only top-level formulae that are not dependencies."
          comma_array "--only=",
                      description: "Upgrade only these formulae and/or casks (comma-separated). " \
                                   "Requires `--upgrade`."
          switch "--ac-only",
                 description: "Run only while the Mac is connected to AC power."
          switch "--notify-on-error",
                 description: "Notify only when an autoupdate run fails."
          switch "--no-notify",
                 description: "Disable autoupdate notifications."

          conflicts "--only", "--leaves-only"
          conflicts "--notify-on-error", "--no-notify"
          named_args max: 1
        end

        def run
          raise UsageError, "`--only` cannot be passed without `--upgrade`." if args.only && !args.upgrade?

          interval = begin
            ::Autoupdate::Interval.parse(args.named.first)
          rescue ::Autoupdate::Interval::InvalidIntervalError => e
            raise UsageError, e.message
          end

          config_file = ::Autoupdate::Core.config_file
          options_given = args.named.any? || args.only || SWITCHES.any? { |switch| args.public_send(:"#{switch}?") }
          config = if options_given || !config_file.exist?
            ::Autoupdate::Setup.config_from_args(interval:, args:)
          else
            ohai "Reusing the options saved by the previous `brew autoupdate start`."
            ::Autoupdate::Config.load(config_file)
          end
          ::Autoupdate::Setup.start(config)
        end
      end
    end
  end
end
