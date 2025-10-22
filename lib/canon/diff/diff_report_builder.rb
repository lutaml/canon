# frozen_string_literal: true

require_relative "diff_report"
require_relative "diff_block_builder"
require_relative "diff_context_builder"

module Canon
  module Diff
    # Builds a complete DiffReport from DiffLines
    # Orchestrates the pipeline: DiffLines → DiffBlocks → DiffContexts → DiffReport
    class DiffReportBuilder
      # Build a diff report from diff lines
      #
      # @param diff_lines [Array<DiffLine>] The diff lines to process
      # @param options [Hash] Build options
      # @option options [Symbol] :show_diffs (:all) Filter setting (:normative, :informative, :all)
      # @option options [Integer] :context_lines (3) Number of context lines
      # @option options [Integer, nil] :grouping_lines (nil) Max lines between blocks to group
      # @option options [String] :element_name ("root") Name of element being compared
      # @option options [String, nil] :file1_name (nil) Name of first file
      # @option options [String, nil] :file2_name (nil) Name of second file
      # @return [DiffReport] The complete diff report
      def self.build(diff_lines, options = {})
        new(diff_lines, options).build
      end

      def initialize(diff_lines, options = {})
        @diff_lines = diff_lines
        @show_diffs = options[:show_diffs] || :all
        @context_lines = options[:context_lines] || 3
        @grouping_lines = options[:grouping_lines]
        @element_name = options[:element_name] || "root"
        @file1_name = options[:file1_name]
        @file2_name = options[:file2_name]
      end

      def build
        # Step 1: Build blocks from lines (with filtering)
        diff_blocks = DiffBlockBuilder.build_blocks(
          @diff_lines,
          show_diffs: @show_diffs,
        )

        # Step 2: Build contexts from blocks
        diff_contexts = DiffContextBuilder.build_contexts(
          diff_blocks,
          @diff_lines,
          context_lines: @context_lines,
          grouping_lines: @grouping_lines,
        )

        # Step 3: Wrap in DiffReport
        DiffReport.new(
          element_name: @element_name,
          file1_name: @file1_name,
          file2_name: @file2_name,
          contexts: diff_contexts,
        )
      end
    end
  end
end
