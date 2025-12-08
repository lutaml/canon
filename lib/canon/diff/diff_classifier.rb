# frozen_string_literal: true

require_relative "formatting_detector"
require_relative "../comparison/compare_profile"

module Canon
  module Diff
    # Classifies DiffNodes as normative (affects equivalence) or informative (doesn't affect equivalence)
    # based on the match options in effect
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
      # First checks if the difference is formatting-only, then applies normative/informative logic
      # @param diff_node [DiffNode] The diff node to classify
      # @return [DiffNode] The same diff node with normative/formatting attributes set
      def classify(diff_node)
        # First, determine if this dimension is normative (affects equivalence)
        is_normative = profile.normative_dimension?(diff_node.dimension)

        # If the dimension is normative, it cannot be formatting-only
        if is_normative
          diff_node.formatting = false
          diff_node.normative = true
          return diff_node
        end

        # For non-normative dimensions, check if formatting-only applies
        if profile.supports_formatting_detection?(diff_node.dimension)
          # For text/content dimensions, check if formatting-only
          if formatting_only_diff?(diff_node)
            diff_node.formatting = true
            diff_node.normative = false
          else
            # Not formatting-only, but still non-normative (informative)
            diff_node.formatting = false
            diff_node.normative = false
          end
        else
          # Doesn't support formatting detection, just mark as non-normative
          diff_node.formatting = false
          diff_node.normative = false
        end

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
        text1 = extract_text_content(diff_node.node1)
        text2 = extract_text_content(diff_node.node2)

        FormattingDetector.formatting_only?(text1, text2)
      end

      # Extract text content from a node for formatting comparison
      # @param node [Object] The node to extract text from
      # @return [String, nil] The text content or nil
      def extract_text_content(node)
        return nil if node.nil?

        # For TextNode with value attribute (Canon::Xml::Nodes::TextNode)
        return node.value if node.respond_to?(:value) && node.is_a?(Canon::Xml::Nodes::TextNode)

        # For XML/HTML nodes with text_content method
        return node.text_content if node.respond_to?(:text_content)

        # For nodes with text method
        return node.text if node.respond_to?(:text)

        # For nodes with content method
        return node.content if node.respond_to?(:content)

        # For nodes with value method (other types)
        return node.value if node.respond_to?(:value)

        # For simple text nodes or strings
        return node.to_s if node.is_a?(String)

        # For other node types, try to_s
        node.to_s
      rescue StandardError
        # If extraction fails, return nil (not formatting-only)
        nil
      end
    end
  end
end
