# frozen_string_literal: true

module Canon
  module Diff
    # Represents a contiguous block of changes in a diff
    # A diff block is a run of consecutive change lines (-, +, !)
    class DiffBlock
      attr_reader :start_idx, :end_idx, :types

      def initialize(start_idx:, end_idx:, types: [])
        @start_idx = start_idx
        @end_idx = end_idx
        @types = types
      end

      # Number of lines in this block
      def size
        end_idx - start_idx + 1
      end

      # Check if this block contains a specific type of change
      def includes_type?(type)
        types.include?(type)
      end

      def to_h
        {
          start_idx: start_idx,
          end_idx: end_idx,
          types: types,
        }
      end

      def ==(other)
        other.is_a?(DiffBlock) &&
          start_idx == other.start_idx &&
          end_idx == other.end_idx &&
          types == other.types
      end
    end
  end
end
