# frozen_string_literal: true

require_relative "diff_context"

module Canon
  module Diff
    # Builds DiffContexts from DiffBlocks
    # Groups nearby blocks and adds surrounding context lines
    class DiffContextBuilder
      # Build contexts from diff blocks
      #
      # @param diff_blocks [Array<DiffBlock>] The diff blocks to group
      # @param all_lines [Array<DiffLine>] All diff lines (for context)
      # @param context_lines [Integer] Number of context lines to show
      # @param grouping_lines [Integer, nil] Max lines between blocks to group them
      # @return [Array<DiffContext>] Grouped contexts with context lines
      def self.build_contexts(diff_blocks, all_lines, context_lines: 3,
grouping_lines: nil)
        new(diff_blocks, all_lines, context_lines, grouping_lines).build
      end

      def initialize(diff_blocks, all_lines, context_lines, grouping_lines)
        @diff_blocks = diff_blocks
        @all_lines = all_lines
        @context_lines = context_lines
        @grouping_lines = grouping_lines
      end

      def build
        return [] if @diff_blocks.empty?

        # Group nearby blocks if grouping_lines is specified
        grouped_blocks = if @grouping_lines
                           group_nearby_blocks(@diff_blocks, @grouping_lines)
                         else
                           @diff_blocks.map { |block| [block] }
                         end

        # Create contexts with context lines
        contexts = grouped_blocks.map do |block_group|
          create_context_for_blocks(block_group)
        end

        # Merge overlapping contexts to avoid duplicate line display
        contexts = merge_overlapping_contexts(contexts)

        # Filter out all-informative contexts if show_diffs was :normative
        # Note: The filtering based on show_diffs happens at the block level
        # in DiffBlockBuilder, so we don't need to re-filter here.
        # However, we should filter out contexts that have NO blocks
        # (which could happen if all blocks were filtered out)
        contexts.reject { |ctx| ctx.blocks.empty? }
      end

      private

      # Merge overlapping contexts into single contexts
      # When contexts have overlapping line ranges, combine them
      def merge_overlapping_contexts(contexts)
        return contexts if contexts.empty?

        # Sort by start_idx
        sorted = contexts.sort_by(&:start_idx)
        merged = [sorted.first]

        sorted[1..].each do |context|
          last = merged.last

          # Check if contexts overlap (including touching contexts)
          if context.start_idx <= last.end_idx + 1
            # Merge: extend the range and combine blocks
            new_end = [last.end_idx, context.end_idx].max
            combined_blocks = (last.blocks + context.blocks).uniq

            # Extract combined lines
            combined_lines = @all_lines[last.start_idx..new_end]

            # Replace last context with merged one
            merged[-1] = DiffContext.new(
              start_line: last.start_idx,
              end_line: new_end,
              blocks: combined_blocks,
              lines: combined_lines,
              normative: last.normative? || context.normative?,
            )
          else
            # No overlap, add as separate context
            merged << context
          end
        end

        merged
      end

      # Group blocks that are close together
      def group_nearby_blocks(blocks, max_gap)
        return [] if blocks.empty?

        groups = []
        current_group = [blocks.first]

        blocks[1..].each do |block|
          prev_block = current_group.last
          gap = block.start_idx - prev_block.end_idx - 1

          if gap <= max_gap
            # Close enough, add to current group
            current_group << block
          else
            # Too far apart, start new group
            groups << current_group
            current_group = [block]
          end
        end

        # Don't forget the last group
        groups << current_group unless current_group.empty?
        groups
      end

      # Create a context for a group of blocks
      def create_context_for_blocks(block_group)
        first_block = block_group.first
        last_block = block_group.last

        # Calculate context range
        context_start = [first_block.start_idx - @context_lines, 0].max
        context_end = [last_block.end_idx + @context_lines,
                       @all_lines.length - 1].min

        # Extract lines for this context
        context_lines = @all_lines[context_start..context_end]

        # Determine if context is normative
        # A context is normative if ANY of its blocks are normative
        normative = block_group.any?(&:normative?)

        DiffContext.new(
          start_line: context_start,
          end_line: context_end,
          blocks: block_group,
          lines: context_lines,
          normative: normative,
        )
      end
    end
  end
end
