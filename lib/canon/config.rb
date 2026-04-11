# frozen_string_literal: true

require_relative "config/env_provider"
require_relative "config/override_resolver"
require_relative "config/profile_loader"
require_relative "color_detector"

module Canon
  # Global configuration for Canon
  # Provides unified configuration across CLI, Ruby API, and RSpec interfaces
  class Config
    class << self
      def instance
        @instance ||= new
      end

      def configure
        yield instance if block_given?
        instance
      end

      def reset!
        @instance = new
      end

      # Delegate to instance
      def method_missing(method, ...)
        if @instance.respond_to?(method)
          @instance.send(method, ...)
        else
          super
        end
      end

      def respond_to_missing?(method, include_private = false)
        @instance.respond_to?(method) || super
      end
    end

    attr_reader :xml, :html, :json, :yaml, :string

    def initialize
      @xml = FormatConfig.new(:xml)
      @html = FormatConfig.new(:html)
      @json = FormatConfig.new(:json)
      @yaml = FormatConfig.new(:yaml)
      @string = FormatConfig.new(:string)
      @profile = nil

      env_profile = ENV.fetch("CANON_CONFIG_PROFILE", nil)
      if env_profile
        # Convert to symbol if it matches a built-in profile name
        self.profile = if ProfileLoader.available_profiles.include?(env_profile.to_sym)
                         env_profile.to_sym
                       else
                         env_profile
                       end
      end
    end

    # Returns the current profile name or path.
    def profile
      @profile
    end

    # Apply a configuration profile by name (Symbol for built-in) or
    # file path (String). Set to +nil+ to clear the profile layer.
    def profile=(name_or_path)
      clear_profile_values!

      if name_or_path.nil?
        @profile = nil
        return
      end

      @profile = name_or_path.is_a?(Symbol) ? name_or_path : name_or_path.to_s
      apply_profile(@profile)
    end

    def reset!
      @xml.reset!
      @html.reset!
      @json.reset!
      @yaml.reset!
      @string.reset!
      @profile = nil
    end

    # Backward compatibility methods for top-level diff configuration
    # These delegate to XML diff config for backward compatibility
    def diff_mode
      @xml.diff.mode
    end

    def diff_mode=(value)
      @xml.diff.mode = value
    end

    def use_color
      @xml.diff.use_color
    end

    def use_color=(value)
      @xml.diff.use_color = value
    end

    # Backward compatibility methods for match profile configuration
    def xml_match_profile
      @xml.match.profile
    end

    def xml_match_profile=(value)
      @xml.match.profile = value
    end

    def html_match_profile
      @html.match.profile
    end

    def html_match_profile=(value)
      @html.match.profile = value
    end

    # Format-specific configuration
    # Each format (XML, HTML, JSON, YAML) has its own instance
    class FormatConfig
      attr_reader :format, :match, :diff

      def initialize(format)
        @format = format
        @match = MatchConfig.new(format)
        @diff = DiffConfig.new(format)
        @preprocessing = nil
        @profile_preprocessing = nil
      end

      def preprocessing
        @preprocessing || @profile_preprocessing
      end

      def preprocessing=(value)
        @preprocessing = value
      end

      def reset!
        @match.reset!
        @diff.reset!
        @preprocessing = nil
        @profile_preprocessing = nil
      end

      def apply_profile_data(data)
        if data.key?("preprocessing")
          val = data["preprocessing"]
          @profile_preprocessing = val.is_a?(String) ? val.to_sym : val
        end

        @match.apply_profile_data(data["match"]) if data.key?("match")
        @diff.apply_profile_data(data["diff"]) if data.key?("diff")
      end

      def clear_profile!
        @profile_preprocessing = nil
        @match.clear_profile!
        @diff.clear_profile!
      end
    end

    # Match configuration for comparison behavior
    class MatchConfig
      attr_reader :options

      def initialize(format = nil)
        @format = format
        @resolver = build_resolver(format)
        @options = {}
      end

      def options=(value)
        @options = value || {}
      end

      def reset!
        @resolver = build_resolver(@format)
        @options = {}
      end

      # Profile accessor with ENV override support
      def profile
        @resolver.resolve(:profile)
      end

      def profile=(value)
        @resolver.set_programmatic(:profile, value)
      end

      # Return all profile-sourced values from the resolver, excluding
      # the :profile key itself (which is accessed via #profile).
      # These are the YAML-profile settings (e.g., preserve_whitespace_elements)
      # that are stored in the resolver's profile layer but not exposed
      # through the built-in MATCH_PROFILES system.
      #
      # @return [Hash] Profile option key-values (excluding :profile)
      def profile_options
        @resolver.profile.except(:profile)
      end

      # Element names where whitespace is PRESERVED exactly (no manipulation).
      # All whitespace characters are significant in these elements.
      def preserve_whitespace_elements
        @resolver.resolve(:preserve_whitespace_elements) || []
      end

      # Element names where whitespace is COLLAPSED (HTML-style behavior).
      # Multiple whitespace chars collapse to single space; boundaries preserved.
      def collapse_whitespace_elements
        @resolver.resolve(:collapse_whitespace_elements) || []
      end

      # Element names where whitespace-only text nodes are STRIPPED.
      def strip_whitespace_elements
        @resolver.resolve(:strip_whitespace_elements) || []
      end

      # Build match options from profile and options
      def to_h
        result = {}
        result[:match_profile] = profile if profile
        result[:match] = @options if @options && !@options.empty?
        result
      end

      def apply_profile_data(data)
        return unless data

        data.each do |key, value|
          sym_key = key.to_sym
          converted = value.is_a?(String) ? value.to_sym : value
          @resolver.set_profile(sym_key, converted)
        end
      end

      def clear_profile!
        @resolver.clear_profile!
      end

      private

      def build_resolver(format)
        defaults = {
          profile: nil,
        }

        env = format ? EnvProvider.load_match_for_format(format) : {}

        OverrideResolver.new(
          defaults: defaults,
          programmatic: {},
          env: env,
        )
      end
    end

    # Pretty-printer sub-configuration for display canonicalization.
    # Controls how documents are formatted by +Canon::PrettyPrinter::Xml+
    # when +display_preprocessing: :pretty_print+ is active.
    # The two attributes (+indent+ and +indent_type+) are backed by the
    # parent +DiffConfig+'s resolver so that ENV overrides (e.g.
    # +CANON_XML_DIFF_PRETTY_PRINTER_INDENT+) work automatically.
    class PrettyPrinterConfig
      def initialize(resolver)
        @resolver = resolver
      end

      def indent
        @resolver.resolve(:pretty_printer_indent)
      end

      def indent=(value)
        @resolver.set_programmatic(:pretty_printer_indent, value)
      end

      def indent_type
        @resolver.resolve(:pretty_printer_indent_type)
      end

      def indent_type=(value)
        @resolver.set_programmatic(:pretty_printer_indent_type, value)
      end
    end

    # Diff configuration for output formatting
    class DiffConfig
      attr_reader :pretty_printer

      def initialize(format = nil)
        @format = format
        @resolver = build_resolver(format)
        @pretty_printer = PrettyPrinterConfig.new(@resolver)
      end

      def reset!
        @resolver = build_resolver(@format)
        @pretty_printer = PrettyPrinterConfig.new(@resolver)
      end

      def apply_profile_data(data)
        return unless data

        data.each do |key, value|
          sym_key = key.to_sym
          @resolver.set_profile(sym_key, coerce_profile_value(sym_key, value))
        end
      end

      def clear_profile!
        @resolver.clear_profile!
      end

      # Accessors with ENV override support
      def mode
        @resolver.resolve(:mode)
      end

      def mode=(value)
        @resolver.set_programmatic(:mode, value)
      end

      def use_color
        @resolver.resolve(:use_color)
      end

      def use_color=(value)
        @resolver.set_programmatic(:use_color, value)
      end

      def context_lines
        @resolver.resolve(:context_lines)
      end

      def context_lines=(value)
        @resolver.set_programmatic(:context_lines, value)
      end

      def grouping_lines
        @resolver.resolve(:grouping_lines)
      end

      def grouping_lines=(value)
        @resolver.set_programmatic(:grouping_lines, value)
      end

      def show_diffs
        @resolver.resolve(:show_diffs)
      end

      def show_diffs=(value)
        @resolver.set_programmatic(:show_diffs, value)
      end

      def verbose_diff
        @resolver.resolve(:verbose_diff)
      end

      def verbose_diff=(value)
        @resolver.set_programmatic(:verbose_diff, value)
      end

      def show_raw_inputs
        @resolver.resolve(:show_raw_inputs)
      end

      def show_raw_inputs=(value)
        @resolver.set_programmatic(:show_raw_inputs, value)
      end

      # Show only the EXPECTED (fixture) block in the raw-inputs section.
      # Has no effect unless +show_raw_inputs+ or +verbose_diff+ is also set.
      # Use +show_raw_expected: false+ together with +show_raw_received: true+
      # (or +show_raw_inputs: true+) to suppress the fixture display while
      # keeping the received output.
      #
      # ENV variable: +CANON_<FORMAT>_DIFF_SHOW_RAW_EXPECTED+
      def show_raw_expected
        @resolver.resolve(:show_raw_expected)
      end

      def show_raw_expected=(value)
        @resolver.set_programmatic(:show_raw_expected, value)
      end

      # Show only the RECEIVED (actual) block in the raw-inputs section.
      # Combined with +show_raw_expected: false+ (or leaving it at the default
      # +false+) this suppresses the fixture while still displaying the output
      # that was generated.
      #
      # ENV variable: +CANON_<FORMAT>_DIFF_SHOW_RAW_RECEIVED+
      def show_raw_received
        @resolver.resolve(:show_raw_received)
      end

      def show_raw_received=(value)
        @resolver.set_programmatic(:show_raw_received, value)
      end

      def show_preprocessed_inputs
        @resolver.resolve(:show_preprocessed_inputs)
      end

      def show_preprocessed_inputs=(value)
        @resolver.set_programmatic(:show_preprocessed_inputs, value)
      end

      # Show only the EXPECTED (fixture) block in the preprocessed-inputs
      # section.  Has no effect unless +show_preprocessed_inputs+ or
      # +verbose_diff+ is also set.  Use +show_preprocessed_expected: true+
      # together with +show_preprocessed_received: false+ to display only the
      # preprocessed fixture while suppressing the preprocessed received output.
      #
      # ENV variable: +CANON_<FORMAT>_DIFF_SHOW_PREPROCESSED_EXPECTED+
      def show_preprocessed_expected
        @resolver.resolve(:show_preprocessed_expected)
      end

      def show_preprocessed_expected=(value)
        @resolver.set_programmatic(:show_preprocessed_expected, value)
      end

      # Show only the RECEIVED (actual) block in the preprocessed-inputs
      # section.  Combined with +show_preprocessed_expected: false+ (or leaving
      # it at the default +false+) this suppresses the fixture preprocessing
      # display while still showing what the received document looked like after
      # preprocessing.
      #
      # ENV variable: +CANON_<FORMAT>_DIFF_SHOW_PREPROCESSED_RECEIVED+
      def show_preprocessed_received
        @resolver.resolve(:show_preprocessed_received)
      end

      def show_preprocessed_received=(value)
        @resolver.set_programmatic(:show_preprocessed_received, value)
      end

      # Show both EXPECTED and RECEIVED blocks in a fixture-ready pretty-printed
      # section.  The output uses the same pretty-printer as
      # +display_preprocessing: :pretty_print+ (one tag per line, indentation)
      # but with *no* character visualization — whitespace appears as plain ASCII
      # so the output can be copy-pasted directly into RSpec fixture heredocs.
      #
      # ENV variable: +CANON_<FORMAT>_DIFF_SHOW_PRETTYPRINT_INPUTS+
      def show_prettyprint_inputs
        @resolver.resolve(:show_prettyprint_inputs)
      end

      def show_prettyprint_inputs=(value)
        @resolver.set_programmatic(:show_prettyprint_inputs, value)
      end

      # Show only the EXPECTED (fixture) block in the pretty-print section.
      # Useful when the fixture is what needs updating and the received side is
      # not needed for copy-pasting.
      #
      # ENV variable: +CANON_<FORMAT>_DIFF_SHOW_PRETTYPRINT_EXPECTED+
      def show_prettyprint_expected
        @resolver.resolve(:show_prettyprint_expected)
      end

      def show_prettyprint_expected=(value)
        @resolver.set_programmatic(:show_prettyprint_expected, value)
      end

      # Show only the RECEIVED (actual) block in the pretty-print section.
      # Use this to get a copy-pasteable pretty-printed form of the generated
      # output (the most common fixture-update workflow).
      #
      # ENV variable: +CANON_<FORMAT>_DIFF_SHOW_PRETTYPRINT_RECEIVED+
      def show_prettyprint_received
        @resolver.resolve(:show_prettyprint_received)
      end

      def show_prettyprint_received=(value)
        @resolver.set_programmatic(:show_prettyprint_received, value)
      end

      def show_line_numbered_inputs
        @resolver.resolve(:show_line_numbered_inputs)
      end

      def show_line_numbered_inputs=(value)
        @resolver.set_programmatic(:show_line_numbered_inputs, value)
      end

      def display_format
        @resolver.resolve(:display_format)
      end

      def display_format=(value)
        @resolver.set_programmatic(:display_format, value)
      end

      # Controls how documents are normalized *for display* before the line
      # diff. This is independent of +FormatConfig#preprocessing+, which
      # controls normalization for *comparison* (equivalence detection).
      #
      # Values:
      #   :none         - use documents as-is (default, existing behaviour)
      #   :pretty_print - run through Canon::PrettyPrinter::Xml before diffing
      #   :c14n         - run through XML C14N normalization before diffing
      def display_preprocessing
        @resolver.resolve(:display_preprocessing)
      end

      def display_preprocessing=(value)
        @resolver.set_programmatic(:display_preprocessing, value)
      end

      # Element names where whitespace is PRESERVED exactly (no manipulation).
      # All whitespace characters are significant in these elements.
      # ENV variable: +CANON_<FORMAT>_DIFF_PRESERVE_WHITESPACE_ELEMENTS+
      def preserve_whitespace_elements
        @resolver.resolve(:preserve_whitespace_elements) || []
      end

      def preserve_whitespace_elements=(value)
        @resolver.set_programmatic(:preserve_whitespace_elements, Array(value).map(&:to_s))
      end

      # Element names where whitespace is COLLAPSED (HTML-style behavior).
      # Multiple whitespace chars collapse to single space; boundaries preserved.
      # ENV variable: +CANON_<FORMAT>_DIFF_COLLAPSE_WHITESPACE_ELEMENTS+
      def collapse_whitespace_elements
        @resolver.resolve(:collapse_whitespace_elements) || []
      end

      def collapse_whitespace_elements=(value)
        @resolver.set_programmatic(:collapse_whitespace_elements, Array(value).map(&:to_s))
      end

      # Element names where whitespace-only text nodes are STRIPPED.
      # ENV variable: +CANON_<FORMAT>_DIFF_STRIP_WHITESPACE_ELEMENTS+
      def strip_whitespace_elements
        @resolver.resolve(:strip_whitespace_elements) || []
      end

      def strip_whitespace_elements=(value)
        @resolver.set_programmatic(:strip_whitespace_elements, Array(value).map(&:to_s))
      end

      # When true, whitespace-only text nodes starting with "\n" in :collapse
      # elements of the **expected** (fixture) document are treated as structural
      # indentation and dropped from both comparison and display.  Use this when
      # fixture files are indented but received XML is compact.
      # ENV variable: +CANON_<FORMAT>_DIFF_PRETTY_PRINTED_EXPECTED+
      def pretty_printed_expected
        @resolver.resolve(:pretty_printed_expected)
      end

      def pretty_printed_expected=(value)
        @resolver.set_programmatic(:pretty_printed_expected, value)
      end

      # When true, whitespace-only text nodes starting with "\n" in :normalize
      # elements of the **received** document are treated as structural
      # indentation and dropped from both comparison and display.  Use this when
      # received XML may be pretty-printed but the fixture is compact.
      # ENV variable: +CANON_<FORMAT>_DIFF_PRETTY_PRINTED_RECEIVED+
      def pretty_printed_received
        @resolver.resolve(:pretty_printed_received)
      end

      def pretty_printed_received=(value)
        @resolver.set_programmatic(:pretty_printed_received, value)
      end

      # When true, attributes on each element are sorted by namespace URI
      # then local name in the pretty-printed display, eliminating spurious
      # diff noise from differing attribute order.
      # ENV variable: +CANON_<FORMAT>_DIFF_PRETTY_PRINTER_SORT_ATTRIBUTES+
      def pretty_printer_sort_attributes
        @resolver.resolve(:pretty_printer_sort_attributes)
      end

      def pretty_printer_sort_attributes=(value)
        @resolver.set_programmatic(:pretty_printer_sort_attributes, value)
      end

      # Render element nodes in the Semantic Diff Report as compact inline XML
      # (e.g. +<strong>Annex</strong>+) instead of the verbose node_info
      # description string (e.g. "name: strong namespace_uri: …").
      #
      # Default: +false+ (keep existing verbose format for backwards compatibility)
      # ENV variable: +CANON_<FORMAT>_DIFF_COMPACT_SEMANTIC_REPORT+
      def compact_semantic_report
        @resolver.resolve(:compact_semantic_report)
      end

      def compact_semantic_report=(value)
        @resolver.set_programmatic(:compact_semantic_report, value)
      end

      # Show the full serialized node content (including children) in
      # element_structure diffs instead of just the tag name.
      #
      # Default: +false+ (show only the tag name, e.g. +<biblio-tag>+)
      # ENV variable: +CANON_<FORMAT>_DIFF_EXPAND_DIFFERENCE+
      def expand_difference
        @resolver.resolve(:expand_difference)
      end

      def expand_difference=(value)
        @resolver.set_programmatic(:expand_difference, value)
      end

      # Controls whether invisible characters (spaces, tabs, non-breaking
      # spaces, etc.) are replaced with visible Unicode symbols in diff output.
      #
      # Values:
      #   true          - apply the full default visualization map (default)
      #   false         - disable visualization; output plain text
      #   :content_only - reserved for future use; currently behaves as +true+.
      #                   Future intent: apply visualization only to DOM text
      #                   node content, not to structural indentation whitespace.
      #                   (TODO: implement DOM-level pre-serialization pass)
      def character_visualization
        val = @resolver.resolve(:character_visualization)
        # Coerce symbol booleans that may arrive via ENV (env_schema uses :symbol type
        # so "true"/"false" env strings become :true/:false symbols)
        case val
        when true, :true then true # rubocop:disable Lint/BooleanSymbol
        when false, :false then false # rubocop:disable Lint/BooleanSymbol
        else val # true/false from programmatic, or :content_only
        end
      end

      def character_visualization=(value)
        @resolver.set_programmatic(:character_visualization, value)
      end

      def algorithm
        @resolver.resolve(:algorithm)
      end

      def algorithm=(value)
        @resolver.set_programmatic(:algorithm, value)
      end

      # Theme name (:light, :dark, :retro, :claude)
      def theme
        @resolver.resolve(:theme)
      end

      def theme=(value)
        @resolver.set_programmatic(:theme, value)
      end

      # File size limit in bytes (default 5MB)
      def max_file_size
        @resolver.resolve(:max_file_size)
      end

      def max_file_size=(value)
        @resolver.set_programmatic(:max_file_size, value)
      end

      # Maximum node count in tree (default 10,000)
      def max_node_count
        @resolver.resolve(:max_node_count)
      end

      def max_node_count=(value)
        @resolver.set_programmatic(:max_node_count, value)
      end

      # Maximum diff output lines (default 10,000)
      def max_diff_lines
        @resolver.resolve(:max_diff_lines)
      end

      def max_diff_lines=(value)
        @resolver.set_programmatic(:max_diff_lines, value)
      end

      # Build diff options
      def to_h
        {
          diff: mode,
          use_color: use_color,
          context_lines: context_lines,
          grouping_lines: grouping_lines,
          show_diffs: show_diffs,
          verbose_diff: verbose_diff,
          diff_algorithm: algorithm,
          show_raw_inputs: show_raw_inputs,
          show_raw_expected: show_raw_expected,
          show_raw_received: show_raw_received,
          show_preprocessed_inputs: show_preprocessed_inputs,
          show_preprocessed_expected: show_preprocessed_expected,
          show_preprocessed_received: show_preprocessed_received,
          show_prettyprint_inputs: show_prettyprint_inputs,
          show_prettyprint_expected: show_prettyprint_expected,
          show_prettyprint_received: show_prettyprint_received,
          show_line_numbered_inputs: show_line_numbered_inputs,
          character_visualization: character_visualization,
          display_format: display_format,
          display_preprocessing: display_preprocessing,
          pretty_printer_indent: pretty_printer.indent,
          pretty_printer_indent_type: pretty_printer.indent_type,
          preserve_whitespace_elements: preserve_whitespace_elements,
          collapse_whitespace_elements: collapse_whitespace_elements,
          strip_whitespace_elements: strip_whitespace_elements,
          pretty_printed_expected: pretty_printed_expected,
          pretty_printed_received: pretty_printed_received,
          compact_semantic_report: compact_semantic_report,
          expand_difference: expand_difference,
          max_file_size: max_file_size,
          max_node_count: max_node_count,
          max_diff_lines: max_diff_lines,
          theme: theme,
        }
      end

      private

      def build_resolver(format)
        defaults = {
          mode: :by_line,
          use_color: ColorDetector.supports_color?,
          context_lines: 3,
          grouping_lines: 10,
          show_diffs: :all,
          verbose_diff: false,
          algorithm: :dom,
          show_raw_inputs: false,
          show_raw_expected: false,
          show_raw_received: false,
          show_preprocessed_inputs: false,
          show_preprocessed_expected: false,
          show_preprocessed_received: false,
          show_prettyprint_inputs: false,
          show_prettyprint_expected: false,
          show_prettyprint_received: false,
          show_line_numbered_inputs: false,
          character_visualization: true, # true, false, :content_only
          display_format: :raw,          # :raw = no formatting, :canonical = HTML-aware formatting
          display_preprocessing: :none,  # :none, :pretty_print, :c14n
          pretty_printer_indent: 2,
          pretty_printer_indent_type: :space, # :space or :tab
          preserve_whitespace_elements: [],
          collapse_whitespace_elements: [],
          strip_whitespace_elements: [],
          pretty_printed_expected: false,
          pretty_printed_received: false,
          pretty_printer_sort_attributes: false,
          compact_semantic_report: false,
          expand_difference: false,
          max_file_size: 5_242_880,      # 5MB in bytes
          max_node_count: 10_000,        # Maximum nodes in tree
          max_diff_lines: 10_000,        # Maximum diff output lines
          theme: :dark, # Default theme
        }

        env = format ? EnvProvider.load_diff_for_format(format) : {}

        OverrideResolver.new(
          defaults: defaults,
          programmatic: {},
          env: env,
        )
      end

      # Coerce a YAML value to the appropriate Ruby type based on EnvSchema.
      # YAML natively handles booleans, integers, and arrays, but symbols
      # arrive as strings and need conversion.
      def coerce_profile_value(key, value)
        return value if value.is_a?(Array) # string_array already correct from YAML

        type = EnvSchema.type_for(key)
        case type
        when :symbol
          value.is_a?(String) ? value.to_sym : value
        when :boolean
          # YAML booleans are already true/false
          value
        when :integer
          value.is_a?(String) ? Integer(value) : value
        else
          value
        end
      end
    end

    private

    def apply_profile(name_or_path)
      data = ProfileLoader.load(name_or_path)
      shared = data["shared"] || {}
      formats = data["formats"] || {}

      format_configs.each do |fmt_key, fmt_cfg|
        fmt_data = ProfileLoader.send(:deep_merge, shared, formats[fmt_key.to_s] || {})
        fmt_cfg.apply_profile_data(fmt_data)
      end
    end

    def clear_profile_values!
      format_configs.each_value(&:clear_profile!)
    end

    def format_configs
      { xml: @xml, html: @html, json: @json, yaml: @yaml, string: @string }
    end
  end
end
