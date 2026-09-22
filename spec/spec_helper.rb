# frozen_string_literal: true

# Simulate "nokogiri not installed" BEFORE anything can load it. Must run
# ahead of `require "canon"` so Canon::NokogiriLoader and every
# `defined?(Nokogiri)` guard see genuine absence.
require "support/nokogiri_less" if
  ENV["CANON_SIMULATE_NO_NOKOGIRI"] == "1" && RUBY_ENGINE != "opal"

require "canon"

# Ensure file reads use UTF-8 regardless of system locale (LC_ALL/LANG).
# Fixture files contain non-ASCII characters (e.g. em-dashes) and will raise
# ArgumentError / Encoding::CompatibilityError on US-ASCII systems without this.
if RUBY_ENGINE != "opal"
  Encoding.default_external = Encoding::UTF_8
  Encoding.default_internal = Encoding::UTF_8
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Nokogiri-less run (CANON_SIMULATE_NO_NOKOGIRI=1): exclude specs that
  # genuinely need nokogiri. Trees are tagged by file path via derived
  # metadata; individual examples outside those trees can set
  # `:requires_nokogiri => true` explicitly.
  if ENV["CANON_SIMULATE_NO_NOKOGIRI"] == "1"
    config.filter_run_excluding requires_nokogiri: true
    # Spec files that REQUIRE nokogiri at load time (HTML support, the
    # raw-nokogiri legacy paths, engine-parity fixtures) must be excluded
    # from LOADING — metadata filters only run after load.
    # exclude_pattern takes a GLOB (not a regex): these spec trees need
    # nokogiri at load time (HTML support, fixture-integrity byte gates,
    # the refactored-comparison suite).
    # file_glob_from wraps this comma-separated list in one brace group.
    config.exclude_pattern =
      "spec/**/*{html,comparison_refactored,fixtures_integrity}*, spec/**/html/*"
    # Spec trees that construct raw Nokogiri objects or exercise
    # nokogiri-only pipelines (HTML support, engine parity, display
    # preprocessing, legacy adapters).
    config.define_derived_metadata(
      file_path: %r{
        /spec/canon/(
          html/|
          comparison/html_|comparison_html_|comparison_spec|
          comparison/(node_inspector|comments_asymmetry|whitespace_adjacency|
                      whitespace_sensitivity|diff_node_builder|
                      parse_error_surface|pipeline_spec)|
          validators/html_|validators/xml_validator_spec|
          formatters/html|diff_formatter/by_line/html|
          pretty_printer/html|pretty_printer/xml_normalized_spec|
          xml/engine_parity_spec|xml/tree_builder_spec|
          diff/(node_serializer|path_builder|
                xml_serialization_formatter)|
          diff_formatter/(diff_detail_formatter|display_preprocessing|
                          pretty_diff)|
          tree_diff/(adapters/xml_adapter|(canon_)?integration|
                     whitespace_sensitive)|
          rspec_matchers_spec|informative_diffs_debug_spec|
          enriched_diffnode_spec|fixtures/isodoc_spec|
          match_profiles_integration_spec|isodoc_attribute_order_spec|
          table_class_attribute_bug_spec
        )}x,
    ) do |metadata|
      metadata[:requires_nokogiri] = true
    end
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
