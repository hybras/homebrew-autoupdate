# frozen_string_literal: true

require "plist"

module Autoupdate
  module_function

  def status
    running = Autoupdate::Launchd.loaded?
    updater = Autoupdate::Core.updater
    # The configuration is saved on every start; older setups only have the
    # updater script, which they never rewrote.
    started = [Autoupdate::Core.config_file, updater].find(&:exist?)

    if running || started
      puts "Autoupdate is installed and #{running ? "running" : "stopped"}."
      puts
      puts "Last started: #{started ? started.mtime.strftime("%F") : "unknown"}"
      puts configuration_summary
      puts
      puts outdated_message if started && (Date.today - started.mtime.to_date).to_i >= 90
    elsif !File.exist?(Autoupdate::Core.plist)
      puts "Autoupdate is not configured. Use `brew autoupdate start` to begin."
    else
      puts <<~EOS
        Autoupdate cannot determine its status.
        Please feel free to file an issue with further information here:
        https://github.com/DomT4/homebrew-autoupdate/issues
      EOS
    end
  end

  def configuration_summary
    plist = File.exist?(Autoupdate::Core.plist) ? Plist.parse_xml(Autoupdate::Core.plist, marshal: false) : {}
    details = if Autoupdate::Core.config_file.exist?
      Autoupdate::Config.load(Autoupdate::Core.config_file).summary(casks: casks_installed?)
    else
      ["Options: not saved by the version of `brew autoupdate` that started it"]
    end
    details << "Runs via: #{launch_mode(plist)}"
    details << "Logs: #{plist["StandardOutPath"]}" if plist["StandardOutPath"]
    details.join("\n")
  rescue JSON::ParserError, ArgumentError => e
    "Configuration: unable to read #{Autoupdate::Core.config_file} (#{e.message})"
  end

  def outdated_message
    if Autoupdate::Core.config_file.exist?
      <<~EOS
        The updater script was generated more than 90 days ago. Run
        `brew autoupdate stop` and then `brew autoupdate start` to regenerate it
        with the latest improvements; your options are kept.
      EOS
    else
      <<~EOS
        This setup was created by an older version of `brew autoupdate`. Run
        `brew autoupdate delete` and then `brew autoupdate start` with your
        options to enable the latest features.
      EOS
    end
  end

  def launch_mode(plist)
    unless plist["Program"].to_s.end_with?("/#{Autoupdate::Launcher::SCRIPT_NAME}")
      return "updater script (legacy; run `brew autoupdate stop` then `start` " \
             "to run through brew-autoupdate.app)"
    end

    if Autoupdate::Launcher.app_supports_run_updater?(Autoupdate::Notify.notifier_app)
      "brew-autoupdate.app (grant it App Management to upgrade cask apps in place)"
    else
      "updater script (the installed brew-autoupdate.app cannot run updates)"
    end
  end
end
