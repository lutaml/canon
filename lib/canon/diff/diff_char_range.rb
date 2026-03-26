# frozen_string_literal: true

module Canon
  module Diff
    # Represents a character range within a source line, linked to a DiffNode.
    #
    # DiffCharRange is the core abstraction for character-level diff rendering.
    # Each DiffNode produces one or more DiffCharRanges (before-text, changed-text,
    # after-text) that tell the formatter exactly which characters to highlight.
    #
    # The formatter reads DiffCharRanges and applies colors — no computation needed.
    #
    # @example Text change "Hello World" → "Hello Universe"
    #   # Before-text (unchanged):
    #   DiffCharRange.new(line_number: 0, start_col: 9, end_col: 15,
    #                     side: :old, status: :unchanged, role: :before, diff_node: dn)
    #   # Changed-text (old side):
    #   DiffCharRange.new(line_number: 0, start_col: 15, end_col: 20,
    #                     side: :old, status: :changed_old, role: :changed, diff_node: dn)
    #   # Changed-text (new side):
    #   DiffCharRange.new(line_number: 0, start_col: 15, end_col: 23,
    #                     side: :new, status: :changed_new, role: :changed, diff_node: dn)
    class DiffCharRange
      # @return [Integer] 0-based line index in text1 or text2
      attr_reader :line_number

      # @return [Integer] 0-based column offset (inclusive start)
      attr_reader :start_col

      # @return [Integer] exclusive end (half-open [start_col, end_col))
      attr_reader :end_col

      # @return [Symbol] :old (text1) or :new (text2)
      attr_reader :side

      # @return [Symbol] :unchanged, :removed, :added, :changed_old, :changed_new
      attr_reader :status

      # @return [Symbol] :before, :changed, :after
      attr_reader :role

      # @return [DiffNode, nil] the originating DiffNode
      attr_reader :diff_node

      # @param line_number [Integer] 0-based line index
      # @param start_col [Integer] 0-based column (inclusive)
      # @param end_col [Integer] exclusive end
      # @param side [Symbol] :old or :new
      # @param status [Symbol] :unchanged, :removed, :added, :changed_old, :changed_new
      # @param role [Symbol] :before, :changed, :after
      # @param diff_node [DiffNode, nil] originating DiffNode
      def initialize(line_number:, start_col:, end_col:, side:, status:,
                     role: nil, diff_node: nil)
        @line_number = line_number
        @start_col = start_col
        @end_col = end_col
        @side = side
        @status = status
        @role = role
        @diff_node = diff_node
      end

      # @return [Boolean] true if this range has zero length
      def empty?
        start_col >= end_col
      end

      # @return [Integer] number of characters in this range
      def length
        end_col - start_col
      end

      # @param line_length [Integer] total length of the line
      # @return [Boolean] true if this range covers the entire line
      def covers_entire_line?(line_length)
        start_col.zero? && end_col >= line_length
      end

      # Extract the substring this range covers from a line
      # @param line_text [String] the full line text
      # @return [String] the substring, or "" if out of bounds
      def extract_from(line_text)
        return "" if line_text.nil? || empty?

        line_text[start_col...end_col] || ""
      end

      # @return [Boolean] true if this is an old-side (text1) range
      def old_side?
        side == :old
      end

      # @return [Boolean] true if this is a new-side (text2) range
      def new_side?
        side == :new
      end

      # @return [Boolean] true if this range represents unchanged content
      def unchanged?
        status == :unchanged
      end

      # @return [Boolean] true if this range represents a change on the old side
      def changed_old?
        status == :changed_old
      end

      # @return [Boolean] true if this range represents a change on the new side
      def changed_new?
        status == :changed_new
      end

      # @return [Boolean] true if this range should be highlighted
      def highlighted?
        %i[changed_old changed_new removed added].include?(status)
      end

      def to_h
        {
          line_number: line_number,
          start_col: start_col,
          end_col: end_col,
          side: side,
          status: status,
          role: role,
        }
      end

      def ==(other)
        other.is_a?(DiffCharRange) &&
          line_number == other.line_number &&
          start_col == other.start_col &&
          end_col == other.end_col &&
          side == other.side &&
          status == other.status &&
          role == other.role
      end
    end
  end
end
