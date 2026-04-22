# frozen_string_literal: true

require "paint"
require "diff/lcs"

module Canon
  class DiffFormatter
    # Handles the pretty_diff rendering pipeline for text-LCS diffs.
    #
    # Bypasses DiffNodeMapper entirely — runs Diff::LCS.sdiff on plain-text
    # lines and renders with context windowing and colorization.
    class PrettyDiffFormatter
      def initialize(use_color:, context_lines:)
        @use_color = use_color
        @context_lines = context_lines
      end

      # Format a text-LCS diff between two documents.
      #
      # @param doc1 [String, nil] First document (already preprocessed)
      # @param doc2 [String, nil] Second document (already preprocessed)
      # @param format [Symbol] Document format for display name
      # @return [String] Formatted diff output
      def format(doc1, doc2, format:)
        format_name = format.to_s.upcase

        output = []
        output << colorize("Pretty diff (#{format_name} mode):", :cyan, :bold)

        return output.join("\n") if doc1.nil? || doc2.nil?

        lines1 = doc1.lines.map(&:chomp)
        lines2 = doc2.lines.map(&:chomp)

        hunks = ::Diff::LCS.sdiff(lines1, lines2)

        output << render_pretty_diff(hunks)
        output.join("\n")
      end

      private

      # Render sdiff hunks with context windowing and colorization.
      #
      # Uses context_lines setting for expansion. Changed hunks
      # (action != "=") are expanded by context_lines in each direction;
      # nearby windows are merged; a separator is emitted between
      # non-adjacent blocks.
      #
      # @param hunks [Array<Diff::LCS::ContextChange>] Output of Diff::LCS.sdiff
      # @return [String] Rendered diff lines joined with "\n"
      def render_pretty_diff(hunks)
        changed = hunks.each_index.reject { |i| hunks[i].action == "=" }

        return colorize("  (no differences)", :green) if changed.empty?

        ctx = [@context_lines || 3, 0].max

        windows = changed.map do |pos|
          [
            [pos - ctx, 0].max,
            [pos + ctx, hunks.length - 1].min,
          ]
        end

        merged = []
        windows.each do |lo, hi|
          if merged.empty? || lo > merged.last[1] + 1
            merged << [lo, hi]
          else
            merged.last[1] = [merged.last[1], hi].max
          end
        end

        lines = []
        merged.each_with_index do |(lo, hi), block_idx|
          if block_idx.positive?
            lines << colorize("--- ---", :cyan)
          elsif lo.positive?
            lines << colorize("--- ---", :cyan)
          end

          (lo..hi).each do |i|
            hunk = hunks[i]
            case hunk.action
            when "="
              lines << (@use_color ? "\e[0m  #{hunk.old_element}" : "  #{hunk.old_element}")
            when "-"
              lines << colorize("- #{hunk.old_element}", :red)
            when "+"
              lines << colorize("+ #{hunk.new_element}", :green)
            when "!"
              lines << colorize("- #{hunk.old_element}", :red)
              lines << colorize("+ #{hunk.new_element}", :green)
            end
          end
        end

        lines.join("\n")
      end

      def colorize(text, *colors)
        return text unless @use_color
        "\e[0m#{Paint[text, *colors]}"
      end
    end
  end
end
