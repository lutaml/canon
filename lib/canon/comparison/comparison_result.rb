# frozen_string_literal: true

module Canon
  module Comparison
    # Encapsulates the result of a comparison operation
    # Provides methods to query equivalence based on normative diffs
    class ComparisonResult
      attr_reader :differences, :preprocessed_strings, :format, :html_version,
                  :match_options, :algorithm, :original_strings,
                  :parse_errors_expected, :parse_errors_received

      # @param differences [Array<DiffNode>] Array of difference nodes
      # @param preprocessed_strings [Array<String, String>] Pre-processed content for display
      # @param format [Symbol] Format type (:xml, :html, :json, :yaml)
      # @param html_version [Symbol, nil] HTML version (:html4 or :html5) for HTML format only
      # @param match_options [Hash, nil] Resolved match options used for comparison
      # @param algorithm [Symbol] Diff algorithm used (:dom or :semantic)
      # @param original_strings [Array<String, String>, nil] Original unprocessed content for line diff
      # @param parse_errors_expected [Array<String>, nil] Parser errors from the expected side
      # @param parse_errors_received [Array<String>, nil] Parser errors from the received side
      def initialize(differences:, preprocessed_strings:, format:,
html_version: nil, match_options: nil, algorithm: :dom, original_strings: nil,
parse_errors_expected: nil, parse_errors_received: nil)
        @differences = differences
        @preprocessed_strings = preprocessed_strings
        @original_strings = original_strings || preprocessed_strings
        @format = format
        @html_version = html_version
        @match_options = match_options
        @algorithm = algorithm
        @parse_errors_expected = Array(parse_errors_expected)
        @parse_errors_received = Array(parse_errors_received)
      end

      # Whether either side reported parse errors.  Used by the diff
      # formatter to decide whether to render the parse-error banner.
      #
      # @return [Boolean]
      def parse_errors?
        @parse_errors_expected.any? || @parse_errors_received.any?
      end

      # Check if documents are semantically equivalent (no normative diffs)
      #
      # @return [Boolean] true if no normative differences present
      def equivalent?
        !has_normative_diffs?
      end

      # Check if there are any normative (semantic) differences
      # Includes both DiffNode objects marked as normative AND legacy Hash differences
      # (which represent structural differences like element name mismatches)
      #
      # @return [Boolean] true if at least one normative diff exists
      def has_normative_diffs?
        @differences.any? do |diff|
          # DiffNode objects - check if marked normative
          if diff.is_a?(Canon::Diff::DiffNode)
            diff.normative?
          # Legacy Hash format - always considered normative (structural differences)
          else
            diff.is_a?(Hash)
          end
        end
      end

      # Check if there are any informative (textual-only) differences
      #
      # @return [Boolean] true if at least one informative diff exists
      def has_informative_diffs?
        @differences.any? do |diff|
          diff.is_a?(Canon::Diff::DiffNode) && diff.informative?
        end
      end

      # Get all normative differences
      #
      # @return [Array<DiffNode>] Normative differences only
      def normative_differences
        @differences.select do |diff|
          diff.is_a?(Canon::Diff::DiffNode) && diff.normative?
        end
      end

      # Get all informative differences
      #
      # @return [Array<DiffNode>] Informative differences only
      def informative_differences
        @differences.select do |diff|
          diff.is_a?(Canon::Diff::DiffNode) && diff.informative?
        end
      end

      # Get tree diff operations (only available when diff_algorithm: :semantic)
      #
      # @return [Array<Operation>] Array of tree diff operations
      def operations
        @match_options&.[](:tree_diff_operations) || []
      end

      # Generate a human-readable summary of the first difference.
      #
      # When documents are equivalent, returns "Equivalent".
      # When they differ, returns a single-line string with the first normative
      # (or first informative) difference location and reason.
      #
      # @return [String] Summary string
      def summary
        return "Equivalent" if equivalent?

        diff = normative_differences.first || informative_differences.first ||
               @differences.first # rubocop:disable Layout/MultilineOperationIndentation

        return "Not equivalent" unless diff

        if diff.is_a?(Canon::Diff::DiffNode)
          summarize_diff_node(diff)
        elsif diff.is_a?(Hash)
          summarize_legacy_hash(diff)
        else
          "Not equivalent"
        end
      end

      # Generate formatted diff output
      #
      # @param use_color [Boolean] Whether to use ANSI color codes
      # @param context_lines [Integer] Number of context lines to show
      # @param diff_grouping_lines [Integer] Maximum gap for grouping diffs
      # @param show_diffs [Symbol] Which diffs to show (:all, :normative, :informative)
      # @param diff_mode [Symbol] Diff display mode (:separate, :inline)
      # @param legacy_terminal [Boolean] Force legacy mode (no ANSI, separate-line only)
      # @return [String] Formatted diff output
      def diff(use_color: true, context_lines: 3, diff_grouping_lines: nil,
show_diffs: :all, diff_mode: :separate, legacy_terminal: false)
        formatter = Canon::DiffFormatter.new(
          use_color: use_color,
          mode: :by_line,
          context_lines: context_lines,
          diff_grouping_lines: diff_grouping_lines,
          show_diffs: show_diffs,
          diff_mode: diff_mode,
          legacy_terminal: legacy_terminal,
        )

        # Pass self (ComparisonResult) so formatter can check equivalent? status
        formatter.format(
          self,
          @format,
          doc1: @preprocessed_strings[0],
          doc2: @preprocessed_strings[1],
          html_version: @html_version,
        )
      end

      private

      # Format a single DiffNode into a summary string.
      #
      # @param diff [DiffNode] The difference to summarize
      # @return [String] Human-readable summary
      def summarize_diff_node(diff)
        parts = ["Not equivalent:"]

        # rubocop:disable Layout/SpaceBeforeInterpolation,Style/ConditionalAssignment
        if diff.path
          parts << "#{diff.reason} at #{diff.path}"
        else
          parts << diff.reason.to_s
        end
        # rubocop:enable Layout/SpaceBeforeInterpolation,Style/ConditionalAssignment

        if diff.serialized_before && diff.serialized_after
          before_preview = truncate_preview(diff.serialized_before)
          after_preview = truncate_preview(diff.serialized_after)
          parts << "(#{before_preview} vs #{after_preview})"
        end

        parts.join(" ")
      end

      # Format a legacy Hash difference into a summary string.
      #
      # @param diff [Hash] Legacy difference hash with :path, :value1, :value2
      # @return [String] Human-readable summary
      def summarize_legacy_hash(diff)
        parts = ["Not equivalent:"]
        parts << "#{diff[:diff_code_description]} at #{diff[:path]}" if diff[:path]

        if diff[:value1] && diff[:value2]
          parts << "(#{truncate_preview(diff[:value1].to_s)} vs #{truncate_preview(diff[:value2].to_s)})"
        end

        parts.size > 1 ? parts.join(" ") : "Not equivalent: values differ"
      end

      # Truncate a string for preview display.
      #
      # @param text [String] Text to truncate
      # @param max_len [Integer] Maximum length
      # @return [String] Truncated text with ellipsis if needed
      def truncate_preview(text, max_len = 40)
        stripped = text.strip.gsub(/\s+/, " ")
        if stripped.length > max_len
          "#{stripped[0...(max_len - 3)]}..."
        else
          stripped
        end
      end
    end
  end
end
