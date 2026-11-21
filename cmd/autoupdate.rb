# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
# Each subcommand registers itself from its file in `lib/autoupdate/`.
require_relative "../lib/autoupdate"

module Homebrew
  module Cmd
    class Autoupdate < AbstractCommand
      cmd_args do
        usage_banner "`autoupdate` <subcommand> [<options>]"

        description <<~EOS
          An easy, convenient way to automatically update Homebrew.

          This script will run `brew update` in the background once every 24 hours (by default)
          until explicitly told to stop, utilising `launchd`.

          Start autoupdating with:
            `brew autoupdate start [<interval>] [<options>]`

          The interval defaults to 24 hours. It can be provided as seconds or as a duration
          such as `30m`, `12h`, `1d`, or `1w`, or as a 24-hour clock time such as `00:00` to
          run daily at that specific time instead of relative to when the command was run.

          Common start options:
            `--upgrade` upgrades installed formulae and casks.
            `--cleanup` cleans Homebrew's cache and logs after a successful run.
            `--immediate` runs immediately and whenever the launch agent is loaded.
            `--only=wget,node,firefox` upgrades only the listed packages.
            `--leaves-only` upgrades only top-level formulae.
            `--greedy` includes auto-updating casks.
            `--sudo` enables a GUI password prompt for cask upgrades.
            `--ac-only` skips runs while the Mac is on battery power.
            `--notify-on-error` shows notifications only for failed runs.
            `--no-notify` disables notifications.

          After this tap's source changes, run `brew autoupdate restart` so the
          job uses the new version; `status` and the job's notifications remind you.

          Examples:
            `brew autoupdate start`
            `brew autoupdate start 12h --upgrade --cleanup --immediate`
            `brew autoupdate start 1d --upgrade --only=wget,node,firefox`
            `brew autoupdate start 00:00 --upgrade --cleanup`
            `brew autoupdate restart`
            `brew autoupdate logs --lines=50`
            `brew autoupdate logs --follow`

          Run `brew autoupdate start --help` or `brew autoupdate logs --help` for
          complete options for those subcommands.
        EOS

        Homebrew::AbstractSubcommand.define_all(self, command: Homebrew::Cmd::Autoupdate)
      end

      def run
        # This entire tool is essentially a "bells and whistles" wrapper around
        # `launchd` so Linux support is a no-go unless someone wants to put
        # the work in to add/support it in a sustainable manner.
        raise UsageError, "`brew autoupdate` is supported only on macOS!" unless OS.mac?

        subcommand = Homebrew::AbstractSubcommand.subcommands_for(self.class).find do |candidate|
          candidate.subcommand_name == args.subcommand
        end
        raise UsageError, "This command requires a subcommand argument." if subcommand.nil?

        subcommand.new(args).run
      end
    end
  end
end
