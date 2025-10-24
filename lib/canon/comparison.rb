# frozen_string_literal: true

require "moxml"
require "nokogiri"
require_relative "xml/whitespace_normalizer"
require_relative "comparison/xml_comparator"
require_relative "comparison/html_comparator"
require_relative "comparison/json_comparator"
require_relative "comparison/yaml_comparator"
require_relative "comparison/combined_comparison_result"
require_relative "diff/diff_node_mapper"
require_relative "diff/diff_line"
require_relative "diff/diff_block_builder"
require_relative "diff/diff_context_builder"
require_relative "diff/diff_report_builder"

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
  # - collapse_whitespace: Normalize whitespace in text (default: true)
  # - ignore_attr_order: Ignore attribute/key ordering (default: true)
  # - ignore_comments: Skip comment nodes (default: true)
  # - ignore_text_nodes: Skip all text content (default: false)
  # - ignore_children: Skip child nodes (default: false)
  # - verbose: Return detailed diff array (default: false)
  #
  # == Usage Examples
  #
  #   # XML comparison
  #   Canon::Comparison.equivalent?(xml1, xml2)
  #   Canon::Comparison.equivalent?(xml1, xml2, verbose: true)
  #
  #   # HTML comparison
  #   Canon::Comparison.equivalent?(html1, html2, ignore_comments: true)
  #
  #   # JSON comparison
  #   Canon::Comparison.equivalent?(json1, json2)
  #   Canon::Comparison.equivalent?(hash1, hash2)  # Pre-parsed objects
  #
  #   # With detailed output
  #   diffs = Canon::Comparison.equivalent?(doc1, doc2, verbose: true)
  #   diffs.each { |diff| puts diff.inspect }
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
    UNEQUAL_ARRAY_LENGTHS = 12
    UNEQUAL_ARRAY_ELEMENTS = 13
    UNEQUAL_TYPES = 14
    UNEQUAL_PRIMITIVES = 15

    class << self
      # Auto-detect format and compare two objects
      #
      # @param obj1 [Object] First object to compare
      # @param obj2 [Object] Second object to compare
      # @param opts [Hash] Comparison options
      #   - :format - Format hint (:xml, :html, :html4, :html5, :json, :yaml, :string)
      #   - :diff_algorithm - Algorithm to use (:dom or :semantic)
      #   - :show_compare - Show both algorithms (boolean, default: false)
      # @return [Boolean, Array] true if equivalent, or array of diffs if verbose
      def equivalent?(obj1, obj2, opts = {})
        # Check if show_compare is enabled (orthogonal to algorithm choice)
        if opts[:show_compare]
          # Run both algorithms, use :diff_algorithm (or :dom default) for decision
          decision_algorithm = opts[:diff_algorithm] || :dom
          return both_algorithms(obj1, obj2, opts.merge(decision_algorithm: decision_algorithm))
        end

        # Legacy support: :both algorithm redirects to show_compare
        if opts[:diff_algorithm] == :both
          decision_algorithm = :dom # Default to DOM for decision when :both is used
          return both_algorithms(obj1, obj2, opts.merge(decision_algorithm: decision_algorithm))
        end

        # Check if semantic tree diff is requested
        if opts[:diff_algorithm] == :semantic
          return semantic_diff(obj1, obj2, opts)
        end

        # Otherwise use DOM-based comparison (default)
        dom_diff(obj1, obj2, opts)
      end

      private

      # Run both DOM and Tree algorithms sequentially
      def both_algorithms(obj1, obj2, opts = {})
        # Extract decision algorithm (defaults to :dom)
        decision_algorithm = opts[:decision_algorithm] || :dom

        # Run DOM diff
        dom_opts = opts.merge(diff_algorithm: :dom)
        dom_result = dom_diff(obj1, obj2, dom_opts)

        # Run Tree diff
        tree_opts = opts.merge(diff_algorithm: :semantic)
        tree_result = semantic_diff(obj1, obj2, tree_opts)

        # If verbose, return combined result with decision algorithm
        if opts[:verbose]
          CombinedComparisonResult.new(dom_result, tree_result, decision_algorithm: decision_algorithm)
        else
          # For non-verbose, return result from the decision algorithm
          case decision_algorithm
          when :semantic
            tree_result
          else # :dom (default)
            dom_result
          end
        end
      end

      # Perform semantic tree diff comparison
      def semantic_diff(obj1, obj2, opts = {})
        require_relative "tree_diff"

        # Detect format for both objects
        format1 = opts[:format] || detect_format(obj1)
        format2 = opts[:format] || detect_format(obj2)

        # Ensure formats match
        unless format1 == format2
          raise Canon::CompareFormatMismatchError.new(format1, format2)
        end

        # Resolve match options for the format
        match_opts_hash = resolve_match_options(format1, opts)

        # Delegate parsing to comparators (reuses existing preprocessing logic)
        doc1, doc2 = parse_with_comparator(obj1, obj2, format1, match_opts_hash)

        # Normalize format for TreeDiff (html4/html5 -> html)
        tree_diff_format = normalize_format_for_tree_diff(format1)

        # Create TreeDiff integrator for the format
        # CRITICAL: Use match_opts_hash (resolved options with profile) not opts[:match]
        integrator = Canon::TreeDiff::TreeDiffIntegrator.new(
          format: tree_diff_format,
          options: match_opts_hash
        )

        # Perform diff
        tree_diff_result = integrator.diff(doc1, doc2)

        # Convert operations to DiffNodes for unified pipeline
        # CRITICAL: Use match_opts_hash (resolved options with profile) not opts[:match]
        converter = Canon::TreeDiff::OperationConverter.new(
          format: format1,
          match_options: match_opts_hash
        )
        diff_nodes = converter.convert(tree_diff_result[:operations])

        # CRITICAL: Use strategy's preprocess_for_display to ensure proper line-breaking
        # This matches DOM diff preprocessing pattern (xml_comparator.rb:106-109)
        require_relative "comparison/strategies/semantic_tree_match_strategy"
        strategy = Comparison::Strategies::SemanticTreeMatchStrategy.new(format1, match_opts_hash)
        str1, str2 = strategy.preprocess_for_display(doc1, doc2)

        # Store tree diff data in match_options for access via result
        enhanced_match_options = match_opts_hash.merge(
          tree_diff_operations: tree_diff_result[:operations],
          tree_diff_statistics: tree_diff_result[:statistics],
          tree_diff_matching: tree_diff_result[:matching]
        )

        # Create ComparisonResult for unified handling
        result = Canon::Comparison::ComparisonResult.new(
          differences: diff_nodes,
          preprocessed_strings: [str1, str2],
          format: format1,
          html_version: (format1 == :html4 || format1 == :html5) ? format1 : nil,
          match_options: enhanced_match_options,
          algorithm: :semantic
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
        case format
        when :xml, :html, :html4, :html5
          MatchOptions::Xml.resolve(
            format: format,
            match_profile: opts[:match_profile],
            match: opts[:match],
            preprocessing: opts[:preprocessing],
            global_profile: opts[:global_profile],
            global_options: opts[:global_options]
          )
        when :json
          MatchOptions::Json.resolve(
            format: format,
            match_profile: opts[:match_profile],
            match: opts[:match],
            preprocessing: opts[:preprocessing],
            global_profile: opts[:global_profile],
            global_options: opts[:global_options]
          )
        when :yaml
          MatchOptions::Yaml.resolve(
            format: format,
            match_profile: opts[:match_profile],
            match: opts[:match],
            preprocessing: opts[:preprocessing],
            global_profile: opts[:global_profile],
            global_options: opts[:global_options]
          )
        else
          opts[:match] || {}
        end
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
          # Delegate to XmlComparator's parse_node
          doc1 = XmlComparator.send(:parse_node, obj1, preprocessing)
          doc2 = XmlComparator.send(:parse_node, obj2, preprocessing)
          # Convert Moxml to Nokogiri for TreeDiff
          [
            XmlComparator.send(:convert_to_nokogiri, doc1),
            XmlComparator.send(:convert_to_nokogiri, doc2)
          ]
        when :html, :html4, :html5
          # Delegate to HtmlComparator's parse_node
          [
            HtmlComparator.send(:parse_node, obj1, preprocessing, match_opts_hash),
            HtmlComparator.send(:parse_node, obj2, preprocessing, match_opts_hash)
          ]
        when :json
          # Delegate to JsonComparator's parse_json
          [
            JsonComparator.send(:parse_json, obj1),
            JsonComparator.send(:parse_json, obj2)
          ]
        when :yaml
          # Delegate to YamlComparator's parse_yaml
          [
            YamlComparator.send(:parse_yaml, obj1),
            YamlComparator.send(:parse_yaml, obj2)
          ]
        else
          [obj1, obj2]
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

      # Serialize document back to string
      def serialize_document(doc, format)
        case format
        when :xml, :html, :html4, :html5
          doc.respond_to?(:to_html) ? doc.to_html : doc.to_xml
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
            obj1 = parse_html(obj1, opts[:format]) if obj1.is_a?(String)
            obj2 = parse_html(obj2, opts[:format]) if obj2.is_a?(String)
            # Normalize html4/html5 to html for comparison
            format1 = format2 = :html
          end
        else
          format1 = detect_format(obj1)
          format2 = detect_format(obj2)
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

        case comparison_format
        when :xml
          XmlComparator.equivalent?(obj1, obj2, opts)
        when :html
          HtmlComparator.equivalent?(obj1, obj2, opts)
        when :json
          JsonComparator.equivalent?(obj1, obj2, opts)
        when :yaml
          YamlComparator.equivalent?(obj1, obj2, opts)
        end
      end

      # Parse HTML string into Nokogiri document
      #
      # @param content [String, Object] Content to parse (returns as-is if not a string)
      # @param format [Symbol] HTML format (:html, :html4, :html5)
      # @return [Nokogiri::HTML::Document, Nokogiri::HTML5::Document, Nokogiri::HTML::DocumentFragment, Object]
      def parse_html(content, _format)
        return content unless content.is_a?(String)
        return content if content.is_a?(Nokogiri::HTML::Document) ||
          content.is_a?(Nokogiri::HTML5::Document) ||
          content.is_a?(Nokogiri::XML::Document) ||
          content.is_a?(Nokogiri::HTML::DocumentFragment) ||
          content.is_a?(Nokogiri::HTML5::DocumentFragment) ||
          content.is_a?(Nokogiri::XML::DocumentFragment)

        # Let HtmlComparator's parse_node handle parsing with preprocessing
        # For now, just return the string and let it be parsed by HtmlComparator
        content
      rescue StandardError
        content
      end

      # Detect the format of an object
      #
      # @param obj [Object] Object to detect format of
      # @return [Symbol] Format type
      def detect_format(obj)
        case obj
        when Moxml::Node, Moxml::Document
          :xml
        when Nokogiri::HTML::DocumentFragment, Nokogiri::HTML5::DocumentFragment
          # HTML DocumentFragments
          :html
        when Nokogiri::XML::DocumentFragment
          # XML DocumentFragments - check if it's actually HTML
          obj.document&.html? ? :html : :xml
        when Nokogiri::XML::Document, Nokogiri::XML::Node
          # Check if it's HTML by looking at the document type
          obj.html? ? :html : :xml
        when Nokogiri::HTML::Document, Nokogiri::HTML5::Document
          :html
        when String
          detect_string_format(obj)
        when Hash, Array
          # Raw Ruby objects (from parsed JSON/YAML)
          :ruby_object
        else
          raise Canon::Error, "Unknown format for object: #{obj.class}"
        end
      end

      # Detect the format of a string
      #
      # @param str [String] String to detect format of
      # @return [Symbol] Format type
      def detect_string_format(str)
        trimmed = str.strip

        # YAML indicators
        return :yaml if trimmed.start_with?("---")
        return :yaml if trimmed.match?(/^[a-zA-Z_]\w*:\s/)

        # JSON indicators
        return :json if trimmed.start_with?("{", "[")

        # HTML indicators
        return :html if trimmed.start_with?("<!DOCTYPE html", "<html", "<HTML")

        # XML indicators - must start with < and end with >
        return :xml if trimmed.start_with?("<") && trimmed.end_with?(">")

        # Default to plain string for everything else
        :string
      end
    end
  end
end
