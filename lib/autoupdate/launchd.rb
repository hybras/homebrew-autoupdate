# frozen_string_literal: true

require "system_command"
require "utils/output"

module Autoupdate
  # Loads and unloads the launch agent in the logged-in user's GUI domain.
  module Launchd
    extend SystemCommand::Mixin
    extend Utils::Output::Mixin

    module_function

    def domain
      "gui/#{Process.uid}"
    end

    def service
      "#{domain}/#{Autoupdate::Core.name}"
    end

    # Matches the exact label; `launchctl list` output also contains other
    # jobs whose labels merely include this one, such as the running app.
    def loaded?
      SystemCommand.quiet_system "/bin/launchctl", "print", service
    end

    def load(plist)
      result = system_command "/bin/launchctl", args: ["bootstrap", domain, plist], print_stderr: false
      return if result.success?

      odie <<~EOS
        Could not load #{plist}:
          #{result.stderr.strip}
        `brew autoupdate` must be run from a logged-in macOS session, not only over SSH.
      EOS
    end

    def unload
      return unless loaded?

      result = system_command "/bin/launchctl", args: ["bootout", service], print_stderr: false
      odie "Could not unload #{service}: #{result.stderr.strip}" unless result.success?
    end
  end
end
