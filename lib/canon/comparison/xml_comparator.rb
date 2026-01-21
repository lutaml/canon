# frozen_string_literal: true

require_relative "../xml/c14n"
require_relative "markup_comparator"
require_relative "match_options"
require_relative "../diff/diff_node"
require_relative "../diff/diff_classifier"
require_relative "../diff/path_builder"
require_relative "../diff/node_serializer"
require_relative "comparison_result"
require_relative "../tree_diff"
require_relative "strategies/match_strategy_factory"
# XmlComparator modules
require_relative "xml_comparator/node_parser"
require_relative "xml_comparator/attribute_filter"
require_relative "xml_comparator/attribute_comparator"
require_relative "xml_comparator/namespace_comparator"
require_relative "xml_comparator/node_type_comparator"
require_relative "xml_comparator/child_comparison"
require_relative "xml_comparator/diff_node_builder"
# Whitespace sensitivity module
require_relative "whitespace_sensitivity"

module Canon
  module Comparison
    # XML comparison class
    # Handles comparison of XML nodes with various options
    #
    # Inherits shared comparison functionality from MarkupComparator.
    class XmlComparator < MarkupComparator
      # Default comparison options for XML
      DEFAULT_OPTS = {
        # Structural filtering options
        ignore_children: false,
        ignore_text_nodes: false,
        ignore_attr_content: [],
        ignore_attrs: [],
        ignore_attrs_by_name: [],
        ignore_nodes: [],

        # Output options
        verbose: false,
        diff_children: false,

        # Match system options
        match_profile: nil,
        match: nil,
        preprocessing: nil,
        global_profile: nil,
        global_options: nil,

        # Diff display options
        diff: nil,
      }.freeze

      class << self
        # Compare two XML nodes for equivalence
        #
        # @param n1 [String, Moxml::Node] First node
        # @param n2 [String, Moxml::Node] Second node
        # @param opts [Hash] Comparison options
        # @param child_opts [Hash] Options for child comparison
        # @return [Boolean, Array] true if equivalent, or array of diffs if
        #   verbose
        def equivalent?(n1, n2, opts = {}, child_opts = {})
          opts = DEFAULT_OPTS.merge(opts)

          # Resolve match options with format-specific defaults
          match_opts_hash = MatchOptions::Xml.resolve(
            format: :xml,
            match_profile: opts[:match_profile],
            match: opts[:match],
            preprocessing: opts[:preprocessing],
            global_profile: opts[:global_profile],
            global_options: opts[:global_options],
          )

          # Wrap in ResolvedMatchOptions for DiffClassifier
          match_opts = Canon::Comparison::ResolvedMatchOptions.new(
            match_opts_hash,
            format: :xml,
          )

          # Store resolved match options hash for use in comparison logic
          opts[:match_opts] = match_opts_hash

          # Use tree diff if semantic_diff option is enabled
          if match_opts.semantic_diff?
            return perform_semantic_tree_diff(n1, n2, opts, match_opts_hash)
          end

          # Create child_opts with resolved options
          child_opts = opts.merge(child_opts)

          # Determine if we should preserve whitespace during parsing
          # When structural_whitespace is :strict, preserve all whitespace-only text nodes
          preserve_whitespace = match_opts_hash[:structural_whitespace] == :strict

          # Parse nodes if they are strings, applying preprocessing if needed
          node1 = parse_node(n1, match_opts_hash[:preprocessing],
                             preserve_whitespace: preserve_whitespace)
          node2 = parse_node(n2, match_opts_hash[:preprocessing],
                             preserve_whitespace: preserve_whitespace)

          # Store original strings for line diff display (before preprocessing)
          original1 = if n1.is_a?(String)
                        n1
                      else
                        (n1.respond_to?(:to_xml) ? n1.to_xml : n1.to_s)
                      end
          original2 = if n2.is_a?(String)
                        n2
                      else
                        (n2.respond_to?(:to_xml) ? n2.to_xml : n2.to_s)
                      end

          differences = []
          diff_children = opts[:diff_children] || false

          result = compare_nodes(node1, node2, opts, child_opts,
                                 diff_children, differences)

          # Classify DiffNodes as normative/informative if we have verbose output
          if opts[:verbose] && !differences.empty?
            classifier = Canon::Diff::DiffClassifier.new(match_opts)
            classifier.classify_all(differences.select do |d|
              d.is_a?(Canon::Diff::DiffNode)
            end)
          end

          if opts[:verbose]
            # Serialize parsed nodes for consistent formatting
            # This ensures both sides formatted identically, showing only real differences
            preprocessed = [
              serialize_node(node1).gsub(/></, ">\n<"),
              serialize_node(node2).gsub(/></, ">\n<"),
            ]

            ComparisonResult.new(
              differences: differences,
              preprocessed_strings: preprocessed,
              original_strings: [original1, original2],
              format: :xml,
              match_options: match_opts_hash,
              algorithm: :dom,
            )
          elsif result != Comparison::EQUIVALENT && !differences.empty?
            # Non-verbose mode: check equivalence
            # If comparison found differences, classify them to determine if normative
            classifier = Canon::Diff::DiffClassifier.new(match_opts)
            classifier.classify_all(differences.select do |d|
              d.is_a?(Canon::Diff::DiffNode)
            end)
            # Equivalent if no normative differences (matches semantic algorithm)
            differences.none?(&:normative?)
          else
            # Either equivalent or no differences tracked
            result == Comparison::EQUIVALENT
          end
        end

        private

        # Perform semantic tree diff using SemanticTreeMatchStrategy
        #
        # @param n1 [String, Moxml::Node] First node
        # @param n2 [String, Moxml::Node] Second node
        # @param opts [Hash] Comparison options
        # @param match_opts_hash [Hash] Resolved match options
        # @return [Boolean, ComparisonResult] Result of tree diff comparison
        def perform_semantic_tree_diff(n1, n2, opts, match_opts_hash)
          # Store original strings for line diff display (before preprocessing)
          original1 = if n1.is_a?(String)
                        n1
                      else
                        (n1.respond_to?(:to_xml) ? n1.to_xml : n1.to_s)
                      end
          original2 = if n2.is_a?(String)
                        n2
                      else
                        (n2.respond_to?(:to_xml) ? n2.to_xml : n2.to_s)
                      end

          # Parse to Canon::Xml::Node (preserves preprocessing)
          node1 = parse_node(n1, match_opts_hash[:preprocessing])
          node2 = parse_node(n2, match_opts_hash[:preprocessing])

          # Create strategy using factory
          strategy = Strategies::MatchStrategyFactory.create(
            format: :xml,
            match_options: match_opts_hash,
          )

          # Pass Canon::Xml::Node directly - XML adapter now handles it
          differences = strategy.match(node1, node2)

          # Return based on verbose mode
          if opts[:verbose]
            # Get preprocessed strings for display
            preprocessed = strategy.preprocess_for_display(node1, node2)

            # Return ComparisonResult with strategy metadata
            ComparisonResult.new(
              differences: differences,
              preprocessed_strings: preprocessed,
              original_strings: [original1, original2],
              format: :xml,
              match_options: match_opts_hash.merge(strategy.metadata),
              algorithm: :semantic,
            )
          else
            # Simple boolean result - equivalent if no normative differences
            differences.none?(&:normative?)
          end
        end

        # Parse a node from string or return as-is
        # Applies preprocessing transformation before parsing if specified
        # Delegates to NodeParser module
        def parse_node(node, preprocessing = :none, preserve_whitespace: false)
          XmlComparatorHelpers::NodeParser.parse(node, preprocessing,
                                                 preserve_whitespace: preserve_whitespace)
        end

        # Main comparison dispatcher
        def compare_nodes(n1, n2, opts, child_opts, diff_children, differences)
          # Handle DocumentFragment nodes - compare their children instead
          if n1.is_a?(Nokogiri::XML::DocumentFragment) &&
              n2.is_a?(Nokogiri::XML::DocumentFragment)
            children1 = n1.children.to_a
            children2 = n2.children.to_a

            if children1.length != children2.length
              add_difference(n1, n2, Comparison::UNEQUAL_ELEMENTS,
                             Comparison::UNEQUAL_ELEMENTS, :text_content, opts,
                             differences)
              return Comparison::UNEQUAL_ELEMENTS
            elsif children1.empty?
              return Comparison::EQUIVALENT
            else
              # Compare each pair of children
              result = Comparison::EQUIVALENT
              children1.zip(children2).each do |child1, child2|
                child_result = compare_nodes(child1, child2, opts, child_opts,
                                             diff_children, differences)
                result = child_result unless child_result == Comparison::EQUIVALENT
              end
              return result
            end
          end

          # Check if nodes should be excluded
          return Comparison::EQUIVALENT if node_excluded?(n1, opts) &&
            node_excluded?(n2, opts)

          if node_excluded?(n1, opts) || node_excluded?(n2, opts)
            add_difference(n1, n2, Comparison::MISSING_NODE,
                           Comparison::MISSING_NODE, :text_content, opts, differences)
            return Comparison::MISSING_NODE
          end

          # Check node types match
          unless same_node_type?(n1, n2)
            add_difference(n1, n2, Comparison::UNEQUAL_NODES_TYPES,
                           Comparison::UNEQUAL_NODES_TYPES, :text_content, opts,
                           differences)
            return Comparison::UNEQUAL_NODES_TYPES
          end

          # Dispatch based on node type using NodeTypeComparator strategy
          XmlComparatorHelpers::NodeTypeComparator.compare(
            n1, n2, self, opts, child_opts, diff_children, differences
          )
        end

        # Public comparison methods - exposed for XmlNodeComparison module
        public

        # Compare two element nodes
        def compare_element_nodes(n1, n2, opts, child_opts, diff_children,
                                  differences)
          # Compare element names
          unless n1.name == n2.name
            add_difference(n1, n2, Comparison::UNEQUAL_ELEMENTS,
                           Comparison::UNEQUAL_ELEMENTS, :element_structure, opts,
                           differences)
            return Comparison::UNEQUAL_ELEMENTS
          end

          # Compare namespace URIs - elements with different namespaces are different elements
          ns1 = n1.respond_to?(:namespace_uri) ? n1.namespace_uri : nil
          ns2 = n2.respond_to?(:namespace_uri) ? n2.namespace_uri : nil

          unless ns1 == ns2
            # Create descriptive reason showing the actual namespace URIs
            ns1_display = ns1.nil? || ns1.empty? ? "(no namespace)" : ns1
            ns2_display = ns2.nil? || ns2.empty? ? "(no namespace)" : ns2

            diff_node = Canon::Diff::DiffNode.new(
              node1: n1,
              node2: n2,
              dimension: :namespace_uri,
              reason: "namespace '#{ns1_display}' vs '#{ns2_display}' on element '#{n1.name}'",
            )
            differences << diff_node if opts[:verbose]
            return Comparison::UNEQUAL_ELEMENTS
          end

          # Compare namespace declarations (xmlns and xmlns:* attributes)
          ns_result = compare_namespace_declarations(n1, n2, opts, differences)
          return ns_result unless ns_result == Comparison::EQUIVALENT

          # Compare attributes
          attr_result = compare_attribute_sets(n1, n2, opts, differences)
          return attr_result unless attr_result == Comparison::EQUIVALENT

          # Compare children if not ignored
          return Comparison::EQUIVALENT if opts[:ignore_children]

          compare_children(n1, n2, opts, child_opts, diff_children, differences)
        end

        # Compare attribute sets
        # Delegates to XmlComparatorHelpers::AttributeComparator
        def compare_attribute_sets(n1, n2, opts, differences)
          XmlComparatorHelpers::AttributeComparator.compare(n1, n2, opts,
                                                            differences)
        end

        # Compare text nodes
        def compare_text_nodes(n1, n2, opts, differences)
          return Comparison::EQUIVALENT if opts[:ignore_text_nodes]

          text1 = node_text(n1)
          text2 = node_text(n2)

          # Use match options
          match_opts = opts[:match_opts]
          behavior = match_opts[:text_content]

          # For HTML, check if text node is inside whitespace-preserving element
          # If so, always use strict comparison regardless of text_content setting
          sensitive_element = should_preserve_whitespace_strictly?(n1, n2, opts)
          if sensitive_element
            behavior = :strict
          end

          # Check if raw content differs
          raw_differs = text1 != text2

          # Check if matches according to behavior
          matches_per_behavior = MatchOptions.match_text?(text1, text2,
                                                          behavior)

          # Determine the correct dimension for this difference
          # - If text_content is :strict, ALL differences use :text_content dimension
          # - If text_content is :normalize, whitespace-only diffs could use :structural_whitespace
          #   but we keep :text_content to ensure correct classification behavior
          # - Otherwise use :text_content
          # However, if element is whitespace-sensitive (like <pre> in HTML),
          # always use :text_content dimension regardless of behavior
          #
          # NOTE: We keep the dimension as :text_content even for whitespace-only diffs
          # when text_content: :normalize. This ensures that the classification uses
          # the text_content behavior (:normalize) instead of structural_whitespace
          # behavior (:strict for XML), which would incorrectly mark the diff as normative.
          if sensitive_element
          # Whitespace-sensitive element: always use :text_content dimension
          else
            # Always use :text_content for text differences
            # This ensures correct classification based on text_content behavior
          end
          dimension = :text_content

          # Create DiffNode in verbose mode when raw content differs
          # This ensures informative diffs are created even for :ignore/:normalize
          if raw_differs && opts[:verbose]
            add_difference(n1, n2, Comparison::UNEQUAL_TEXT_CONTENTS,
                           Comparison::UNEQUAL_TEXT_CONTENTS, dimension,
                           opts, differences)
          end

          # Return based on whether behavior makes difference acceptable
          matches_per_behavior ? Comparison::EQUIVALENT : Comparison::UNEQUAL_TEXT_CONTENTS
        end

        # Check if whitespace should be preserved strictly for these text nodes
        # This applies to HTML elements like pre, code, textarea, script, style
        # and elements with xml:space="preserve" or in user-configured whitelist
        def should_preserve_whitespace_strictly?(n1, n2, opts)
          # Use WhitespaceSensitivity module to check if element is sensitive
          # Check both n1 and n2 - if either is in a sensitive element, preserve strictly
          if n1.respond_to?(:parent)
            sensitivity_opts = { match_opts: opts[:match_opts] }
            return true if WhitespaceSensitivity.element_sensitive?(n1,
                                                                    sensitivity_opts)
          end

          if n2.respond_to?(:parent)
            sensitivity_opts = { match_opts: opts[:match_opts] }
            return true if WhitespaceSensitivity.element_sensitive?(n2,
                                                                    sensitivity_opts)
          end

          false
        end

        # Check if a node is inside a whitespace-preserving element
        def in_preserve_element?(node, preserve_list)
          current = node.parent
          while current.respond_to?(:name)
            return true if preserve_list.include?(current.name.downcase)

            # Stop at document root
            break if current.is_a?(Nokogiri::XML::Document) ||
              current.is_a?(Nokogiri::HTML4::Document) ||
              current.is_a?(Nokogiri::HTML5::Document)

            current = current.parent if current.respond_to?(:parent)
            break unless current
          end
          false
        end

        # Compare comment nodes
        def compare_comment_nodes(n1, n2, opts, differences)
          match_opts = opts[:match_opts]
          behavior = match_opts[:comments]

          # Canon::Xml::Node CommentNode uses .value, Nokogiri uses .content
          content1 = node_text(n1)
          content2 = node_text(n2)

          # Check if content differs
          contents_differ = content1 != content2

          # Create DiffNode in verbose mode when content differs
          # This ensures informative diffs are created even for :ignore behavior
          if contents_differ && opts[:verbose]
            add_difference(n1, n2, Comparison::UNEQUAL_COMMENTS,
                           Comparison::UNEQUAL_COMMENTS, :comments, opts,
                           differences)
          end

          # Return based on behavior and whether content matches
          if behavior == :ignore || !contents_differ
            Comparison::EQUIVALENT
          else
            Comparison::UNEQUAL_COMMENTS
          end
        end

        # Compare processing instruction nodes
        def compare_processing_instruction_nodes(n1, n2, opts, differences)
          unless n1.target == n2.target
            add_difference(n1, n2, Comparison::UNEQUAL_NODES_TYPES,
                           Comparison::UNEQUAL_NODES_TYPES, :text_content, opts,
                           differences)
            return Comparison::UNEQUAL_NODES_TYPES
          end

          content1 = n1.content.to_s.strip
          content2 = n2.content.to_s.strip

          if content1 == content2
            Comparison::EQUIVALENT
          else
            add_difference(n1, n2, Comparison::UNEQUAL_TEXT_CONTENTS,
                           Comparison::UNEQUAL_TEXT_CONTENTS, :text_content,
                           opts, differences)
            Comparison::UNEQUAL_TEXT_CONTENTS
          end
        end

        # Compare document nodes
        def compare_document_nodes(n1, n2, opts, child_opts, diff_children,
                                   differences)
          # Compare root elements
          root1 = n1.root
          root2 = n2.root

          if root1.nil? || root2.nil?
            add_difference(n1, n2, Comparison::MISSING_NODE,
                           Comparison::MISSING_NODE, :text_content, opts, differences)
            return Comparison::MISSING_NODE
          end

          compare_nodes(root1, root2, opts, child_opts, diff_children,
                        differences)
        end

        # Compare children of two nodes using semantic matching
        #
        # Delegates to ChildComparison module which handles both ElementMatcher
        # (semantic matching) and simple positional comparison.
        def compare_children(n1, n2, opts, child_opts, diff_children,
differences)
          XmlComparatorHelpers::ChildComparison.compare(
            n1, n2, self, opts, child_opts, diff_children, differences
          )
        end

        # Extract element path for context (best effort)
        # @param node [Object] Node to extract path from
        # @return [Array<String>] Path components
        def extract_element_path(node)
          path = []
          current = node
          max_depth = 20
          depth = 0

          while current && depth < max_depth
            if current.respond_to?(:name) && current.name
              path.unshift(current.name)
            end

            break unless current.respond_to?(:parent)

            current = current.parent
            depth += 1

            # Stop at document root
            break if current.respond_to?(:root)
          end

          path
        end

        # Serialize a node to string for display
        #
        # @param node [Object, nil] Node to serialize
        # @return [String, nil] Serialized content
        def serialize_node(node)
          return nil if node.nil?

          Canon::Diff::NodeSerializer.serialize(node)
        end

        # Extract attributes from a node as a normalized hash
        #
        # @param node [Object, nil] Node to extract attributes from
        # @return [Hash, nil] Normalized attributes hash
        def extract_attributes(node)
          return nil if node.nil?

          Canon::Diff::NodeSerializer.extract_attributes(node)
        end

        # Build a human-readable reason for a difference
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param diff1 [String] Difference type for node1
        # @param diff2 [String] Difference type for node2
        # @param dimension [Symbol] The dimension of the difference
        # @return [String] Human-readable reason
        def build_difference_reason(node1, node2, diff1, diff2, dimension)
          # For deleted/inserted nodes, include namespace information if available
          if dimension == :text_content && (node1.nil? || node2.nil?)
            node = node1 || node2
            if node.respond_to?(:name) && node.respond_to?(:namespace_uri)
              ns = node.namespace_uri
              ns_info = if ns.nil? || ns.empty?
                          ""
                        else
                          " (namespace: #{ns})"
                        end
              return "element '#{node.name}'#{ns_info}: #{diff1} vs #{diff2}"
            end
          end

          # For attribute presence differences, show what attributes differ
          if dimension == :attribute_presence
            attrs1 = extract_attributes(node1)
            attrs2 = extract_attributes(node2)
            return build_attribute_diff_reason(attrs1, attrs2)
          end

          # For text content differences, show the actual text (truncated if needed)
          if dimension == :text_content
            text1 = extract_text_from_node(node1)
            text2 = extract_text_from_node(node2)
            return build_text_diff_reason(text1, text2)
          end

          "#{diff1} vs #{diff2}"
        end

        # Build a clear reason message for attribute presence differences
        #
        # @param attrs1 [Hash, nil] First node's attributes
        # @param attrs2 [Hash, nil] Second node's attributes
        # @return [String] Clear explanation of the attribute difference
        def build_attribute_diff_reason(attrs1, attrs2)
          return "#{attrs1&.keys&.size || 0} vs #{attrs2&.keys&.size || 0} attributes" unless attrs1 && attrs2

          require "set"
          keys1 = attrs1.keys.to_set
          keys2 = attrs2.keys.to_set

          only_in_first = keys1 - keys2
          only_in_second = keys2 - keys1
          common = keys1 & keys2

          # Check if values differ for common keys
          different_values = common.reject { |k| attrs1[k] == attrs2[k] }

          parts = []
          parts << "only in first: #{only_in_first.to_a.sort.join(', ')}" if only_in_first.any?
          parts << "only in second: #{only_in_second.to_a.sort.join(', ')}" if only_in_second.any?
          parts << "different values: #{different_values.sort.join(', ')}" if different_values.any?

          if parts.empty?
            "#{keys1.size} vs #{keys2.size} attributes (same names)"
          else
            parts.join("; ")
          end
        end

        # Extract text from a node for diff reason
        #
        # @param node [Object, nil] Node to extract text from
        # @return [String, nil] Text content or nil
        def extract_text_from_node(node)
          return nil if node.nil?

          # For Canon::Xml::Nodes::TextNode
          return node.value if node.respond_to?(:value) && node.is_a?(Canon::Xml::Nodes::TextNode)

          # For XML/HTML nodes with text_content method
          return node.text_content if node.respond_to?(:text_content)

          # For nodes with text method
          return node.text if node.respond_to?(:text)

          # For nodes with content method (Moxml::Text)
          return node.content if node.respond_to?(:content)

          # For nodes with value method (other types)
          return node.value if node.respond_to?(:value)

          # For simple text nodes or strings
          return node.to_s if node.is_a?(String)

          # For other node types, try to_s
          node.to_s
        rescue StandardError
          nil
        end

        # Build a clear reason message for text content differences
        #
        # @param text1 [String, nil] First text content
        # @param text2 [String, nil] Second text content
        # @return [String] Clear explanation of the text difference
        def build_text_diff_reason(text1, text2)
          # Handle nil cases
          return "missing vs '#{truncate_text(text2)}'" if text1.nil? && text2
          return "'#{truncate_text(text2)}' vs missing" if text1 && text2.nil?
          return "both missing" if text1.nil? && text2.nil?

          # Check if both are whitespace-only
          if whitespace_only?(text1) && whitespace_only?(text2)
            return "whitespace: #{describe_whitespace(text1)} vs #{describe_whitespace(text2)}"
          end

          # Show text with visible whitespace markers
          # Use escaped representations for clarity: \n for newline, \t for tab, · for spaces
          vis1 = visualize_whitespace(text1)
          vis2 = visualize_whitespace(text2)

          "Text: \"#{vis1}\" vs \"#{vis2}\""
        end

        # Check if text is only whitespace
        #
        # @param text [String] Text to check
        # @return [Boolean] true if whitespace-only
        def whitespace_only?(text)
          return false if text.nil?

          text.to_s.strip.empty?
        end

        # Make whitespace visible in text content
        # Uses the existing character visualization map from DiffFormatter (single source of truth)
        #
        # @param text [String] Text to visualize
        # @return [String] Text with visible whitespace markers
        def visualize_whitespace(text)
          return "" if text.nil?

          # Use the character map loader as the single source of truth
          viz_map = character_visualization_map

          # Replace each character with its visualization
          text.chars.map { |char| viz_map[char] || char }.join
        end

        # Get the character visualization map (lazy-loaded to avoid circular dependency)
        #
        # @return [Hash] Character to visualization symbol mapping
        def character_visualization_map
          @character_visualization_map ||= begin
            # Load the YAML file directly to avoid circular dependency
            require "yaml"
            lib_root = File.expand_path("../..", __dir__)
            yaml_path = File.join(lib_root, "canon/diff_formatter/character_map.yml")
            data = YAML.load_file(yaml_path)

            # Build visualization map from the YAML data
            visualization_map = {}
            data["characters"].each do |char_data|
              # Get the character from either unicode code point or character field
              char = if char_data["unicode"]
                       # Convert hex string to character
                       [char_data["unicode"].to_i(16)].pack("U")
                     else
                       # Use character field directly (handles \n, \t, etc.)
                       char_data["character"]
                     end

              vis = char_data["visualization"]
              visualization_map[char] = vis
            end

            visualization_map
          end
        end

        # Describe whitespace content in a readable way
        #
        # @param text [String] Whitespace text
        # @return [String] Description like "4 chars (2 newlines, 2 spaces)"
        def describe_whitespace(text)
          return "0 chars" if text.nil? || text.empty?

          char_count = text.length
          newline_count = text.count("\n")
          space_count = text.count(" ")
          tab_count = text.count("\t")

          parts = []
          parts << "#{newline_count} newlines" if newline_count.positive?
          parts << "#{space_count} spaces" if space_count.positive?
          parts << "#{tab_count} tabs" if tab_count.positive?

          description = parts.join(", ")
          "#{char_count} chars (#{description})"
        end

        # Truncate text for display in reason messages
        #
        # @param text [String] Text to truncate
        # @param max_length [Integer] Maximum length
        # @return [String] Truncated text
        def truncate_text(text, max_length = 40)
          return "" if text.nil?

          text = text.to_s
          return text if text.length <= max_length

          "#{text[0...max_length]}..."
        end

        # Compare namespace declarations (xmlns and xmlns:* attributes)
        # Delegates to XmlComparatorHelpers::NamespaceComparator
        def compare_namespace_declarations(n1, n2, opts, differences)
          XmlComparatorHelpers::NamespaceComparator.compare(n1, n2, opts,
                                                            differences)
        end
      end
    end
  end
end
