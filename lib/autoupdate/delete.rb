# frozen_string_literal: true

module Autoupdate
  module_function

  def delete
    Autoupdate::Launchd.unload
    Autoupdate.cleanup

    puts "Homebrew will no longer autoupdate and the plist has been deleted."
  end
end
