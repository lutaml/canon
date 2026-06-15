# frozen_string_literal: true

module Canon
  # Global configuration for Canon
  # Provides unified configuration across CLI, Ruby API, and RSpec interfaces
  class Config
    autoload :ConfigDSL, "canon/config/config_dsl"
    autoload :EnvProvider, "canon/config/env_provider"
    autoload :EnvSchema, "canon/config/env_schema"
    autoload :OverrideResolver, "canon/config/override_resolver"
    autoload :ProfileLoader, "canon/config/profile_loader"
    autoload :TypeConverter, "canon/config/type_converter"

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
        if %i[xml html json yaml string profile profile= diff_mode diff_mode=
              use_color use_color= xml_match_profile xml_match_profile=
              html_match_profile html_match_profile= reset!].include?(method)
          @instance.public_send(method, ...)
        else
          super
        end
      end

      def respond_to_missing?(method, include_private = false)
        %i[xml html json yaml string profile profile= diff_mode diff_mode=
           use_color use_color= xml_match_profile xml_match_profile=
           html_match_profile html_match_profile= reset!].include?(method) || super
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
        DiffConfig.validate_config_value!(:pretty_printer_indent_type, value)
        @resolver.set_programmatic(:pretty_printer_indent_type, value)
      end
    end

    # Diff configuration for output formatting
    #
    # Each user-tunable attribute is declared with +config_key+ via the
    # +ConfigDSL+ module.  The DSL generates the matching getter/setter
    # pair and registers metadata (type, enum, default) so +EnvSchema+
    # and +TypeConverter+ can discover it without re-declaring it
    # (lutaml/canon TODO.improve/07 — single source of truth).
    class DiffConfig
      extend ConfigDSL

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
          coerced = coerce_profile_value(sym_key, value)
          self.class.validate_config_value!(sym_key, coerced)
          @resolver.set_profile(sym_key, coerced)
        end
      end

      def clear_profile!
        @resolver.clear_profile!
      end

      # --- Attribute declarations --------------------------------------

      config_key :mode, type: :symbol,
                        enum: %i[by_line by_object pretty_diff],
                        default: :by_line
      config_key :use_color, type: :boolean,
                             default: -> { ColorDetector.supports_color? }
      config_key :context_lines, type: :integer, default: 3
      config_key :grouping_lines, type: :integer, default: 10
      config_key :show_diffs, type: :symbol,
                              enum: %i[all normative informative],
                              default: :all
      config_key :verbose_diff, type: :boolean, default: false
      config_key :algorithm, type: :symbol, enum: %i[dom semantic],
                             default: :dom
      config_key :parser, type: :symbol, enum: %i[sax dom], default: :sax

      config_key :show_raw_inputs, type: :boolean, default: false
      config_key :show_raw_expected, type: :boolean, default: false
      config_key :show_raw_received, type: :boolean, default: false
      config_key :show_preprocessed_inputs, type: :boolean, default: false
      config_key :show_preprocessed_expected, type: :boolean, default: false
      config_key :show_preprocessed_received, type: :boolean, default: false
      config_key :show_prettyprint_inputs, type: :boolean, default: false
      config_key :show_prettyprint_expected, type: :boolean, default: false
      config_key :show_prettyprint_received, type: :boolean, default: false
      config_key :show_line_numbered_inputs, type: :boolean, default: false

      config_key :display_format, type: :symbol, enum: %i[raw canonical],
                                  default: :raw
      config_key :display_preprocessing, type: :symbol,
                                         enum: %i[none pretty_print
                                                  normalize_pretty_print c14n],
                                         default: :none

      config_key :preserve_whitespace_elements,
                 type: :string_array,
                 default: [],
                 coerce: ->(v) { Array(v).map(&:to_s) },
                 getter_coerce: ->(v) { v || [] }
      config_key :collapse_whitespace_elements,
                 type: :string_array,
                 default: [],
                 coerce: ->(v) { Array(v).map(&:to_s) },
                 getter_coerce: ->(v) { v || [] }
      config_key :strip_whitespace_elements,
                 type: :string_array,
                 default: [],
                 coerce: ->(v) { Array(v).map(&:to_s) },
                 getter_coerce: ->(v) { v || [] }

      config_key :pretty_printed_expected, type: :boolean, default: false
      config_key :pretty_printed_received, type: :boolean, default: false
      config_key :pretty_printer_sort_attributes, type: :boolean,
                                                  default: false
      config_key :compact_semantic_report, type: :boolean, default: false
      config_key :expand_difference, type: :boolean, default: false

      # Accepts +true+, +false+, or +:content_only+.  ENV-supplied
      # +"true"/"false"+ strings arrive as +:true/:false+ (TypeConverter
      # uses the +:symbol+ type) so the getter coerces them back to
      # booleans.
      config_key :character_visualization,
                 type: :symbol,
                 enum: [true, false, :content_only],
                 default: true,
                 getter_coerce: lambda { |val|
                   case val
                   when true, :true then true # rubocop:disable Lint/BooleanSymbol
                   when false, :false then false # rubocop:disable Lint/BooleanSymbol
                   else val
                   end
                 }

      config_key :theme, type: :symbol,
                         enum: %i[light dark retro claude cyberpunk],
                         default: :dark
      config_key :theme_inheritance, type: :pass_through, default: nil
      config_key :custom_theme, type: :pass_through, default: nil

      config_key :max_file_size, type: :integer, default: 5_242_880
      config_key :max_node_count, type: :integer, default: 10_000
      config_key :max_diff_lines, type: :integer, default: 10_000

      # Pretty-printer keys are declared here so they participate in
      # +config_keys+ (for EnvSchema discovery and validation) even
      # though user code reaches them via the +PrettyPrinterConfig+
      # facade through +DiffConfig#pretty_printer+.
      config_key :pretty_printer_indent, type: :integer, default: 2
      config_key :pretty_printer_indent_type, type: :symbol,
                                              enum: %i[space tab],
                                              default: :space

      # Enum constraint map derived from declared config keys.  Kept as a
      # constant for backward compatibility with code that referenced
      # +DiffConfig::VALID_ENUM_VALUES+ directly.  Must be assigned AFTER
      # all +config_key+ declarations above so the registry is populated.
      VALID_ENUM_VALUES = enum_values.freeze

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
          parser: parser,
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
        defaults = self.class.config_keys.each_with_object({}) do |(k, _m), h|
          h[k] = self.class.resolve_default(k)
        end

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
        fmt_data = ProfileLoader.deep_merge(shared,
                                            formats[fmt_key.to_s] || {})
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
