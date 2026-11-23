# frozen_string_literal: true

module Homebrew
  module Cmd
    class Autoupdate < AbstractCommand
      class VersionSubcommand < AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            `autoupdate version`:
            Show this tool's current version and a short changelog.
          EOS
          named_args :none
        end

        def run
          tap_dir = ::Autoupdate::Core.tap_dir
          puts <<~EOS
            Version #{(tap_dir/"VERSION").read.strip}

          EOS
          return if (tap_dir/".git/shallow").exist?

          last_version, current_version = [1, 0].map do |skip|
            Utils.popen_read("git", "-C", tap_dir, "log", "--grep=version: bump", "-n1", "--skip=#{skip}",
                             "--no-merges", "--pretty=format:%h").chomp
          end
          log = Utils.popen_read("git", "-C", tap_dir, "log", "--oneline", "--no-merges",
                                 "#{last_version}..#{current_version}").chomp

          puts <<~EOS
            Changes since last version:

            #{log}
          EOS
        end
      end
    end
  end
end
