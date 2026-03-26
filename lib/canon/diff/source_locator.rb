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
      # Build a line offset map from source text.
      # Each entry records the start and end character offset of a line.
      #
      # @param text [String] the full source text
      # @return [Array<Hash>] array of { start_offset:, end_offset: } hashes,
      #   one per line (0-indexed)
      def self.build_line_map(text)
        return [] if text.nil? || text.empty?

        map = []
        offset = 0
        text.each_line do |line|
          line_end = offset + line.length
          map << { start_offset: offset, end_offset: line_end }
          offset = line_end
        end
        map
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

        col = char_offset - line_map[line_idx][:start_offset]

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

          col = pos - line_map[line_idx][:start_offset]
          results << { char_offset: pos, line_number: line_idx, col: col }
          offset = pos + 1
        end

        results
      end

      class << self
        private

        # Binary search for the line containing a character offset.
        #
        # @param char_offset [Integer] the character offset
        # @param line_map [Array<Hash>] the line offset map
        # @return [Integer, nil] the 0-based line index, or nil
        def find_line_for_offset(char_offset, line_map)
          # Use bsearch for efficiency on large files
          line_map.bsearch_index do |entry|
            entry[:end_offset] > char_offset
          end
        end
      end
    end
  end
end
