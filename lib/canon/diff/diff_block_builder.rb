# frozen_string_literal: true

require_relative "diff_block"

module Canon
  module Diff
    # Builds DiffBlocks from DiffLines
    # Handles grouping of contiguous changed lines and filtering by normative/informative
    class DiffBlockBuilder
      # Build diff blocks from diff lines
      #
      # @param diff_lines [Array<DiffLine>] The diff lines to process
      # @param show_diffs [Symbol] Filter setting (:normative, :informative, :all)
      # @return [Array<DiffBlock>] Filtered diff blocks
      def self.build_blocks(diff_lines, show_diffs: :all)
        new(diff_lines, show_diffs).build
      end

      def initialize(diff_lines, show_diffs)
        @diff_lines = diff_lines
        @show_diffs = show_diffs
      end

      def build
        # Group contiguous changed lines into blocks
        blocks = group_into_blocks

        # Filter blocks based on show_diffs setting
        filter_blocks(blocks)
      end

      private

      # Group contiguous changed lines into DiffBlock objects
      def group_into_blocks
        blocks = []
        current_block_lines = []
        current_start_idx = nil

        @diff_lines.each_with_index do |line, idx|
          if line.unchanged?
            # End current block if any
            if !current_block_lines.empty?
              blocks << create_block(current_start_idx, idx - 1,
                                     current_block_lines)
              current_block_lines = []
              current_start_idx = nil
            end
          else
            # Start or continue block
            current_start_idx = idx if current_start_idx.nil?
            current_block_lines << line
          end
        end

        # Don't forget last block
        unless current_block_lines.empty?
          blocks << create_block(current_start_idx,
                                 @diff_lines.length - 1,
                                 current_block_lines)
        end

        blocks
      end

      # Create a DiffBlock from lines
      def create_block(start_idx, end_idx, diff_lines)
        # Determine types from diff_lines
        types = diff_lines.map(&:type).uniq.map do |t|
          case t
          when :added then "+"
          when :removed then "-"
          when :changed then "!"
          end
        end.compact

        # Create block
        block = DiffBlock.new(
          start_idx: start_idx,
          end_idx: end_idx,
          types: types,
          diff_lines: diff_lines,
        )

        # Determine if block is normative
        # A block is normative if ANY of its lines are normative
        block.normative = diff_lines.any?(&:normative?)

        block
      end

      # Filter blocks based on show_diffs setting
      def filter_blocks(blocks)
        case @show_diffs
        when :normative
          blocks.select(&:normative?)
        when :informative
          blocks.select(&:informative?)
        else # :all
          blocks
        end
      end
    end
  end
end
