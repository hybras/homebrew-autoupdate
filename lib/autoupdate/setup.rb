# frozen_string_literal: true

require "digest"
require "system_command"
require "utils/output"

module Autoupdate
  # Writes everything a job runs and loads its launch agent; shared by
  # `start` and `restart`.
  module Setup
    extend SystemCommand::Mixin
    extend Utils::Output::Mixin

    module_function

    # Variables captured from the shell running `start` and exported to every
    # run, to respect the user's choices as much as possible.
    CAPTURED_ENVIRONMENT = %w[
      PATH
      HOMEBREW_CACHE
      HOMEBREW_LOGS
      HOMEBREW_DEVELOPER
      HOMEBREW_NO_ANALYTICS
      HOMEBREW_CASK_OPTS
    ].freeze

    def start(config)
      if Autoupdate::Launchd.loaded?
        odie <<~EOS
          The command already appears to have been started.
          Please run `brew autoupdate restart` to start it again.
        EOS
      end
      check_config(config)

      location = Autoupdate::Core.location
      FileUtils.mkpath(Autoupdate::Core.logs)
      FileUtils.mkpath(location)
      log = log_path

      config.commit = Autoupdate::Core.tap_commit
      config.save(Autoupdate::Core.config_file)
      build_app
      write_scripts(config, location:, log:)
      write_launch_agent(config, location:, log:)
      Autoupdate::Launchd.load(Autoupdate::Core.plist)

      print_started(config)
    end

    def config_from_args(interval:, args:)
      environment = CAPTURED_ENVIRONMENT.filter_map { |name| [name, ENV.fetch(name)] if ENV[name] }.to_h
      environment["SUDO_ASKPASS"] = ENV.fetch("SUDO_ASKPASS") if ENV["SUDO_ASKPASS"] && !args.sudo?

      notify = if args.no_notify? || MacOS.version < :catalina
        "never"
      elsif args.notify_on_error?
        "error"
      else
        "always"
      end

      Autoupdate::Config.new(
        interval:,
        run_at_load: args.immediate?,
        upgrade:     args.upgrade?,
        greedy:      args.greedy?,
        cleanup:     args.cleanup?,
        sudo:        args.sudo?,
        leaves_only: args.leaves_only?,
        only:        args.only,
        ac_only:     args.ac_only?,
        notify:,
        environment:,
      )
    end

    def check_config(config)
      # Package names are interpolated into the updater script.
      if config.only
        odie "`--only` requires at least one package name." if config.only.empty?

        invalid_names = config.only.grep_v(%r{\A[a-zA-Z0-9\-_.@/]+\z})
        if invalid_names.any?
          odie <<~EOS
            Invalid package name(s): #{invalid_names.join(", ")}
            Package names may only contain letters, digits, hyphens, underscores, dots, @ signs, and slashes.
          EOS
        end
      end

      if config.sudo && !Utils::Path.formula_any_version_installed?("pinentry-mac")
        odie <<~EOS
          `--sudo` requires https://formulae.brew.sh/formula/pinentry-mac to be installed.
          Please run `brew install pinentry-mac` and try again.
        EOS
      end

      return if !config.upgrade || config.only || !Autoupdate::Core.casks_installed?
      return if config.sudo || config.environment.key?("SUDO_ASKPASS")

      opoo <<~EOS
        Please note if you use Casks that require `sudo` to upgrade,
        you need to use `--sudo` or define a custom `SUDO_ASKPASS`
        environment variable.

      EOS
    end

    # It's not something I particularly support but if someone manually loads
    # the plist with launchctl themselves we can end up with a log directory
    # we can't write to later, so need to ensure a future `start` command
    # doesn't silently fail.
    def log_path
      if File.writable?(Autoupdate::Core.logs)
        "#{Autoupdate::Core.logs}/#{Autoupdate::Core.name}.out"
      elsif File.writable?(Autoupdate::Core.fallback_logs)
        "#{Autoupdate::Core.fallback_logs}/#{Autoupdate::Core.name}.out"
      else
        odie <<~EOS
          #{Autoupdate::Core.logs} does not seem to be writable.
          You may wish to `chown` it back to your user.
        EOS
      end
    end

    # Builds the app from this tap's source into the job's support directory
    # and signs it with the local certificate, unless the app there was
    # already built from the same source and signed with that certificate.
    def build_app
      identity = Autoupdate::Signing.identity
      app = Autoupdate::Core.app
      app_dir = Autoupdate::Core.tap_dir/"app"
      # Matches the hash `build.sh` records.
      sources = %w[BrewAutoupdate.swift build.sh].map { |name| (app_dir/name).binread }.join
      if app.exist?
        built_from = Utils.popen_read("/usr/bin/plutil", "-extract", "BrewAutoupdateSourcesSHA256", "raw",
                                      app/"Contents/Info.plist")
        # The designated requirement names the certificate by its SHA-1.
        requirement = system_command("/usr/bin/codesign", args: ["-d", "-r-", app], print_stderr: false).merged_output
        current = built_from.strip == Digest::SHA256.hexdigest(sources)
        return if current && requirement.downcase.include?("h\"#{identity.downcase}\"")
      end

      ohai "Building #{app.basename} from #{app_dir}"
      system_command! app_dir/"build.sh", args: [app], env: { "CODESIGN_IDENTITY" => identity }, print_stderr: false
    end

    def write_scripts(config, location:, log:)
      write_executable(Autoupdate::Core.notify_script, (Autoupdate::Core.tap_dir/"app/notify-result.sh").read)

      sudo_askpass = location/"brew_autoupdate_sudo_gui"
      if config.sudo
        write_executable(sudo_askpass, Autoupdate::Script.sudo_askpass(
                                         prefix: HOMEBREW_PREFIX,
                                         icon:   Autoupdate::Core.app/"Contents/Resources/applet.icns",
                                       ))
      end

      core = Autoupdate::Core
      write_executable(core.updater, Autoupdate::Script.updater(
                                       config,
                                       brew:                core.brew,
                                       casks:               core.casks_installed?,
                                       sudo_askpass:        sudo_askpass.to_s,
                                       notify_command:      Autoupdate::Notify.command(mode: config.notify),
                                       runs:                core.runs.to_s,
                                       tap:                 core.tap_dir.to_s,
                                       app_management_file: core.app_management_file.to_s,
                                     ))

      write_executable(Pathname(Autoupdate::Launcher.path(location)), Autoupdate::Launcher.script(
                                                                        app:      Autoupdate::Core.app.to_s,
                                                                        location: location.to_s,
                                                                        log:,
                                                                      ))
    end

    def write_executable(path, contents)
      return if path.exist? && path.read == contents

      path.atomic_write(contents)
      FileUtils.chmod 0555, path
    end

    def write_launch_agent(config, location:, log:)
      # https://github.com/Homebrew/homebrew-autoupdate/issues/10
      user_la = Pathname.new(Autoupdate::Core.plist).dirname
      unless user_la.exist?
        odie <<~EOS
          #{user_la} does not exist. Please create it first:
            mkdir -p #{user_la}
          You may need to use `sudo`.
        EOS
      end

      File.write(Autoupdate::Core.plist, Autoupdate::LaunchAgent.plist(
                                           label:       Autoupdate::Core.name,
                                           program:     Autoupdate::Launcher.path(location),
                                           log:,
                                           interval:    config.interval,
                                           run_at_load: config.run_at_load,
                                         ))
    end

    def print_started(config)
      update_message = "Homebrew will now automatically update every #{Autoupdate::Interval.describe(config.interval)}"
      if config.run_at_load
        puts "#{update_message}, now, and on system boot."
      else
        puts "#{update_message}."
      end

      return if !config.upgrade || !Autoupdate::Core.casks_installed?

      puts <<~EOS

        To upgrade cask apps in place (keeping their Dock position and settings),
        grant the app App Management: in System Settings > Privacy & Security >
        App Management, click +, press Cmd+Shift+G and enter:
          #{Autoupdate::Core.app}
        It may not stay visible in that list. `brew autoupdate status` shows
        whether the last scheduled run had the permission.
      EOS
    end
  end
end
