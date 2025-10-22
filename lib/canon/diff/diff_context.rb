# frozen_string_literal: true

require_relative "diff_block"

module Canon
  module Diff
    # Represents a context - a group of diff blocks with surrounding context lines
    # A context is created by grouping nearby diff blocks and expanding with context lines
    class DiffContext
      attr_reader :start_idx, :end_idx, :blocks, :lines
      attr_accessor :normative

      def initialize(start_line: nil, end_line: nil, start_idx: nil,
                     end_idx: nil, blocks: [], lines: [], normative: nil)
        # Support both old (start_idx/end_idx) and new (start_line/end_line) signatures
        @start_idx = start_line || start_idx
        @end_idx = end_line || end_idx
        @blocks = blocks
        @lines = lines
        @normative = normative
      end

      # @return [Boolean] true if this context contains normative diffs
      def normative?
        @normative == true
      end

      # @return [Boolean] true if this context contains only informative diffs
      def informative?
        @normative == false
      end

      # Number of lines in this context (including context lines)
      def size
        end_idx - start_idx + 1
      end

      # Number of diff blocks in this context
      def block_count
        blocks.length
      end

      # Check if this context contains changes of a specific type
      def includes_type?(type)
        blocks.any? { |block| block.includes_type?(type) }
      end

      # Calculate gap to another context
      def gap_to(other_context)
        return Float::INFINITY if other_context.nil?
        return 0 if overlaps?(other_context)

        if other_context.start_idx > end_idx
          other_context.start_idx - end_idx - 1
        elsif start_idx > other_context.end_idx
          start_idx - other_context.end_idx - 1
        else
          0
        end
      end

      # Check if this context overlaps with another
      def overlaps?(other_context)
        return false if other_context.nil?

        !(end_idx < other_context.start_idx || start_idx > other_context.end_idx)
      end

      def to_h
        {
          start_idx: start_idx,
          end_idx: end_idx,
          blocks: blocks.map(&:to_h),
        }
      end

      def ==(other)
        other.is_a?(DiffContext) &&
          start_idx == other.start_idx &&
          end_idx == other.end_idx &&
          blocks == other.blocks
      end
    end
  end
end
