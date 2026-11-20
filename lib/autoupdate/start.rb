# frozen_string_literal: true

require "utils/output"

module Autoupdate
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

  # `start` options other than the interval. Without any of them, `start`
  # after `stop` reuses the saved options.
  START_SWITCHES = %w[upgrade greedy cleanup immediate sudo leaves_only ac_only notify_on_error no_notify].freeze

  def start(interval:, args:)
    if Autoupdate::Launchd.loaded?
      odie <<~EOS
        The command already appears to have been started.
        Please run `brew autoupdate delete` and try again.
      EOS
    end

    options_given = args.named.any? || args.only || START_SWITCHES.any? { |switch| args.send(:"#{switch}?") }
    # Setups created before options were saved keep their updater script
    # unless new options are given, since its options cannot be recovered.
    legacy = !Autoupdate::Core.config_file.exist? && Autoupdate::Core.updater.exist? && !options_given

    config = if options_given || !Autoupdate::Core.config_file.exist?
      config_from_args(interval:, args:)
    else
      ohai "Reusing the options saved by the previous `brew autoupdate start`."
      Autoupdate::Config.load(Autoupdate::Core.config_file)
    end
    check_config(config)

    location = Autoupdate::Core.location
    FileUtils.mkpath(Autoupdate::Core.logs)
    FileUtils.mkpath(location)
    log = log_path

    config.save(Autoupdate::Core.config_file) unless legacy
    write_scripts(config, location:, log:, legacy:)
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

    return if !config.upgrade || config.only || !casks_installed?
    return if config.sudo || config.environment.key?("SUDO_ASKPASS")

    opoo <<~EOS
      Please note if you use Casks that require `sudo` to upgrade,
      you need to use `--sudo` or define a custom `SUDO_ASKPASS`
      environment variable.

    EOS
  end

  def casks_installed?
    (HOMEBREW_PREFIX/"Caskroom").exist?
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

  def write_scripts(config, location:, log:, legacy:)
    updater = Autoupdate::Core.updater
    leaves_script = location/"brew_autoupdate_leaves"
    sudo_askpass = location/"brew_autoupdate_sudo_gui"

    if config.upgrade && config.leaves_only
      write_executable(leaves_script, Autoupdate::Script.leaves(brew: Autoupdate::Core.brew))
    end

    if config.sudo
      write_executable(sudo_askpass, Autoupdate::Script.sudo_askpass(
                                       prefix: HOMEBREW_PREFIX,
                                       icon:   Autoupdate::Core.tap_dir/"notifier/applet.icns",
                                     ))
    end

    if legacy
      # Security tools like "Little Snitch" only display the executable name by
      # default, which makes this generic name a little worrying without context.
      # Rename the old script to the new script name, which should provide more
      # clarity to users who run systems with tools like LS installed.
      FileUtils.cp location/"updater", updater if (location/"updater").exist?
      opoo <<~EOS
        This setup was created by an older version of `brew autoupdate`, which did
        not save its options, so its updater script is kept as it is. To update it,
        run `brew autoupdate delete` and then `brew autoupdate start` with your options.
      EOS
    else
      write_executable(updater, Autoupdate::Script.updater(
                                  config,
                                  brew:           Autoupdate::Core.brew,
                                  casks:          casks_installed?,
                                  leaves_script:  leaves_script.to_s,
                                  sudo_askpass:   sudo_askpass.to_s,
                                  notify_command: Autoupdate::Notify.command(mode: config.notify),
                                ))
    end

    # Unlike the updater script, the launcher holds no user options, so it is
    # refreshed on every start.
    write_executable(Pathname(Autoupdate::Launcher.path(location)), Autoupdate::Launcher.script(
                                                                      app:      Autoupdate::Notify.notifier_app,
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

    return if !config.upgrade || !casks_installed?
    return unless Autoupdate::Launcher.app_supports_run_updater?(Autoupdate::Notify.notifier_app)

    puts <<~EOS

      To upgrade cask apps in place (keeping their Dock position and settings),
      turn on "brew-autoupdate" in System Settings > Privacy & Security > App Management.
      It appears there, switched off, after the first scheduled upgrade macOS blocks;
      you can also add it now with the + button. The app is located at:
        #{Autoupdate::Notify.notifier_app}
    EOS
  end
end
