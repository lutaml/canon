# frozen_string_literal: true

require_relative "formatting_detector"
require_relative "xml_serialization_formatter"
require_relative "../comparison/compare_profile"
require_relative "../comparison/whitespace_sensitivity"

module Canon
  module Diff
    # Classifies DiffNodes as normative (affects equivalence) or informative (doesn't affect equivalence)
    # based on the match options in effect
    #
    # Classification hierarchy (three distinct kinds of differences):
    # 1. Serialization formatting: XML syntax differences (always non-normative)
    # 2. Content formatting: Whitespace differences in content (non-normative when normalized)
    # 3. Normative: Semantic content differences (affect equivalence)
    class DiffClassifier
      attr_reader :match_options, :profile

      # @param match_options [Canon::Comparison::ResolvedMatchOptions] The match options
      def initialize(match_options)
        @match_options = match_options
        # Use the compare_profile from ResolvedMatchOptions if available (e.g., HtmlCompareProfile)
        # Otherwise create a base CompareProfile
        @profile = if match_options.respond_to?(:compare_profile) && match_options.compare_profile
                     match_options.compare_profile
                   else
                     Canon::Comparison::CompareProfile.new(match_options)
                   end
      end

      # Classify a single DiffNode as normative or informative
      # Hierarchy: formatting-only < informative < normative
      # CompareProfile determines base classification, XmlSerializationFormatter handles serialization formatting
      # @param diff_node [DiffNode] The diff node to classify
      # @return [DiffNode] The same diff node with normative/formatting attributes set
      def classify(diff_node)
        # FIRST: Check for XML serialization-level formatting differences
        # These are ALWAYS non-normative (formatting-only) regardless of match options
        # Examples: self-closing tags (<tag/>) vs explicit closing tags (<tag></tag>)
        #
        # EXCEPTION: If the text node is inside a whitespace-sensitive element
        # (:preserve or :collapse), don't dismiss as serialization formatting
        # because whitespace presence is meaningful in those elements.
        if !inside_whitespace_sensitive_element?(diff_node) &&
            XmlSerializationFormatter.serialization_formatting?(diff_node)
          diff_node.formatting = true
          diff_node.normative = false
          return diff_node
        end

        # SECOND: Handle content-level formatting for text_content with :normalize behavior
        # When text_content is :normalize and the difference is formatting-only,
        # it should be marked as non-normative (informative)
        # This ensures that verbose and non-verbose modes give consistent results
        #
        # EXCEPTION: If the text node is inside a PRESERVE whitespace element
        # (like <pre>, <code>, <textarea> in HTML), don't apply formatting detection
        # because whitespace should be preserved exactly in these elements.
        # Note: COLLAPSE elements like <p> DO get formatting detection because
        # their whitespace IS normalized (differences are formatting-only).
        #
        # This check must come BEFORE normative_dimension? is called,
        # because normative_dimension? returns true for text_content: :normalize
        # (since the dimension affects equivalence), which would prevent formatting
        # detection from being applied.
        if diff_node.dimension == :text_content &&
            profile.send(:behavior_for, :text_content) == :normalize &&
            !inside_preserve_element?(diff_node) &&
            formatting_only_diff?(diff_node)
          diff_node.formatting = true
          diff_node.normative = false
          return diff_node
        end

        # :whitespace_adjacency is a report-only re-label of an
        # asymmetric whitespace mismatch emitted by ChildRealignment's
        # two-cursor walk.  Equivalence behaviour is unchanged — the
        # underlying mismatch is normative regardless of match options.
        if diff_node.dimension == :whitespace_adjacency
          diff_node.formatting = false
          diff_node.normative = true
          return diff_node
        end

        # :comments diffs from asymmetric comment nodes intentionally
        # fall through to profile.normative_dimension? below.  Unlike
        # :whitespace_adjacency (always normative), the classification
        # of comment diffs respects the :comments match option:
        # :strict → normative, :ignore → informative.  This is by
        # design — callers can control whether asymmetric comments
        # affect equivalence via the match profile.

        # THIRD: Determine if this dimension is normative based on CompareProfile
        # This respects the policy settings (strict/normalize/ignore)
        is_normative = profile.normative_dimension?(diff_node.dimension)

        # FOURTH: Check if FormattingDetector should be consulted for non-normative dimensions
        # Only check for formatting-only when dimension is NOT normative
        # This ensures strict mode differences remain normative
        should_check_formatting = !is_normative &&
          profile.supports_formatting_detection?(diff_node.dimension)

        # If we should check formatting, see if it's formatting-only
        if should_check_formatting && formatting_only_diff?(diff_node)
          diff_node.formatting = true
          diff_node.normative = false
          return diff_node
        end

        # FIFTH: Apply the normative determination from CompareProfile
        diff_node.formatting = false
        diff_node.normative = is_normative

        diff_node
      end

      # Classify multiple DiffNodes
      # @param diff_nodes [Array<DiffNode>] The diff nodes to classify
      # @return [Array<DiffNode>] The same diff nodes with normative attributes set
      def classify_all(diff_nodes)
        diff_nodes.each { |node| classify(node) }
      end

      private

      # Check if a DiffNode represents a formatting-only difference
      # @param diff_node [DiffNode] The diff node to check
      # @return [Boolean] true if formatting-only
      def formatting_only_diff?(diff_node)
        # Only apply formatting detection to actual text content differences
        # If the nodes are not text nodes (e.g., element nodes), don't apply formatting detection
        node1 = diff_node.node1
        node2 = diff_node.node2

        # Check if both nodes are text nodes
        # If not, this is not a formatting-only difference
        return false unless text_node?(node1) && text_node?(node2)

        text1 = extract_text_content(diff_node.node1)
        text2 = extract_text_content(diff_node.node2)

        # For text_content dimension, use normalized text comparison
        # This handles cases like "" vs "   " (both normalize to "")
        if diff_node.dimension == :text_content
          normalized_equivalent?(text1, text2)
        else
          FormattingDetector.formatting_only?(text1, text2)
        end
      end

      # Check if two texts are equivalent after normalization
      # This detects formatting-only differences where normalized texts match
      # @param text1 [String, nil] First text
      # @param text2 [String, nil] Second text
      # @return [Boolean] true if normalized texts are equivalent
      def normalized_equivalent?(text1, text2)
        return false if text1.nil? && text2.nil?
        return false if text1.nil? || text2.nil?

        # Use MatchOptions.normalize_text for consistency
        normalized1 = Canon::Comparison::MatchOptions.normalize_text(text1)
        normalized2 = Canon::Comparison::MatchOptions.normalize_text(text2)

        # If normalized texts are equivalent but originals are different,
        # it's a formatting-only difference
        normalized1 == normalized2 && text1 != text2
      end

      # Check if the text node is inside a whitespace-sensitive element
      # (preserve/collapse classification, xml:space='preserve', or
      # between inline element siblings in HTML).
      # In these contexts, whitespace presence is meaningful and should
      # not be dismissed as serialization formatting.
      # @param diff_node [DiffNode] The diff node to check
      # @return [Boolean] true if whitespace is preserved for this element
      def inside_whitespace_sensitive_element?(diff_node)
        node = diff_node.node1 || diff_node.node2
        return false unless node

        # HTML: whitespace between inline element siblings is significant
        if Canon::Comparison::WhitespaceSensitivity.inline_whitespace_significant?(node)
          return true
        end

        # HTML: non-breaking space (U+00A0) is never insignificant
        text = if node.respond_to?(:content)
                 node.content
               elsif node.respond_to?(:value)
                 node.value
               end
        if text && Canon::Comparison::WhitespaceSensitivity.contains_nbsp?(text)
          return true
        end

        return false unless node.respond_to?(:parent)

        parent = node.parent
        return false unless parent

        match_opts = @match_options.options
        Canon::Comparison::WhitespaceSensitivity.whitespace_preserved?(parent,
                                                                       match_opts)
      end

      # Check if the text node is inside a PRESERVE whitespace element
      # Only returns true for elements where whitespace is preserved exactly (:preserve),
      # not for elements where whitespace is normalized (:collapse).
      # @param diff_node [DiffNode] The diff node to check
      # @return [Boolean] true if inside a preserve whitespace element
      def inside_preserve_element?(diff_node)
        node = diff_node.node1 || diff_node.node2
        return false unless node

        match_opts = @match_options.options
        parent = node.parent
        return false unless parent

        classification = Canon::Comparison::WhitespaceSensitivity.classify_element(
          parent, match_opts
        )
        classification == :preserve
      end

      # Extract text content from a node for formatting comparison
      # @param node [Object] The node to extract text from
      # @return [String, nil] The text content or nil
      def extract_text_content(node)
        return nil if node.nil?

        case node
        when Canon::Xml::Nodes::TextNode
          node.value
        when Canon::Xml::Node
          node.text_content
        when Nokogiri::XML::Node
          node.content.to_s
        when Moxml::Node
          node.content.to_s
        when String
          node
        else
          node.to_s
        end
      rescue StandardError
        nil
      end

      # Check if a node is a text node
      # @param node [Object] The node to check
      # @return [Boolean] true if the node is a text node
      def text_node?(node)
        return false if node.nil?

        case node
        when Canon::Xml::Nodes::TextNode
          true
        when Canon::Xml::Node
          node.node_type == :text
        when Nokogiri::XML::Node
          node.node_type == Nokogiri::XML::Node::TEXT_NODE
        when Moxml::Node
          node.text?
        when String
          true
        else
          false
        end
      end
    end
  end
end
