# frozen_string_literal: true

require "shellwords"

module Autoupdate
  # Generates the shell scripts written by `brew autoupdate start`. Paths are
  # passed in rather than looked up so the output can be tested directly.
  module Script
    module_function

    # How many runs' logs to keep.
    KEPT_RUNS = 30

    def updater(config, brew:, casks:, sudo_askpass:, notify_command:, runs:)
      <<~SH
        #!/bin/sh
        #{ac_only_check if config.ac_only}
        #{exports(config, sudo_askpass:).join("\n")}
        runs=#{Shellwords.escape(runs)}
        /bin/mkdir -p "$runs" || exit 1
        # Names sort by time, oldest first.
        run_log="$runs/$(/bin/date +%Y-%m-%d-%H%M%S).log"
        # What the run is about to upgrade, for the notification.
        outdated="${run_log%.log}.outdated.json"

        (#{commands(config, brew:, casks:).join(" && ")}) >"$run_log" 2>&1
        status=$?
        echo "$(/bin/date): exit status $status; see $run_log"
        #{notify_command}

        /bin/ls -1r "$runs" | /usr/bin/grep '\\.log$' | /usr/bin/tail -n +#{KEPT_RUNS + 1} |
          while read -r old; do /bin/rm -f "$runs/$old" "$runs/${old%.log}.outdated.json"; done
        exit "$status"
      SH
    end

    def commands(config, brew:, casks:)
      greedy = config.greedy ? " --greedy" : ""
      commands = ["#{brew} update"]

      if config.upgrade
        # `brew outdated` exits 1 when named packages are outdated, which is
        # not a failure here.
        outdated = ->(scope) { "{ #{brew} outdated --json=v2#{scope} >\"$outdated\" || :; }" }
        commands << if config.leaves_only
          # Formula names contain no whitespace, so `$leaves` is split on purpose.
          "leaves=$(#{brew} leaves) && if [ -n \"$leaves\" ]; then " \
            "#{outdated.call(" --formula $leaves")} && " \
            "#{brew} upgrade --no-ask --formula -v $leaves; " \
            "else echo \"No leaves packages to upgrade.\"; fi"
        elsif config.only
          "#{outdated.call("#{greedy} #{config.only.join(" ")}")} && " \
            "#{brew} upgrade --no-ask -v#{greedy} #{config.only.join(" ")}"
        else
          "#{outdated.call(casks ? greedy : " --formula")} && #{brew} upgrade --no-ask --formula -v"
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
