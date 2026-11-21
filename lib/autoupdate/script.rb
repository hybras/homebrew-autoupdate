# frozen_string_literal: true

require "shellwords"

module Autoupdate
  # Generates the shell scripts written by `brew autoupdate start`. Paths are
  # passed in rather than looked up so the output can be tested directly.
  module Script
    module_function

    # How many runs' logs to keep.
    KEPT_RUNS = 30

    RESTART_REMINDER = "This tap has changed since the job started; run `brew autoupdate restart`."

    def updater(config, brew:, casks:, sudo_askpass:, notify_command:, runs:, tap:, app_management_file:)
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

        #{app_management_check(app_management_file) if config.upgrade && casks}
        (#{commands(config, brew:, casks:).join(" && ")}) >"$run_log" 2>&1
        status=$?
        #{restart_check(config, tap:)}
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

    # Does what Homebrew's `Cask::Quarantine.app_management_permissions_granted?`
    # does, writing into an app bundle, so `status` can report whether runs
    # have the permission. Only a run started by the app reflects its grant.
    def app_management_check(file)
      <<~SH.chomp
        if [ -z "${BREW_AUTOUPDATE_RUN_BY_APP:-}" ]
        then
          app_management="not checked: this run did not go through brew-autoupdate.app"
        else
          app_management="not checked: no app in ~/Applications or /Applications is owned by you"
          for target in "$HOME"/Applications/*.app /Applications/*.app
          do
            [ -O "$target" ] && [ -w "$target" ] || continue
            if /usr/bin/touch "$target/.homebrew-write-test" 2>/dev/null
            then
              /bin/rm -f "$target/.homebrew-write-test"
              app_management="granted"
            else
              app_management="not granted"
            fi
            break
          done
        fi
        echo "$app_management ($(/bin/date '+%F %R'))" >#{Shellwords.escape(file)}
      SH
    end

    # `brew update` may have pulled a new version of this tap, which the job
    # only uses after a restart.
    def restart_check(config, tap:)
      return "reminder=" if config.commit.nil?

      <<~SH.chomp
        reminder=
        if [ "$(/usr/bin/git -C #{Shellwords.escape(tap)} rev-parse HEAD 2>/dev/null)" != #{Shellwords.escape(config.commit)} ]
        then
          reminder=#{Shellwords.escape(RESTART_REMINDER)}
          echo "$reminder" >>"$run_log"
        fi
      SH
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
