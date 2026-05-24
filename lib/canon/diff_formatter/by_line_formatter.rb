# frozen_string_literal: true

require "paint" unless RUBY_ENGINE == "opal"

module Canon
  class DiffFormatter
    # Handles the by_line rendering pipeline for line-by-line diffs.
    #
    # Receives preprocessed document strings from the DiffFormatter facade
    # and delegates to format-specific ByLine formatters (XML, HTML, JSON, YAML).
    class ByLineFormatter
      # rubocop:disable Metrics/ParameterLists
      def initialize(use_color:, visualization_map:, context_lines:,
                     diff_grouping_lines:, show_diffs:, character_visualization:,
                     legacy_terminal:, diff_mode:)
        @use_color = use_color
        @visualization_map = visualization_map
        @context_lines = context_lines
        @diff_grouping_lines = diff_grouping_lines
        @show_diffs = show_diffs
        @character_visualization = character_visualization
        @legacy_terminal = legacy_terminal
        @diff_mode = diff_mode
      end
      # rubocop:enable Metrics/ParameterLists

      # Format a line-by-line diff between two documents.
      #
      # @param doc1 [String] First document (already preprocessed)
      # @param doc2 [String] Second document (already preprocessed)
      # @param format [Symbol] Document format (:xml, :html, :json, :yaml, etc.)
      # @param html_version [Symbol, nil] HTML version override (:html4, :html5)
      # @param differences [Array, ComparisonResult] Differences from comparison
      # @return [String] Formatted diff output
      def format(doc1, doc2, format:, html_version: nil, differences: [])
        resolved_format = format == :html && html_version ? html_version : format
        format_name = resolved_format.to_s.upcase

        output = []
        output << colorize("Line-by-line diff (#{format_name} mode):", :cyan,
                           :bold)

        return output.join("\n") if doc1.nil? || doc2.nil?

        diffs_array = extract_differences(differences)

        formatter = ByLine::BaseFormatter.for_format(
          resolved_format,
          use_color: @use_color,
          context_lines: @context_lines,
          diff_grouping_lines: @diff_grouping_lines,
          visualization_map: @visualization_map,
          show_diffs: @show_diffs,
          differences: diffs_array,
          diff_mode: @legacy_terminal ? :separate : @diff_mode,
          legacy_terminal: @legacy_terminal,
          equivalent: @comparison_equivalent,
          character_visualization: @character_visualization,
        )

        output << formatter.format(doc1, doc2)
        output.join("\n")
      end

      private

      def extract_differences(differences)
        if differences.is_a?(Canon::Comparison::ComparisonResult)
          @comparison_equivalent = differences.equivalent?
          differences.differences
        else
          @comparison_equivalent = nil
          differences
        end
      end

      def colorize(text, *colors)
        return text unless @use_color

        "\e[0m#{Paint[text, *colors]}"
      end
    end
  end
end
