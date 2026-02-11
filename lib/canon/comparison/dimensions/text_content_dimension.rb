# frozen_string_literal: true

require_relative "base_dimension"
require_relative "../match_options"

module Canon
  module Comparison
    module Dimensions
      # Text content dimension
      #
      # Handles comparison of text content in nodes.
      # Supports :strict, :normalize, and :ignore behaviors.
      #
      # Behaviors:
      # - :strict - Exact text comparison including whitespace
      # - :normalize - Collapse whitespace and compare
      # - :ignore - Skip text content comparison
      class TextContentDimension < BaseDimension
        # Extract text content from a node
        #
        # @param node [Moxml::Node, Nokogiri::XML::Node] Node to extract from
        # @return [String, nil] Text content or nil if not a text node
        def extract_data(node)
          return nil unless node

          # Handle Moxml nodes
          if node.is_a?(Moxml::Node)
            extract_from_moxml(node)
          # Handle Nokogiri nodes
          elsif node.is_a?(Nokogiri::XML::Node)
            extract_from_nokogiri(node)
          end
        end

        # Strict text comparison
        #
        # @param text1 [String, nil] First text
        # @param text2 [String, nil] Second text
        # @return [Boolean] true if texts are exactly equal
        def compare_strict(text1, text2)
          text1.to_s == text2.to_s
        end

        # Normalized text comparison
        #
        # Collapses whitespace and compares.
        # Two whitespace-only strings that both normalize to empty are equivalent.
        #
        # @param text1 [String, nil] First text
        # @param text2 [String, nil] Second text
        # @return [Boolean] true if normalized texts are equal
        def compare_normalize(text1, text2)
          normalized1 = normalize_text(text1)
          normalized2 = normalize_text(text2)

          # Both empty after normalization = equivalent
          # This handles whitespace-only text nodes that normalize to empty
          return true if normalized1.empty? && normalized2.empty?

          normalized1 == normalized2
        end

        private

        # Extract text from Moxml node
        #
        # @param node [Moxml::Node] Moxml node
        # @return [String, nil] Text content
        def extract_from_moxml(node)
          case node.node_type
          when :text, :cdata
            node.content
          when :element
            # For element nodes, extract concatenated text from children
            node.text
          end
        end

        # Extract text from Nokogiri node
        #
        # @param node [Nokogiri::XML::Node] Nokogiri node
        # @return [String, nil] Text content
        def extract_from_nokogiri(node)
          case node.node_type
          when Nokogiri::XML::Node::TEXT_NODE, Nokogiri::XML::Node::CDATA_SECTION_NODE
            node.content
          when Nokogiri::XML::Node::ELEMENT_NODE
            node.content
          end
        end

        # Normalize text by collapsing whitespace
        #
        # Uses MatchOptions.normalize_text for consistency.
        #
        # @param text [String, nil] Text to normalize
        # @return [String] Normalized text
        def normalize_text(text)
          MatchOptions.normalize_text(text)
        end
      end
    end
  end
end
