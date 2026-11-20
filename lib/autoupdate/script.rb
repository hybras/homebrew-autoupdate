# frozen_string_literal: true

require "shellwords"

module Autoupdate
  # Generates the shell scripts written by `brew autoupdate start`. Paths are
  # passed in rather than looked up so the output can be tested directly.
  module Script
    module_function

    def updater(config, brew:, casks:, leaves_script:, sudo_askpass:, notify_command:)
      <<~SH
        #!/bin/sh
        #{ac_only_check if config.ac_only}
        #{exports(config, sudo_askpass:).join("\n")}
        run_log=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/brew-autoupdate.XXXXXX") || exit 1
        trap '/bin/rm -f "$run_log"' EXIT

        /bin/date
        (#{commands(config, brew:, casks:, leaves_script:).join(" && ")}) >"$run_log" 2>&1
        status=$?
        /bin/cat "$run_log"
        #{notify_command}
        exit "$status"
      SH
    end

    def commands(config, brew:, casks:, leaves_script:)
      greedy = config.greedy ? " --greedy" : ""
      commands = ["#{brew} update"]

      if config.upgrade
        commands << if config.leaves_only
          Shellwords.escape(leaves_script)
        elsif config.only
          "#{brew} upgrade --no-ask -v#{greedy} #{config.only.join(" ")}"
        else
          "#{brew} upgrade --no-ask --formula -v"
        end
        commands << "#{brew} upgrade --no-ask --cask -v#{greedy}" if !config.only && casks
      end

      commands << "#{brew} cleanup" if config.cleanup
      commands
    end

    def exports(config, sudo_askpass:)
      # A background job should not unexpectedly build from source.
      environment = { "HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK" => "1" }.merge(config.environment)
      environment["SUDO_ASKPASS"] = sudo_askpass if config.sudo
      environment.map { |name, value| "export #{name}=#{Shellwords.escape(value)}" }
    end

    def ac_only_check
      <<~SH.chomp
        if ! output=$(LC_ALL=C /usr/bin/pmset -g ps 2>/dev/null); then
          echo "Warning: Unable to determine power source; proceeding anyway" >&2
        elif ! echo "$output" | /usr/bin/grep --quiet "'AC Power'"; then
          echo "Skipping homebrew-autoupdate: device not on AC power" >&2
          exit
        fi
      SH
    end

    def leaves(brew:)
      <<~SH
        #!/bin/bash
        set -e
        LEAVES=$(#{brew} leaves)
        if [ -n "$LEAVES" ]; then
          echo "Upgrading leaves packages only..."
          #{brew} upgrade --no-ask --formula -v $(echo "$LEAVES") || {
            echo "Warning: Some leaves packages failed to upgrade."
            # Return 0 to ensure the autoupdate process continues
            exit 0
          }
        else
          echo "No leaves packages to upgrade."
        fi
      SH
    end

    # Used as SUDO_ASKPASS: asks for the password with pinentry-mac and prints
    # it, decoding the percent-escaping of pinentry's `D` data lines.
    def sudo_askpass(prefix:, icon:)
      <<~SH
        #!/bin/sh
        PATH=#{Shellwords.escape("#{prefix}/bin")}
        (
          export PINENTRY_USER_DATA=#{Shellwords.escape("ICON=#{icon},")}
          printf '%s\\n' \\
            "OPTION allow-external-cache" \\
            "SETOK OK" \\
            "SETCANCEL Cancel" \\
            "SETDESC homebrew-autoupdate needs your admin password to complete the upgrade" \\
            "SETPROMPT Enter Password:" \\
            "SETTITLE homebrew-autoupdate Password Request" \\
            "GETPIN" \\
            | pinentry-mac --no-global-grab --timeout 60
        ) | /usr/bin/awk '/^D / {gsub(/%25/, "%"); print substr($0, 3)}'
      SH
    end
  end
end
