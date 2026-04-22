# frozen_string_literal: true

require "paint"

module Canon
  class DiffFormatter
    # Handles the by_object rendering pipeline for tree-based semantic diffs.
    #
    # Delegates to format-specific ByObject formatters (XML, JSON, YAML)
    # which produce visual tree output with box-drawing characters.
    class ByObjectFormatter
      def initialize(use_color:, visualization_map:, show_diffs:)
        @use_color = use_color
        @visualization_map = visualization_map
        @show_diffs = show_diffs
      end

      # Format a tree-based object diff.
      #
      # @param differences [Array, ComparisonResult] Differences from comparison
      # @param format [Symbol] Document format (:xml, :json, :yaml)
      # @return [String] Formatted diff output
      def format(differences, format)
        output = []
        output << colorize("Visual Diff:", :cyan, :bold)

        diffs_array = if differences.is_a?(Canon::Comparison::ComparisonResult)
                        differences.differences
                      else
                        differences
                      end

        formatter = ByObject::BaseFormatter.for_format(
          format,
          use_color: @use_color,
          visualization_map: @visualization_map,
          show_diffs: @show_diffs,
        )

        output << formatter.format(diffs_array, format)
        output.join("\n")
      end

      private

      def colorize(text, *colors)
        return text unless @use_color
        "\e[0m#{Paint[text, *colors]}"
      end
    end
  end
end
