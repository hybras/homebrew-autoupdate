# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/autoupdate/core"

# Names shared by Ruby, Swift and `app/build.sh` are duplicated on purpose
# (see ARCHITECTURE.md, D15); these tests catch a change made on one side only.
class ConstantsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__).freeze
  SWIFT = File.read(File.join(ROOT, "app/BrewAutoupdate.swift")).freeze
  BUILD = File.read(File.join(ROOT, "app/build.sh")).freeze

  def test_the_app_uses_the_support_directory
    assert_includes SWIFT, "Library/Application Support/#{Autoupdate::Core.name}\""
  end

  def test_the_app_runs_the_updater_script
    assert_includes SWIFT, "/#{Autoupdate::Core.updater.basename}\""
  end

  def test_the_app_writes_the_status_file
    assert_includes SWIFT, "/#{Autoupdate::Core.status_file.basename}\""
  end

  def test_the_bundle_id_extends_the_label
    assert_includes BUILD, "\"#{Autoupdate::Core.bundle_id}\""
  end
end
