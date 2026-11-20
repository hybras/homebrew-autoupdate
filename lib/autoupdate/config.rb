# frozen_string_literal: true

module Autoupdate
  # The options chosen with `brew autoupdate start`, plus the environment
  # captured when it ran. Everything the generated scripts and launch agent
  # need comes from here.
  Config = Struct.new(
    :interval,    # Integer seconds, or an Interval::CalendarTime
    :run_at_load, # also run when the agent is loaded (`--immediate`)
    :upgrade,
    :greedy,
    :cleanup,
    :sudo,        # prompt for a password with pinentry-mac
    :leaves_only,
    :only,        # Array of package names, or nil
    :ac_only,
    :notify,      # "always", "error" or "never"
    :environment, # Hash of variables exported to every run
    keyword_init: true,
  )
end
