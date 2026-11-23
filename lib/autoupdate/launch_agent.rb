# frozen_string_literal: true

require "json"
require "open3"

module Autoupdate
  # Generates the launch agent property list.
  module LaunchAgent
    module_function

    def properties(label:, program:, log:, interval:, run_at_load:)
      properties = {
        "Label"                   => label,
        "Program"                 => program,
        "ProgramArguments"        => [program],
        "StandardErrorPath"       => log,
        "StandardOutPath"         => log,
        "LowPriorityBackgroundIO" => true,
        "LowPriorityIO"           => true,
        "ProcessType"             => "Background",
      }
      # This restores the "Run At Load" key removed in a7de771abcf6 when requested.
      properties["RunAtLoad"] = true if run_at_load

      # A CalendarTime schedules a fixed wall-clock time daily; anything else
      # is a relative interval in seconds from whenever launchd loads the job.
      if interval.respond_to?(:hour)
        properties["StartCalendarInterval"] = { "Hour" => interval.hour, "Minute" => interval.minute }
      else
        properties["StartInterval"] = interval
      end
      properties
    end

    def plist(...)
      xml, status = Open3.capture2(
        "/usr/bin/plutil", "-convert", "xml1", "-o", "-", "-",
        stdin_data: JSON.generate(properties(...))
      )
      raise "plutil could not generate the launch agent" unless status.success?

      xml
    end
  end
end
