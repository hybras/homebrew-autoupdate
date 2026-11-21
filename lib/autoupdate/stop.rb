# frozen_string_literal: true

module Autoupdate
  module_function

  def stop
    odie "Autoupdate is not currently running; cannot stop a command that is not running." unless Autoupdate::Launchd.loaded?

    Autoupdate::Launchd.unload
    puts "Homebrew will no longer autoupdate."
  end
end
