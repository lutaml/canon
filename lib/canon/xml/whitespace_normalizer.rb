# frozen_string_literal: true

module Canon
  module Xml
    # Handles whitespace normalization for flexible XML/HTML comparison
    #
    # Provides MECE (Mutually Exclusive, Collectively Exhaustive) methods
    # for normalizing different categories of whitespace:
    # 1. Indentation whitespace
    # 2. Inter-element whitespace (between tags)
    # 3. Text content whitespace (within text nodes)
    # 4. Tag boundary whitespace (inside tags)
    # 5. Attribute formatting (handled by existing ignore_attr_order)
    class WhitespaceNormalizer
      # Normalize text content by collapsing all whitespace sequences
      # to single spaces and trimming leading/trailing whitespace
      #
      # @param text [String] Text to normalize
      # @return [String] Normalized text
      def normalize_text_content(text)
        return "" if text.nil?

        text.to_s
          .gsub(/\s+/, " ")  # Collapse all whitespace sequences to single space
          .strip             # Remove leading/trailing whitespace
      end

      # Normalize indentation by removing all leading whitespace from each line
      #
      # @param text [String] Text with indentation
      # @return [String] Text with indentation removed
      def normalize_indentation(text)
        return "" if text.nil?

        text.to_s
          .lines
          .map(&:lstrip) # Remove leading whitespace from each line
          .join
      end

      # Normalize inter-element whitespace (whitespace between tags)
      # This removes whitespace-only text nodes between elements
      #
      # @param node [Moxml::Node] Node to check
      # @return [Boolean] true if node is whitespace-only and should be ignored
      def inter_element_whitespace?(node)
        return false unless node.respond_to?(:text?) && node.text?

        text = node.respond_to?(:content) ? node.content.to_s : node.text.to_s
        text.strip.empty?
      end

      # Normalize tag boundary whitespace
      # This is the same as normalizing text content for now,
      # but kept separate for MECE clarity
      #
      # @param text [String] Text at tag boundary
      # @return [String] Normalized text
      def normalize_tag_boundaries(text)
        normalize_text_content(text)
      end

      # Check if two text strings are equivalent under flexible whitespace rules
      #
      # @param text1 [String] First text
      # @param text2 [String] Second text
      # @return [Boolean] true if equivalent after normalization
      def flexible_equivalent?(text1, text2)
        normalize_text_content(text1) == normalize_text_content(text2)
      end
    end
  end
end
