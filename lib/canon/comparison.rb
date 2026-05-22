# frozen_string_literal: true

require "moxml"
require "nokogiri" if Canon::XmlBackend.nokogiri?
require_relative "xml/whitespace_normalizer"
require_relative "comparison/xml_comparator"
require_relative "comparison/html_comparator"
require_relative "comparison/json_comparator"
require_relative "comparison/yaml_comparator"
require_relative "errors"
require_relative "comparison/profile_definition"
require_relative "comparison/format_detector"
require_relative "comparison/html_parser"
require_relative "diff/diff_node_mapper"
require_relative "diff/diff_line"
require_relative "diff/diff_block_builder"
require_relative "diff/diff_context_builder"
require_relative "diff/diff_report_builder"
require_relative "cache"

module Canon
  # Comparison module for XML, HTML, JSON, and YAML documents
  #
  # This module provides a unified comparison API for multiple serialization formats.
  # It auto-detects the format and delegates to specialized comparators while
  # maintaining a CompareXML-compatible API.
  #
  # == Supported Formats
  #
  # - **XML**: Uses Moxml for parsing, supports namespaces
  # - **HTML**: Uses Nokogiri, handles HTML4/HTML5 differences
  # - **JSON**: Direct Ruby object comparison with deep equality
  # - **YAML**: Parses to Ruby objects, compares semantically
  #
  # == Format Detection
  #
  # The module automatically detects format from:
  # - Object type (Moxml::Node, Nokogiri::HTML::Document, Hash, Array)
  # - String content (DOCTYPE, opening tags, YAML/JSON syntax)
  #
  # == Comparison Options
  #
  # Common options across all formats:
  # - profile: Comparison profile (Symbol for preset, Hash for custom)
  #   * Presets: :strict, :rendered, :html4, :html5, :spec_friendly, :content_only
  #   * Custom: { text_content: :normalize, comments: :ignore, ... }
  # - diff_algorithm: Algorithm to use (:dom or :semantic, default: :dom)
  # - verbose: Return detailed diff array (default: false)
  #
  # == Usage Examples
  #
  #   # XML comparison with default profile
  #   Canon::Comparison.equivalent?(xml1, xml2)
  #
  #   # XML comparison with preset profile
  #   Canon::Comparison.equivalent?(xml1, xml2, profile: :strict)
  #   Canon::Comparison.equivalent?(xml1, xml2, profile: :spec_friendly)
  #
  #   # HTML comparison with custom inline profile
  #   Canon::Comparison.equivalent?(html1, html2,
  #     profile: { text_content: :normalize, comments: :ignore })
  #
  #   # Define and use a custom profile
  #   Canon::Comparison.define_profile(:my_custom) do
  #     text_content :normalize
  #     comments :ignore
  #     preprocessing :rendered
  #   end
  #   Canon::Comparison.equivalent?(doc1, doc2, profile: :my_custom)
  #
  #   # JSON comparison with semantic tree diff
  #   Canon::Comparison.equivalent?(json1, json2,
  #     diff_algorithm: :semantic, profile: :spec_friendly)
  #
  #   # With detailed output
  #   diffs = Canon::Comparison.equivalent?(doc1, doc2, verbose: true)
  #   diffs.each { |diff| puts diff.inspect }
  #
  # == XML Declaration Handling
  #
  # XML declarations (`<?xml version="1.0" encoding="UTF-8"?>`) are stripped
  # during preprocessing for semantic comparison. This means:
  #
  # - Documents with and without declarations are considered equivalent
  # - Declaration encoding differences are ignored
  # - Entity declarations within DTD are resolved before comparison
  #
  # This behavior ensures documents are compared by their content, not
  # their serialization format.
  #
  # == Return Values
  #
  # - When verbose: false (default) → Boolean (true if equivalent)
  # - When verbose: true → Array of difference hashes with details
  #
  # == Difference Hash Format
  #
  # Each difference contains:
  # - node1, node2: The nodes being compared (XML/HTML)
  # - diff1, diff2: Comparison result codes
  # - OR for JSON/YAML:
  # - path: String path to the difference (e.g., "user.address.city")
  # - value1, value2: The differing values
  # - diff_code: Type of difference
  #
  module Comparison
    autoload :ChildRealignment, "canon/comparison/child_realignment"

    # Comparison result constants
    EQUIVALENT = 1
    MISSING_ATTRIBUTE = 2
    MISSING_NODE = 3
    UNEQUAL_ATTRIBUTES = 4
    UNEQUAL_COMMENTS = 5
    UNEQUAL_DOCUMENTS = 6
    UNEQUAL_ELEMENTS = 7
    UNEQUAL_NODES_TYPES = 8
    UNEQUAL_TEXT_CONTENTS = 9
    MISSING_HASH_KEY = 10
    UNEQUAL_HASH_VALUES = 11
    UNEQUAL_HASH_KEY_ORDER = 12
    UNEQUAL_ARRAY_LENGTHS = 13
    UNEQUAL_ARRAY_ELEMENTS = 14
    UNEQUAL_TYPES = 15
    UNEQUAL_PRIMITIVES = 16

    # Human-readable labels for the integer comparison-result constants
    # above.  Used by the diff reason builders so user-facing reason text
    # never leaks raw numeric codes (e.g. "7 vs 7" — see lutaml/canon#127).
    # String diff codes (e.g. "position 3" emitted by ChildComparison)
    # pass through +code_label+ unchanged.
    CODE_LABELS = {
      EQUIVALENT => "equivalent",
      MISSING_ATTRIBUTE => "missing attribute",
      MISSING_NODE => "missing",
      UNEQUAL_ATTRIBUTES => "attributes differ",
      UNEQUAL_COMMENTS => "comments differ",
      UNEQUAL_DOCUMENTS => "documents differ",
      UNEQUAL_ELEMENTS => "elements differ",
      UNEQUAL_NODES_TYPES => "node types differ",
      UNEQUAL_TEXT_CONTENTS => "text content differs",
      MISSING_HASH_KEY => "missing hash key",
      UNEQUAL_HASH_VALUES => "hash values differ",
      UNEQUAL_HASH_KEY_ORDER => "hash key order differs",
      UNEQUAL_ARRAY_LENGTHS => "array lengths differ",
      UNEQUAL_ARRAY_ELEMENTS => "array elements differ",
      UNEQUAL_TYPES => "types differ",
      UNEQUAL_PRIMITIVES => "primitives differ",
    }.freeze

    # Translate a comparison result code (Integer constant or String label
    # like "position 3") into a human-readable reason fragment.  Unknown
    # values pass through via +to_s+ as a defensive fallback.
    #
    # @param code [Integer, String] Comparison result code
    # @return [String] Human-readable label
    def self.code_label(code)
      return code if code.is_a?(String)

      CODE_LABELS[code] || code.to_s
    end

    # Build a "diff1 [vs diff2]" reason fragment that never leaks raw
    # integer constants.  When both codes are equal, returns the single
    # label (e.g. "elements differ") rather than "elements differ vs
    # elements differ".  See lutaml/canon#127.
    #
    # @param diff1 [Integer, String] First diff code
    # @param diff2 [Integer, String] Second diff code
    # @return [String] Reason fragment
    def self.code_pair_label(diff1, diff2)
      return code_label(diff1) if diff1 == diff2

      "#{code_label(diff1)} vs #{code_label(diff2)}"
    end

    # Extract parse-time errors from a parsed-tree or Nokogiri fragment.
    # Delegates to NodeInspector for cross-backend type dispatch.
    #
    # @param node [Object, nil] Parsed node
    # @return [Array<String>] Parse errors as strings (empty by default)
    def self.parse_errors_for(node)
      NodeInspector.parse_errors(node)
    end

    class << self
      # Auto-detect format and compare two objects
      #
      # @param obj1 [Object] First object to compare
      # @param obj2 [Object] Second object to compare
      # @param opts [Hash] Comparison options
      #   - :profile - Profile to use (Symbol for preset, Hash for custom)
      #   - :format - Format hint (:xml, :html, :html4, :html5, :json, :yaml, :string)
      #   - :diff_algorithm - Algorithm to use (:dom or :semantic)
      #   - :verbose - Return detailed diff array (default: false)
      # @return [Boolean, Array] true if equivalent, or array of diffs if verbose
      def equivalent?(obj1, obj2, opts = {})
        # Check if semantic tree diff is requested
        # Support both :semantic and :semantic_tree for backward compatibility
        if %i[semantic semantic_tree].include?(opts[:diff_algorithm])
          return semantic_diff(obj1, obj2, opts)
        end

        # Otherwise use DOM-based comparison (default)
        dom_diff(obj1, obj2, opts)
      end

      # Summarize the first difference between two documents.
      #
      # Returns a human-readable string describing the first difference
      # when documents differ, or "Equivalent" when they match.
      # This is a lightweight alternative to +equivalent?+ with +verbose: true+.
      #
      # @param obj1 [Object] First object to compare
      # @param obj2 [Object] Second object to compare
      # @param opts [Hash] Comparison options (same as +equivalent?+)
      # @return [String] Summary string
      #
      # @example
      #   Canon::Comparison.summarize("<p>Hello</p>", "<p>World</p>")
      #   # => "Not equivalent: text content differs at /p[1] (Hello vs World)"
      #
      #   Canon::Comparison.summarize("<p>Hello</p>", "<p>Hello</p>")
      #   # => "Equivalent"
      def summarize(obj1, obj2, opts = {})
        result = equivalent?(obj1, obj2, opts.merge(verbose: true))

        if result.is_a?(ComparisonResult)
          result.summary
        elsif result == true
          "Equivalent"
        else
          "Not equivalent"
        end
      end

      # Define a custom comparison profile with DSL syntax
      #
      # @param name [Symbol] Profile name
      # @yield [ProfileDefinition] DSL block for defining profile
      # @return [Symbol] Profile name
      # @raise [ProfileError] if profile definition is invalid
      #
      # @example Define a custom profile
      #   Canon::Comparison.define_profile(:my_custom) do
      #     text_content :normalize
      #     comments :ignore
      #     preprocessing :rendered
      #   end
      def define_profile(name, &block)
        definition = ProfileDefinition.define(name, &block)

        @custom_profiles ||= {}
        @custom_profiles[name] = definition

        name
      end

      # Load a profile (custom or preset)
      #
      # @param name [Symbol] Profile name
      # @return [Hash] Profile settings
      def load_profile(name)
        # Check custom profiles first
        if @custom_profiles&.key?(name)
          return @custom_profiles[name].dup
        end

        # Fall back to presets - try Xml first (most common)
        begin
          MatchOptions::Xml.get_profile_options(name)
        rescue Error
          # Try other formats
          MatchOptions::Json.get_profile_options(name)
        end
      end

      # List all available profiles (custom + presets)
      #
      # @return [Array<Symbol>] Available profile names
      def available_profiles
        custom = @custom_profiles&.keys || []
        presets = MatchOptions::Xml::MATCH_PROFILES.keys
        (custom + presets).sort.uniq
      end

      private

      # Perform semantic tree diff comparison
      def semantic_diff(obj1, obj2, opts = {})
        require_relative "tree_diff"

        # Capture original strings BEFORE any parsing/transformation
        # These are used for display to preserve original formatting
        format_hint = opts[:format]
        original_str1 = extract_original_string(obj1, format_hint)
        original_str2 = extract_original_string(obj2, format_hint)

        # Detect format for both objects
        format1 = opts[:format] || FormatDetector.detect(obj1)
        format2 = opts[:format] || FormatDetector.detect(obj2)

        # Handle string format (plain text comparison) - semantic tree doesn't support it
        if format1 == :string
          if opts[:verbose]
            return obj1.to_s == obj2.to_s ? [] : [:different]
          else
            return obj1.to_s == obj2.to_s
          end
        end

        # Ensure formats match
        unless format1 == format2
          raise Canon::CompareFormatMismatchError.new(format1, format2)
        end

        # Get global config options if not defined in opts
        # This is needed because semantic_diff doesn't go through dom_diff's config handling
        if !(opts[:match_profile] || opts[:global_options]) && %i[xml html json yaml string].include?(format1)
          format_config = Canon::Config.instance.public_send(format1)
          if format_config.match.profile
            opts[:match_profile] =
              format_config.match.profile
          end
          if format_config.match.options && !format_config.match.options.empty?
            opts[:global_options] =
              format_config.match.options
          end
        end

        # Resolve match options for the format
        match_opts_hash = resolve_match_options(format1, opts)

        # Also read diff options from config (e.g., max_node_count for large documents)
        # This is independent of match options and needs to be passed to TreeDiffIntegrator
        if !match_opts_hash[:max_node_count] && %i[xml html json yaml string].include?(format1)
          diff_max_node = Canon::Config.instance.public_send(format1).diff.max_node_count
          if diff_max_node > 10_000
            match_opts_hash[:max_node_count] =
              diff_max_node
          end
        end

        # Delegate parsing to comparators (reuses existing preprocessing logic)
        doc1, doc2 = parse_with_comparator(obj1, obj2, format1, match_opts_hash)

        # Normalize format for TreeDiff (html4/html5 -> html)
        tree_diff_format = normalize_format_for_tree_diff(format1)

        # Create TreeDiff integrator for the format
        # CRITICAL: Use match_opts_hash (resolved options with profile) not opts[:match]
        integrator = Canon::TreeDiff::TreeDiffIntegrator.new(
          format: tree_diff_format,
          options: match_opts_hash,
        )

        # Perform diff
        tree_diff_result = integrator.diff(doc1, doc2)

        # Extract only match-related keys for OperationConverter and SemanticTreeMatchStrategy
        # These components expect match options, not diff options like max_node_count
        match_only_keys = %i[match_profile match preprocessing
                             text_content structural_whitespace attribute_presence
                             attribute_order attribute_values element_position
                             comments format similarity_threshold hash_matching
                             similarity_matching propagation
                             preserve_whitespace_elements
                             collapse_whitespace_elements
                             strip_whitespace_elements respect_xml_space]
        match_options_only = match_opts_hash.slice(*match_only_keys)

        # Convert operations to DiffNodes for unified pipeline
        # CRITICAL: Use match_opts_hash (resolved options with profile) not opts[:match]
        converter = Canon::TreeDiff::OperationConverter.new(
          format: format1,
          match_options: match_options_only,
        )
        diff_nodes = converter.convert(tree_diff_result[:operations])

        # CRITICAL: Use strategy's preprocess_for_display to ensure proper line-breaking
        # This matches DOM diff preprocessing pattern (xml_comparator.rb:106-109)
        require_relative "comparison/strategies/semantic_tree_match_strategy"
        strategy = Comparison::Strategies::SemanticTreeMatchStrategy.new(
          format: format1, match_options: match_options_only,
        )
        str1, str2 = strategy.preprocess_for_display(doc1, doc2)

        # Store tree diff data in match_options for access via result
        enhanced_match_options = match_opts_hash.merge(
          tree_diff_operations: tree_diff_result[:operations],
          tree_diff_statistics: tree_diff_result[:statistics],
          tree_diff_matching: tree_diff_result[:matching],
        )

        # Create ComparisonResult for unified handling
        result = Canon::Comparison::ComparisonResult.new(
          differences: diff_nodes,
          preprocessed_strings: [str1, str2],
          original_strings: [original_str1, original_str2],
          format: format1,
          html_version: %i[html4 html5].include?(format1) ? format1 : nil,
          match_options: enhanced_match_options,
          algorithm: :semantic,
        )

        # Return boolean or ComparisonResult based on verbose flag
        if opts[:verbose]
          result
        else
          result.equivalent?
        end
      end

      # Resolve match options for a format
      #
      # @param format [Symbol] Format type
      # @param opts [Hash] User options
      # @return [Hash] Resolved match options
      def resolve_match_options(format, opts)
        # Process unified profile parameter first
        processed_opts = process_profile_parameter(opts)

        case format
        when :xml, :html, :html4, :html5
          MatchOptions::Xml.resolve(
            format: format,
            match_profile: processed_opts[:match_profile],
            match: processed_opts[:match],
            preprocessing: processed_opts[:preprocessing],
            global_profile: processed_opts[:global_profile],
            global_options: processed_opts[:global_options],
          )
        when :json
          MatchOptions::Json.resolve(
            format: format,
            match_profile: processed_opts[:match_profile],
            match: processed_opts[:match],
            preprocessing: processed_opts[:preprocessing],
            global_profile: processed_opts[:global_profile],
            global_options: processed_opts[:global_options],
          )
        when :yaml
          MatchOptions::Yaml.resolve(
            format: format,
            match_profile: processed_opts[:match_profile],
            match: processed_opts[:match],
            preprocessing: processed_opts[:preprocessing],
            global_profile: processed_opts[:global_profile],
            global_options: processed_opts[:global_options],
          )
        else
          processed_opts[:match] || {}
        end
      end

      # Process unified profile parameter
      #
      # Converts the new :profile parameter into the legacy format expected
      # by MatchOptions resolvers. Handles:
      # - Symbol → preset profile (uses :match_profile)
      # - Hash → custom profile (validates and uses :match)
      #
      # @param opts [Hash] Original user options
      # @return [Hash] Processed options with legacy format
      def process_profile_parameter(opts)
        processed = opts.dup

        # Handle unified :profile parameter
        if opts.key?(:profile)
          profile = opts[:profile]

          case profile
          when Symbol
            # Preset profile name
            processed[:match_profile] = profile
          when Hash
            # Inline custom profile - validate and use as :match
            validate_custom_profile!(profile, format_from_opts(opts))
            processed[:match] = profile
          else
            raise Canon::Error,
                  "Invalid profile type: #{profile.class}. " \
                  "Expected Symbol (preset name) or Hash (custom profile)."
          end
        end

        processed
      end

      # Validate custom profile hash
      #
      # Ensures all dimensions and behaviors in a custom profile are valid.
      # Uses ProfileDefinition validation logic.
      #
      # @param profile [Hash] Custom profile hash
      # @param format [Symbol] Format type for validation context
      # @raise [Canon::Error] if profile contains invalid dimensions or behaviors
      def validate_custom_profile!(profile, format)
        profile.each do |dimension, behavior|
          # Skip preprocessing and special options
          next if dimension == :preprocessing
          next if dimension == :semantic_diff
          next if dimension == :similarity_threshold

          # Validate dimension is known
          valid_dimensions = valid_dimensions_for_format(format)
          unless valid_dimensions.include?(dimension)
            raise Canon::Error,
                  "Unknown dimension: #{dimension}. " \
                  "Valid dimensions for #{format}: #{valid_dimensions.join(', ')}"
          end

          # Validate behavior is allowed for this dimension
          valid_behaviors = ProfileDefinition::DIMENSION_BEHAVIORS[dimension]
          if valid_behaviors && !valid_behaviors.include?(behavior)
            raise Canon::Error,
                  "Invalid behavior '#{behavior}' for dimension '#{dimension}'. " \
                  "Valid behaviors: #{valid_behaviors.join(', ')}"
          end

          # Validate behavior is in general MATCH_BEHAVIORS
          unless MatchOptions::MATCH_BEHAVIORS.include?(behavior)
            raise Canon::Error,
                  "Unknown match behavior: #{behavior}. " \
                  "Valid behaviors: #{MatchOptions::MATCH_BEHAVIORS.join(', ')}"
          end
        end
      end

      # Get valid dimensions for a format
      #
      # @param format [Symbol] Format type
      # @return [Array<Symbol>] Valid dimensions for the format
      def valid_dimensions_for_format(format)
        case format
        when :xml, :html, :html4, :html5
          MatchOptions::Xml::MATCH_DIMENSIONS
        when :json
          MatchOptions::Json::MATCH_DIMENSIONS
        when :yaml
          MatchOptions::Yaml::MATCH_DIMENSIONS
        else
          []
        end
      end

      # Helper to extract format from opts for validation
      #
      # @param opts [Hash] User options
      # @return [Symbol] Format type or :xml as default
      def format_from_opts(opts)
        opts[:format] || :xml
      end

      # Parse documents using comparator's parse logic (reuses preprocessing)
      #
      # @param obj1 [Object] First object
      # @param obj2 [Object] Second object
      # @param format [Symbol] Format type
      # @param match_opts_hash [Hash] Resolved match options
      # @return [Array<Object, Object>] Parsed documents
      def parse_with_comparator(obj1, obj2, format, match_opts_hash)
        preprocessing = match_opts_hash[:preprocessing] || :none

        case format
        when :xml
          # Delegate to XmlComparator's parse - returns Canon::Xml::Node
          doc1 = parse_with_cache(obj1, format, preprocessing) do |doc|
            XmlComparator.parse(doc, preprocessing)
          end
          doc2 = parse_with_cache(obj2, format, preprocessing) do |doc|
            XmlComparator.parse(doc, preprocessing)
          end
          [doc1, doc2]
        when :html, :html4, :html5
          [
            parse_with_cache(obj1, format, preprocessing) do |doc|
              HtmlComparator.parse(doc, preprocessing)
            end,
            parse_with_cache(obj2, format, preprocessing) do |doc|
              HtmlComparator.parse(doc, preprocessing)
            end,
          ]
        when :json
          [
            parse_with_cache(obj1, format, :none) do |doc|
              JsonComparator.parse(doc)
            end,
            parse_with_cache(obj2, format, :none) do |doc|
              JsonComparator.parse(doc)
            end,
          ]
        when :yaml
          [
            parse_with_cache(obj1, format, :none) do |doc|
              YamlComparator.parse(doc)
            end,
            parse_with_cache(obj2, format, :none) do |doc|
              YamlComparator.parse(doc)
            end,
          ]
        else
          [obj1, obj2]
        end
      end

      # Parse a document with caching
      #
      # @param doc [Object] Document to parse (string or already parsed)
      # @param format [Symbol] Document format
      # @param preprocessing [Symbol] Preprocessing option
      # @yield Block to parse the document if not cached
      # @return [Object] Parsed document
      def parse_with_cache(doc, format, preprocessing)
        # If already a parsed node, return as-is
        return doc unless doc.is_a?(String)

        # Use cache for string documents
        Cache.fetch(:document_parse,
                    Cache.key_for_document(doc, format, preprocessing)) do # rubocop:disable Lint/UselessDefaultValueArgument
          yield doc
        end
      end

      # Normalize format for TreeDiff (html4/html5 -> html)
      #
      # @param format [Symbol] Original format
      # @return [Symbol] Normalized format for TreeDiff
      def normalize_format_for_tree_diff(format)
        case format
        when :html4, :html5
          :html
        else
          format
        end
      end

      # Extract original string from various input types
      # This preserves the original formatting without minification
      #
      # @param obj [String, Nokogiri::Node, Canon::Xml::Node, Object] Input object
      # @param format [Symbol] Format type for context
      # @return [String] Original string representation
      def extract_original_string(obj, _format = nil)
        case obj
        when String
          obj
        when Nokogiri::XML::Document, Nokogiri::HTML::Document,
             Nokogiri::XML::DocumentFragment, Nokogiri::HTML::DocumentFragment
          obj.to_html
        else
          if Canon::XmlParsing.xml_node?(obj) || obj.is_a?(Canon::Xml::Node)
            Canon::XmlParsing.serialize(obj)
          else
            obj.to_s
          end
        end
      end

      # Serialize document back to string
      def serialize_document(doc, format)
        case format
        when :xml, :html, :html4, :html5
          if Canon::XmlParsing.xml_node?(doc) || doc.is_a?(Canon::Xml::Node)
            Canon::XmlParsing.serialize(doc)
          else
            doc.to_s
          end
        when :json
          require "json"
          JSON.pretty_generate(doc)
        when :yaml
          require "yaml"
          doc.to_yaml
        else
          doc.to_s
        end
      rescue StandardError
        doc.to_s
      end

      # Perform DOM-based comparison (original behavior)
      def dom_diff(obj1, obj2, opts = {})
        # Use format hint if provided
        if opts[:format]
          format1 = format2 = opts[:format]
          # Parse HTML strings if format is html/html4/html5
          if %i[html html4 html5].include?(opts[:format])
            # Preserve original strings for display (HTML fragment
            # parsers can mutate the DOM).
            opts[:_original_str1] = obj1.dup if obj1.is_a?(String)
            opts[:_original_str2] = obj2.dup if obj2.is_a?(String)
            # Parse all HTML formats (:html, :html4, :html5) with
            # Nokogiri::HTML5 so that html4 and html5 share HTML's
            # whitespace-sensitivity semantics (issue #118).
            #
            # The previous html/html4 branch used Nokogiri::XML.fragment
            # to dodge Nokogiri::HTML4.fragment's destructive DOM
            # mutations. That avoided one problem but introduced a
            # bigger one: XML whitespace rules were being applied to
            # HTML content. HTML's content model — identical between
            # HTML4 and HTML5 — treats whitespace-only text between
            # block-level children as insignificant; XML treats every
            # whitespace text node as significant. Routing html4 input
            # through an XML parser therefore made
            # be_html4_equivalent_to reject inputs that
            # be_html5_equivalent_to (correctly) accepts.
            # Nokogiri::HTML5.fragment is non-destructive (the original
            # HTML4.fragment concern does not apply to it) and applies
            # HTML's content model uniformly.
            obj1 = HtmlParser.parse(obj1, :html5) if obj1.is_a?(String)
            obj2 = HtmlParser.parse(obj2, :html5) if obj2.is_a?(String)
          end
        else
          format1 = FormatDetector.detect(obj1)
          format2 = FormatDetector.detect(obj2)
        end

        # Handle string format (plain text comparison)
        if format1 == :string
          if opts[:verbose]
            return obj1.to_s == obj2.to_s ? [] : [:different]
          else
            return obj1.to_s == obj2.to_s
          end
        end

        # Allow comparing json/yaml strings with ruby objects
        # since they parse to the same structure
        formats_compatible = format1 == format2 ||
          (%i[json ruby_object].include?(format1) &&
           %i[json ruby_object].include?(format2)) ||
          (%i[yaml ruby_object].include?(format1) &&
           %i[yaml ruby_object].include?(format2))

        unless formats_compatible
          raise Canon::CompareFormatMismatchError.new(format1, format2)
        end

        # Normalize format for comparison
        comparison_format = case format1
                            when :ruby_object
                              # If comparing ruby_object with json/yaml, use that format
                              %i[json yaml].include?(format2) ? format2 : :json
                            else
                              format1
                            end

        # get match_profile if it is not defined in options
        # but defined in config
        if %i[xml html json yaml string].include?(comparison_format)
          format_config = Canon::Config.instance.public_send(comparison_format)
          if opts[:global_profile].nil? && format_config.match.profile
            # Config-sourced profile has *global* priority (applied before
            # global_options), so that YAML profile_options like
            # whitespace_type: :normalize can override the built-in profile
            # (e.g. :spec_friendly)'s whitespace_type: :strict.  Writing to
            # :match_profile here gave the config profile per-call priority,
            # which incorrectly overrode the YAML's own overrides.
            opts[:global_profile] = format_config.match.profile
          end
          # Pass YAML profile's extra match options (e.g., preserve_whitespace_elements)
          # that are stored in MatchConfig's resolver but not exposed via the
          # built-in MATCH_PROFILES system. These supplement the built-in profile.
          profile_opts = format_config.match.profile_options
          if profile_opts.any? && opts[:global_options].nil?
            opts[:global_options] = profile_opts
          elsif profile_opts.any?
            # Merge: global_options already set (e.g., per-call) takes precedence
            opts[:global_options] = opts[:global_options].merge(profile_opts)
          end
        end

        case comparison_format
        when :xml
          XmlComparator.equivalent?(obj1, obj2, opts)
        when :html, :html4, :html5
          HtmlComparator.equivalent?(obj1, obj2, opts)
        when :json
          JsonComparator.equivalent?(obj1, obj2, opts)
        when :yaml
          YamlComparator.equivalent?(obj1, obj2, opts)
        end
      end

      # Strip XML declarations and DOCTYPE preambles from an HTML string
      # so it can be safely parsed with Nokogiri::XML.fragment without
      # generating processing-instruction nodes.
      def strip_xml_preamble(str)
        str = str.sub(/\A\s*<\?xml[^?]*\?>\s*/m, "")
        if (i = str.index(/<!DOCTYPE/i))
          j = str.index(">", i)
          str = (str[0...i] + str[(j + 1)..]).strip if j
        end
        str
      end

      # Decode HTML named entities (&nbsp; etc.) to their numeric
      # character reference equivalents so that Nokogiri::XML.fragment
      # (which only understands the five XML entities) preserves them
      # as text nodes instead of silently dropping them.
      #
      # Uses Nokogiri's HTML4 parser to resolve the entities — the
      # text is extracted from a fragment so no structural tags are added.
      #
      # @param str [String] HTML string potentially containing named entities
      # @return [String] String with named entities replaced by characters
      def decode_html_entities(str)
        # Fast path: skip if no ampersands present
        return str unless str.include?("&")

        # Parse as HTML fragment to resolve named entities, then
        # re-serialize as text.  This converts &nbsp; → U+00A0, etc.
        doc = Nokogiri::HTML4.fragment(str)

        # Serialize back, preserving the resolved characters.
        # to_html re-encodes characters, so use inner_html which
        # keeps the character form.
        doc.inner_html

        # If the serialization re-encoded characters as entities,
        # that's fine — the XML parser understands numeric refs like &#160;
      end

      # Detect the format of an object (delegates to FormatDetector)
      #
      # @param obj [Object] Object to detect format of
      # @return [Symbol] Format type
      def detect_format(obj)
        FormatDetector.detect(obj)
      end

      # Detect the format of a string (delegates to FormatDetector)
      #
      # @param str [String] String to detect format of
      # @return [Symbol] Format type
      def detect_string_format(str)
        FormatDetector.detect_string(str)
      end

      # Parse HTML string into Nokogiri document (delegates to HtmlParser)
      #
      # @param content [String, Object] Content to parse
      # @param format [Symbol] HTML format (:html, :html4, :html5)
      # @return [Object] Parsed document
      def parse_html(content, format)
        HtmlParser.parse(content, format)
      end
    end
  end
end
