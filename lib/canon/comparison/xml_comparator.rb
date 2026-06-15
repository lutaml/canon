# frozen_string_literal: true

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
          # FAST PATH: Object identity - same object is always equivalent
          if n1.equal?(n2)
            return build_trivial_equivalent_result(n1, n2, opts)
          end

          # FAST PATH: String content equality - identical strings are equivalent
          # Skip in verbose mode since caller may need full metadata (e.g. tree_diff statistics)
          if !opts[:verbose] && n1.is_a?(String) && n2.is_a?(String) && n1 == n2
            return true
          end

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

          # Create child_opts with resolved options
          child_opts = opts.merge(child_opts)

          # Determine if we should preserve whitespace during parsing.
          # Only structural_whitespace: :strict forces whitespace-only text
          # nodes to survive parsing.  whitespace_type is about distinguishing
          # Unicode whitespace *types* in surviving text-node content, and
          # does NOT require indent text nodes to be kept — libxml's NOBLANKS
          # only strips pure-ASCII whitespace-only nodes, so NBSP-only nodes
          # survive regardless.  Coupling whitespace_type: :strict to
          # parsing-time preservation made pretty-printed fixtures produce
          # spurious element-position diffs (issue #112).
          preserve_whitespace = match_opts_hash[:structural_whitespace] == :strict

          # Parse nodes if they are strings, applying preprocessing if needed
          node1 = parse_node(n1, match_opts_hash[:preprocessing],
                             preserve_whitespace: preserve_whitespace)
          node2 = parse_node(n2, match_opts_hash[:preprocessing],
                             preserve_whitespace: preserve_whitespace)

          # Store original strings for line diff display (before preprocessing)
          original1 = n1.is_a?(String) ? n1 : serialize_node(n1)
          original2 = n2.is_a?(String) ? n2 : serialize_node(n2)

          differences = []
          diff_children = opts[:diff_children] || false

          result = compare_nodes(node1, node2, opts, child_opts,
                                 diff_children, differences)

          # Classify DiffNodes as normative/informative if we have verbose output
          if opts[:verbose] && !differences.empty?
            classifier = Canon::Diff::DiffClassifier.new(match_opts)
            classifier.classify_all(differences.grep(Canon::Diff::DiffNode))
          end

          if opts[:verbose]
            # Serialize parsed nodes for consistent formatting
            # This ensures both sides formatted identically, showing only real differences
            preprocessed = [
              serialize_node(node1).gsub("><", ">\n<"),
              serialize_node(node2).gsub("><", ">\n<"),
            ]

            ComparisonResult.new(
              differences: differences,
              preprocessed_strings: preprocessed,
              original_strings: [original1, original2],
              format: :xml,
              match_options: match_opts_hash,
              algorithm: :dom,
              parse_errors_expected: Comparison.parse_errors_for(node1),
              parse_errors_received: Comparison.parse_errors_for(node2),
            )
          elsif result != Comparison::EQUIVALENT && !differences.empty?
            # Non-verbose mode: check equivalence
            # If comparison found differences, classify them to determine if normative
            classifier = Canon::Diff::DiffClassifier.new(match_opts)
            classifier.classify_all(differences.grep(Canon::Diff::DiffNode))
            # Equivalent if no normative differences (matches semantic algorithm)
            differences.none?(&:normative?)
          else
            # Either equivalent or no differences tracked
            result == Comparison::EQUIVALENT
          end
        end

        private

        # Parse a node from string or return as-is
        # Applies preprocessing transformation before parsing if specified
        # Delegates to NodeParser module
        def parse_node(node, preprocessing = :none, preserve_whitespace: false)
          XmlComparatorHelpers::NodeParser.parse(node, preprocessing,
                                                 preserve_whitespace: preserve_whitespace)
        end

        # Build result for trivially equivalent inputs (same object or identical strings)
        #
        # Returns plain `true` in non-verbose mode, or a ComparisonResult in verbose mode.
        #
        # @param n1 [Object] First input
        # @param n2 [Object] Second input
        # @param opts [Hash] Raw options (before merge with DEFAULT_OPTS)
        # @return [Boolean, ComparisonResult]
        def build_trivial_equivalent_result(n1, n2, opts)
          return true unless opts[:verbose]

          # Parse nodes for verbose display
          preserve_whitespace = true
          node1 = parse_node(n1, :none,
                             preserve_whitespace: preserve_whitespace)
          node2 = parse_node(n2, :none,
                             preserve_whitespace: preserve_whitespace)
          preprocessed = [
            serialize_node(node1).gsub("><", ">\n<"),
            serialize_node(node2).gsub("><", ">\n<"),
          ]
          original1 = n1.is_a?(String) ? n1 : serialize_node(n1)
          original2 = n2.is_a?(String) ? n2 : serialize_node(n2)

          ComparisonResult.new(
            differences: [],
            preprocessed_strings: preprocessed,
            original_strings: [original1, original2],
            format: :xml,
            match_options: {},
            algorithm: :dom,
          )
        end

        public

        # Public parsing API for external callers
        def parse(node, preprocessing = :none, preserve_whitespace: false)
          parse_node(node, preprocessing,
                     preserve_whitespace: preserve_whitespace)
        end

        # Main comparison dispatcher
        def compare_nodes(n1, n2, opts, child_opts, diff_children, differences)
          # FAST PATH: Object identity - same object is always equivalent
          return Comparison::EQUIVALENT if n1.equal?(n2)

          # Handle DocumentFragment nodes - compare their children instead
          if Canon::XmlParsing.document_fragment?(n1) &&
              Canon::XmlParsing.document_fragment?(n2)
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

          # Handle comment vs non-comment comparisons specially
          # Create :comments dimension differences instead of UNEQUAL_NODES_TYPES
          if comment_vs_non_comment_comparison?(n1, n2)
            match_opts = opts[:match_opts]
            comment_behavior = match_opts ? match_opts[:comments] : nil

            # Create a :comments dimension difference
            # The difference will be marked as normative or not based on the profile
            add_difference(n1, n2, Comparison::MISSING_NODE,
                           Comparison::MISSING_NODE, :comments, opts,
                           differences)

            # Return EQUIVALENT if comments are ignored, otherwise return UNEQUAL
            if comment_behavior == :ignore
              Comparison::EQUIVALENT
            else
              Comparison::UNEQUAL_COMMENTS
            end
          elsif !same_node_type?(n1, n2)
            # Check node types match for non-comment comparisons
            add_difference(n1, n2, Comparison::UNEQUAL_NODES_TYPES,
                           Comparison::UNEQUAL_NODES_TYPES, :text_content, opts,
                           differences)
            Comparison::UNEQUAL_NODES_TYPES
          else
            # Dispatch based on node type using NodeTypeComparator strategy
            XmlComparatorHelpers::NodeTypeComparator.compare(
              n1, n2, self, opts, child_opts, diff_children, differences
            )
          end
        end

        # Check if this is a comment vs non-comment comparison
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @return [Boolean] true if exactly one node is a comment
        def comment_vs_non_comment_comparison?(node1, node2)
          node1_comment = XmlNodeComparison
            .comment_node?(node1, check_children: true)
          node2_comment = XmlNodeComparison
            .comment_node?(node2, check_children: true)

          # XOR: exactly one is a comment
          node1_comment ^ node2_comment
        end

        # Public comparison methods - exposed for XmlNodeComparison module

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
          ns1 = Canon::XmlParsing.namespace_uri(n1)
          ns2 = Canon::XmlParsing.namespace_uri(n2)

          unless ns1 == ns2
            diff_node = Canon::Comparison::DiffNodeBuilder.build(
              node1: n1,
              node2: n2,
              diff1: Comparison::UNEQUAL_ELEMENTS,
              diff2: Comparison::UNEQUAL_ELEMENTS,
              dimension: :namespace_uri,
            )
            differences << diff_node if opts[:verbose]
            return Comparison::UNEQUAL_ELEMENTS
          end

          # Track the worst result across namespace, attribute, and children
          # comparisons. Do NOT return early on attribute/namespace mismatches —
          # children must still be compared so structural differences in the
          # subtree are reported. Early returns caused the comparator to skip
          # entire subtrees when a root or intermediate element had different
          # attributes, missing all nested structural changes.
          worst_result = Comparison::EQUIVALENT

          # Compare namespace declarations (xmlns and xmlns:* attributes)
          ns_result = compare_namespace_declarations(n1, n2, opts, differences)
          worst_result = ns_result unless ns_result == Comparison::EQUIVALENT

          # Compare attributes
          attr_result = compare_attribute_sets(n1, n2, opts, differences)
          worst_result = attr_result unless attr_result == Comparison::EQUIVALENT

          # Compare children if not ignored
          unless opts[:ignore_children]
            child_result = compare_children(n1, n2, opts, child_opts,
                                            diff_children, differences)
            worst_result = child_result unless child_result == Comparison::EQUIVALENT
          end

          worst_result
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
          whitespace_type = match_opts[:whitespace_type] || :strict
          matches_per_behavior = MatchOptions.match_text?(text1, text2,
                                                          behavior,
                                                          whitespace_type: whitespace_type)

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
        # and elements with xml:space="preserve" or in user-configured preserve list.
        #
        # IMPORTANT: This returns true ONLY for :preserve classification.
        # For :collapse classification, whitespace differences ARE acceptable
        # (they are detected as formatting-only by DiffClassifier).
        def should_preserve_whitespace_strictly?(n1, n2, opts)
          # Check both n1 and n2 - if either is in a preserve whitespace element, preserve strictly
          [n1, n2].each do |node|
            next unless Canon::XmlParsing.xml_node?(node) || node.is_a?(Canon::Xml::Node)

            parent = node.parent
            next unless parent

            classification = WhitespaceSensitivity.classify_element(parent,
                                                                    opts[:match_opts])
            return true if classification == :preserve
          end

          false
        end

        # Check if a node is inside a whitespace-preserving element
        def in_preserve_element?(node, preserve_list)
          current = node.parent
          while Canon::XmlParsing.xml_node?(current) || current.is_a?(Canon::Xml::Node)
            return true if preserve_list.include?(current.name.downcase)

            break if Canon::XmlParsing.document?(current)

            current = current.parent
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

          content1 = Canon::XmlParsing.xml_node?(n1) ? n1.content.to_s.strip : ""
          content2 = Canon::XmlParsing.xml_node?(n2) ? n2.content.to_s.strip : ""

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
            n = if current.is_a?(Canon::Xml::Node)
                  current.name
                elsif Canon::XmlParsing.xml_node?(current)
                  current.name
                end
            path.unshift(n) if n

            break unless Canon::XmlParsing.xml_node?(current) || current.is_a?(Canon::Xml::Node)

            current = current.parent
            depth += 1

            break if Canon::XmlParsing.document?(current)
          end

          path
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
