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
      def initialize(line_number:, content:, type:, diff_node: nil)
        @line_number = line_number
        @content = content
        @type = type
        @diff_node = diff_node
      end

      # @return [Boolean] true if this line represents a semantic difference
      def active?
        diff_node&.active? || false
      end

      # @return [Boolean] true if this line represents a textual-only difference
      def inactive?
        diff_node&.inactive? || false
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
          active: active?,
        }
      end

      def ==(other)
        other.is_a?(DiffLine) &&
          line_number == other.line_number &&
          content == other.content &&
          type == other.type &&
          diff_node == other.diff_node
      end
    end
  end
end
