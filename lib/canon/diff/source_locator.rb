# frozen_string_literal: true

module Canon
  module Diff
    # Locates serialized content within source text and maps character offsets
    # to line/column positions. Used during DiffNode enrichment (Phase 1).
    #
    # The SourceLocator uses String#index on the full source text (not LCS on
    # lines) to find where a DiffNode's serialized content appears. It then
    # maps the character offset to a line number and column position using
    # a pre-built line offset map.
    #
    # @example
    #   line_map = SourceLocator.build_line_map("line1\nline2\nline3")
    #   SourceLocator.locate("line2", "line1\nline2\nline3", line_map)
    #   # => { char_offset: 6, line_number: 1, col: 0 }
    class SourceLocator
      # Line offset map: two flat Integer arrays (starts, ends) — a
      # hash-per-line was one allocation per document line on every
      # enrichment, the presentation stage's quiet constant.
      class LineMap
        attr_reader :starts, :ends

        def initialize(starts, ends)
          @starts = starts
          @ends = ends
        end

        def empty?
          @starts.empty?
        end

        def line_count
          @starts.length
        end

        def start_at(index)
          @starts[index]
        end

        def end_at(index)
          @ends[index]
        end
      end

      # Build a line offset map from source text.
      #
      # @param text [String] the full source text
      # @return [LineMap] flat offset arrays, one entry per line
      #   (0-indexed)
      def self.build_line_map(text)
        return LineMap.new([], []) if text.nil? || text.empty?

        starts = []
        offset = 0
        text.each_line do |line|
          starts << offset
          offset += line.length
        end
        ends = starts[1..] || []
        ends << text.length
        LineMap.new(starts, ends)
      end

      # Locate a substring within source text and return its position.
      #
      # @param substring [String] the content to find (e.g., serialized_before)
      # @param text [String] the full source text
      # @param line_map [Array<Hash>] pre-built line offset map
      # @param start_from [Integer, nil] character offset to start searching from
      # @return [Hash, nil] { char_offset:, line_number:, col: } or nil if not found
      def self.locate(substring, text, line_map, start_from: nil)
        return nil if substring.nil? || substring.empty?
        return nil if text.nil? || line_map.empty?

        char_offset = if start_from
                        text.index(substring, start_from)
                      else
                        text.index(substring)
                      end
        return nil if char_offset.nil?

        line_idx = find_line_for_offset(char_offset, line_map)
        return nil if line_idx.nil?

        col = char_offset - line_map.start_at(line_idx)

        { char_offset: char_offset, line_number: line_idx, col: col }
      end

      # Locate ALL occurrences of a substring within source text.
      #
      # @param substring [String] the content to find
      # @param text [String] the full source text
      # @param line_map [Array<Hash>] pre-built line offset map
      # @return [Array<Hash>] array of { char_offset:, line_number:, col: } hashes
      def self.locate_all(substring, text, line_map)
        return [] if substring.nil? || substring.empty?
        return [] if text.nil? || line_map.empty?

        results = []
        offset = 0

        while (pos = text.index(substring, offset))
          line_idx = find_line_for_offset(pos, line_map)
          break if line_idx.nil?

          col = pos - line_map.start_at(line_idx)
          results << { char_offset: pos, line_number: line_idx, col: col }
          offset = pos + 1
        end

        results
      end

      class << self
        # Binary search for the line containing a character offset.
        #
        # @param char_offset [Integer] the character offset
        # @param line_map [Array<Hash>] the line offset map
        # @return [Integer, nil] the 0-based line index, or nil
        def find_line_for_offset(char_offset, line_map)
          line_map.ends.bsearch_index do |end_offset|
            end_offset > char_offset
          end
        end
      end
    end
  end
end
