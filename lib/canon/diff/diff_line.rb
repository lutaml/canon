# frozen_string_literal: true

module Canon
  module Diff
    # Represents a single line in the diff output
    # Links textual representation to semantic DiffNode and DiffCharRanges
    class DiffLine
      attr_reader :line_number, :new_position, :content, :type, :diff_node,
                  :char_ranges, :new_char_ranges, :new_content
      attr_accessor :old_content
      attr_writer :formatting

      # @param line_number [Integer] The 0-based line number in text1 (old text)
      # @param new_position [Integer, nil] The 0-based line number in text2 (new text),
      #   used for :changed lines where old and new positions differ
      # @param content [String] The text content of the line (from text1)
      # @param type [Symbol] The type of line (:unchanged, :added, :removed, :changed)
      # @param diff_node [DiffNode, nil] The semantic diff node this line belongs to
      # @param formatting [Boolean] Whether this is a formatting-only difference
      # @param char_ranges [Array<DiffCharRange>] Character ranges for text1 side
      # @param new_char_ranges [Array<DiffCharRange>] Character ranges for text2 side
      # @param new_content [String, nil] The text2 line content (for :changed lines)
      # @param old_content [String, nil] Deprecated: multi-line old content
      def initialize(line_number:, content:, type:, diff_node: nil,
                     formatting: false, new_position: nil, old_content: nil,
                     char_ranges: nil, new_char_ranges: nil, new_content: nil)
        @line_number = line_number
        @new_position = new_position
        @content = content
        @type = type
        @diff_node = diff_node
        @formatting = formatting
        @old_content = old_content
        @char_ranges = char_ranges || []
        @new_char_ranges = new_char_ranges || []
        @new_content = new_content
      end

      # Add a character range for the text1 (old) side
      # @param char_range [DiffCharRange]
      def add_char_range(char_range)
        @char_ranges << char_range
      end

      # Add a character range for the text2 (new) side
      # @param char_range [DiffCharRange]
      def add_new_char_range(char_range)
        @new_char_ranges << char_range
      end

      # @return [Boolean] true if this line has any character ranges
      def has_char_ranges?
        !@char_ranges.empty? || !@new_char_ranges.empty?
      end

      # Get character ranges for a specific side
      # @param side [Symbol] :old or :new
      # @return [Array<DiffCharRange>]
      def char_ranges_for_side(side)
        side == :old ? @char_ranges : @new_char_ranges
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
          new_position: new_position,
          content: content,
          new_content: new_content,
          type: type,
          diff_node: diff_node&.to_h,
          normative: normative?,
          informative: informative?,
          formatting: formatting?,
          char_ranges: @char_ranges.map(&:to_h),
          new_char_ranges: @new_char_ranges.map(&:to_h),
        }
      end

      def ==(other)
        other.is_a?(DiffLine) &&
          line_number == other.line_number &&
          new_position == other.new_position &&
          content == other.content &&
          type == other.type &&
          diff_node == other.diff_node &&
          formatting? == other.formatting?
      end
    end
  end
end
