# frozen_string_literal: true

require "moxml"
require "nokogiri" if Canon::XmlBackend.nokogiri?

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
    autoload :BaseComparator, "canon/comparison/base_comparator"
    autoload :ChildRealignment, "canon/comparison/child_realignment"
    autoload :CompareProfile, "canon/comparison/compare_profile"
    autoload :ComparisonResult, "canon/comparison/comparison_result"
    autoload :DiffNodeBuilder, "canon/comparison/diff_node_builder"
    autoload :Dimensions, "canon/comparison/dimensions"
    autoload :FormatDetector, "canon/comparison/format_detector"
    autoload :HtmlComparator, "canon/comparison/html_comparator"
    autoload :HtmlCompareProfile, "canon/comparison/html_compare_profile"
    autoload :HtmlParser, "canon/comparison/html_parser"
    autoload :JsonComparator, "canon/comparison/json_comparator"
    autoload :JsonParser, "canon/comparison/json_parser"
    autoload :MarkupComparator, "canon/comparison/markup_comparator"
    autoload :MatchOptions, "canon/comparison/match_options"
    autoload :NodeInspector, "canon/comparison/node_inspector"
    autoload :Pipeline, "canon/comparison/pipeline"
    autoload :ProfileDefinition, "canon/comparison/profile_definition"
    autoload :RubyObjectComparator, "canon/comparison/ruby_object_comparator"
    autoload :Strategies, "canon/comparison/strategies"
    autoload :WhitespaceSensitivity, "canon/comparison/whitespace_sensitivity"
    autoload :XmlComparator, "canon/comparison/xml_comparator"
    autoload :XmlComparatorHelpers, "canon/comparison/xml_comparator_helpers"
    autoload :XmlNodeComparison, "canon/comparison/xml_node_comparison"
    autoload :XmlParser, "canon/comparison/xml_parser"
    autoload :YamlComparator, "canon/comparison/yaml_comparator"

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

    # Keys that OperationConverter and SemanticTreeMatchStrategy accept.
    # Used to strip diff-only keys (e.g. +max_node_count+) from the
    # fully-resolved match options hash before passing it to components
    # that expect match options only.
    MATCH_OPTION_KEYS = %i[
      match_profile
      match
      preprocessing
      text_content
      structural_whitespace
      attribute_presence
      attribute_order
      attribute_values
      element_position
      comments
      format
      similarity_threshold
      hash_matching
      similarity_matching
      propagation
      preserve_whitespace_elements
      collapse_whitespace_elements
      strip_whitespace_elements
      respect_xml_space
    ].freeze

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
        # Normalize: match: { semantic_diff: true } → diff_algorithm: :semantic
        if opts.dig(:match, :semantic_diff) || opts.dig(:match, :semantic_tree)
          opts = opts.merge(diff_algorithm: :semantic)
          opts = opts.merge(match: opts[:match].except(:semantic_diff,
                                                       :semantic_tree))
        end

        if %i[semantic semantic_tree].include?(opts[:diff_algorithm])
          return semantic_diff(obj1, obj2, opts)
        end

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

      # --- Internal methods (public for testability) ---

      # Perform semantic tree diff comparison
      def semantic_diff(obj1, obj2, opts = {})
        resolved = opts.dup
        format_hint = resolved[:format]

        # Capture original strings BEFORE any parsing/transformation.
        # These are used for display to preserve original formatting.
        original_str1, original_str2 = Pipeline.capture_originals(obj1, obj2)

        # Detect format for both objects.
        format1, format2 = Pipeline.detect_formats(obj1, obj2, format_hint)

        # Semantic tree doesn't support plain-string comparison.
        if format1 == :string
          if resolved[:verbose]
            return obj1.to_s == obj2.to_s ? [] : [:different]
          else
            return obj1.to_s == obj2.to_s
          end
        end

        # Semantic requires exact format match (no ruby_object cross-compat).
        Pipeline.validate_compatible!(format1, format2, strict: true)

        # Merge global config-sourced profile and options into opts.
        resolved = Pipeline.resolve_config(format1, resolved)

        # Resolve match options for the format.
        match_opts_hash = resolve_match_options(format1, resolved)

        # Also read diff options from config (e.g., max_node_count for
        # large documents). Independent of match options; passed to
        # TreeDiffIntegrator.
        if !match_opts_hash[:max_node_count] &&
            Pipeline::CONFIG_BACKED_FORMATS.include?(format1)
          diff_max_node = Canon::Config.instance.public_send(format1).diff.max_node_count
          if diff_max_node > 10_000
            match_opts_hash[:max_node_count] = diff_max_node
          end
        end

        # Delegate parsing to comparators (reuses existing preprocessing).
        doc1, doc2 = Pipeline.parse_pair(obj1, obj2, format1, match_opts_hash)

        # Normalize format for TreeDiff (html4/html5 -> html).
        tree_diff_format = normalize_format_for_tree_diff(format1)

        # Create TreeDiff integrator for the format.
        # CRITICAL: Use match_opts_hash (resolved options with profile)
        # not opts[:match].
        integrator = Canon::TreeDiff::TreeDiffIntegrator.new(
          format: tree_diff_format,
          options: match_opts_hash,
        )

        # Perform diff.
        tree_diff_result = integrator.diff(doc1, doc2)

        # Extract only match-related keys for OperationConverter and
        # SemanticTreeMatchStrategy. These components expect match
        # options, not diff options like max_node_count.
        match_options_only = match_opts_hash.slice(*MATCH_OPTION_KEYS)

        # Convert operations to DiffNodes for unified pipeline.
        converter = Canon::TreeDiff::OperationConverter.new(
          format: format1,
          match_options: match_options_only,
        )
        diff_nodes = converter.convert(tree_diff_result[:operations])

        # CRITICAL: Use strategy's preprocess_for_display to ensure proper
        # line-breaking. This matches DOM diff preprocessing pattern
        # (xml_comparator.rb:106-109).
        strategy = Comparison::Strategies::SemanticTreeMatchStrategy.new(
          format: format1, match_options: match_options_only,
        )
        str1, str2 = strategy.preprocess_for_display(doc1, doc2)

        # Store tree diff data in match_options for access via result.
        enhanced_match_options = match_opts_hash.merge(
          tree_diff_operations: tree_diff_result[:operations],
          tree_diff_statistics: tree_diff_result[:statistics],
          tree_diff_matching: tree_diff_result[:matching],
        )

        # Create ComparisonResult for unified handling.
        result = Canon::Comparison::ComparisonResult.new(
          differences: diff_nodes,
          preprocessed_strings: [str1, str2],
          original_strings: [original_str1, original_str2],
          format: format1,
          html_version: %i[html4 html5].include?(format1) ? format1 : nil,
          match_options: enhanced_match_options,
          algorithm: :semantic,
        )

        # Return boolean or ComparisonResult based on verbose flag.
        if resolved[:verbose]
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
        Dimensions::Registry.for(format).names
      end

      # Helper to extract format from opts for validation
      #
      # @param opts [Hash] User options
      # @return [Symbol] Format type or :xml as default
      def format_from_opts(opts)
        opts[:format] || :xml
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
        resolved = opts.dup
        format_hint = resolved[:format]

        # Detect formats (with explicit hint) and pre-parse HTML strings
        # through Nokogiri::HTML5 so html4 and html5 share HTML's
        # whitespace-sensitivity semantics (issue #118).  Pre-parsing
        # also lets us snapshot the original strings before the HTML
        # fragment parser mutates the DOM.
        format1, format2 = Pipeline.detect_formats(obj1, obj2, format_hint)
        if %i[html html4 html5].include?(format_hint) && obj1.is_a?(String) &&
            obj2.is_a?(String)
          resolved[:_original_str1] = obj1
          resolved[:_original_str2] = obj2
          obj1, obj2 = Pipeline.preparse_html_pair(obj1, obj2)
        end

        # Handle string format (plain text comparison).
        if format1 == :string
          if resolved[:verbose]
            return obj1.to_s == obj2.to_s ? [] : [:different]
          else
            return obj1.to_s == obj2.to_s
          end
        end

        # DOM allows ruby_object <-> json/yaml cross-compatibility.
        Pipeline.validate_compatible!(format1, format2, strict: false)

        # Normalize comparison format (ruby_object -> json by default).
        comparison_format = normalize_comparison_format(format1, format2)

        # Merge global config-sourced profile and options into opts.
        resolved = Pipeline.resolve_config(comparison_format, resolved)

        case comparison_format
        when :xml
          XmlComparator.equivalent?(obj1, obj2, resolved)
        when :html, :html4, :html5
          HtmlComparator.equivalent?(obj1, obj2, resolved)
        when :json
          JsonComparator.equivalent?(obj1, obj2, resolved)
        when :yaml
          YamlComparator.equivalent?(obj1, obj2, resolved)
        end
      end

      # Pick the format used for actual comparison.
      #
      # When comparing ruby_object with json/yaml, use the json/yaml side
      # so both inputs parse to the same Ruby structure.  When both sides
      # are ruby_object (or the other side is not json/yaml), default to
      # JSON since ruby_object has no comparator of its own.
      #
      # @param format1 [Symbol]
      # @param format2 [Symbol]
      # @return [Symbol]
      def normalize_comparison_format(format1, format2)
        return format2 if format1 == :ruby_object &&
          %i[json yaml].include?(format2)
        return :json if format1 == :ruby_object

        format1
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
