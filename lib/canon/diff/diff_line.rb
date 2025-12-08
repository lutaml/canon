# frozen_string_literal: true

module Canon
  module Diff
    # Represents a single line in the diff output
    # Links textual representation to semantic DiffNode
    class DiffLine
      attr_reader :line_number, :content, :type, :diff_node

      # @param line_number [Integer] The line number in the original text
      # @param content [String] The text content of the line
      # @param type [Symbol] The type of line (:unchanged, :added, :removed, :changed)
      # @param diff_node [DiffNode, nil] The semantic diff node this line belongs to
      # @param formatting [Boolean] Whether this is a formatting-only difference
      def initialize(line_number:, content:, type:, diff_node: nil, formatting: false)
        @line_number = line_number
        @content = content
        @type = type
        @diff_node = diff_node
        @formatting = formatting
      end

      # @return [Boolean] true if this line represents a normative difference
      # If diff_node is nil (not linked to any semantic difference), the line
      # is considered informative (cosmetic/unchanged)
      # Formatting-only diffs are never normative
      def normative?
        return false if formatting?
        return false if diff_node.nil?

        diff_node.normative?
      end

      # @return [Boolean] true if this line represents an informative-only difference
      # If diff_node is nil (not linked), it's not informative either (it's unchanged/cosmetic)
      # Formatting-only diffs are never informative
      def informative?
        return false if formatting?
        return false if diff_node.nil?

        diff_node.informative?
      end

      # @return [Boolean] true if this line represents a formatting-only difference
      # Formatting diffs are purely cosmetic (whitespace, line breaks) with no semantic meaning
      def formatting?
        @formatting == true
      end

      # @return [Boolean] true if this line is unchanged
      def unchanged?
        type == :unchanged
      end

      # @return [Boolean] true if this line was added
      def added?
        type == :added
      end

      # @return [Boolean] true if this line was removed
      def removed?
        type == :removed
      end

      # @return [Boolean] true if this line was changed
      def changed?
        type == :changed
      end

      def to_h
        {
          line_number: line_number,
          content: content,
          type: type,
          diff_node: diff_node&.to_h,
          normative: normative?,
          informative: informative?,
          formatting: formatting?,
        }
      end

      def ==(other)
        other.is_a?(DiffLine) &&
          line_number == other.line_number &&
          content == other.content &&
          type == other.type &&
          diff_node == other.diff_node &&
          @formatting == other.instance_variable_get(:@formatting)
      end
    end
  end
end
