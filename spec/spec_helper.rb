# frozen_string_literal: true

require "canon"

# Ensure file reads use UTF-8 regardless of system locale (LC_ALL/LANG).
# Fixture files contain non-ASCII characters (e.g. em-dashes) and will raise
# ArgumentError / Encoding::CompatibilityError on US-ASCII systems without this.
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Under Opal, exclude specs requiring native-only features
  if RUBY_ENGINE == "opal"
    config.filter_run_excluding(
      :html,
      :cli,
      :terminal,
      :native_fs,
      :nokogiri_only,
      :native_adapter,
    )
  end
end
