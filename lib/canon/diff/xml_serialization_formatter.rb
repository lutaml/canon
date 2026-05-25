# frozen_string_literal: true

module Canon
  module Diff
    # Detects and classifies XML serialization-level formatting differences.
    #
    # Serialization formatting differences are ALWAYS non-normative (formatting-only)
    # regardless of match options, because they are purely syntactic variations.
    class XmlSerializationFormatter
      NI = Canon::Comparison::NodeInspector

      def self.serialization_formatting?(diff_node)
        return false unless diff_node.dimension == :text_content

        empty_text_content_serialization_diff?(diff_node)
      end

      def self.empty_text_content_serialization_diff?(diff_node)
        return false unless diff_node.dimension == :text_content

        node1 = diff_node.node1
        node2 = diff_node.node2

        return false if node1.nil? && node2.nil?

        if node1.nil? || node2.nil?
          non_nil = node1 || node2
          return false unless text_node?(non_nil)

          text = extract_text_content(non_nil)
          return blank?(text)
        end

        return false unless text_node?(node1) && text_node?(node2)

        text1 = extract_text_content(node1)
        text2 = extract_text_content(node2)

        blank?(text1) && blank?(text2)
      end

      def self.blank?(value)
        value.nil? || value.to_s.strip.empty?
      end

      def self.text_node?(node)
        return false if node.nil?
        return true if node.is_a?(String)

        NI.text_node?(node)
      end

      def self.extract_text_content(node)
        return nil if node.nil?

        NI.text_content(node)
      rescue StandardError
        nil
      end
    end
  end
end
