# frozen_string_literal: true

module Canon
  module Diff
    # Represents a contiguous block of changes in a diff
    # A diff block is a run of consecutive change lines (-, +, !)
    class DiffBlock
      attr_reader :start_idx, :end_idx, :types, :diff_lines, :diff_node
      attr_accessor :active

      def initialize(start_idx:, end_idx:, types: [], diff_lines: [], diff_node: nil)
        @start_idx = start_idx
        @end_idx = end_idx
        @types = types
        @diff_lines = diff_lines
        @diff_node = diff_node
        @active = nil
      end

      # Number of lines in this block
      def size
        end_idx - start_idx + 1
      end

      # @return [Boolean] true if this block represents a semantic difference
      def active?
        return @active unless @active.nil?

        # If we have a diff_node, use its active status
        return diff_node.active? if diff_node

        # If we have diff_lines, check if any are active
        return diff_lines.any?(&:active?) if diff_lines&.any?

        # Default to true (treat as active if we can't determine)
        true
      end

      # @return [Boolean] true if this block represents a textual-only difference
      def inactive?
        !active?
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
          diff_lines: diff_lines.map(&:to_h),
          diff_node: diff_node&.to_h,
          active: active?,
        }
      end

      def ==(other)
        other.is_a?(DiffBlock) &&
          start_idx == other.start_idx &&
          end_idx == other.end_idx &&
          types == other.types &&
          diff_lines == other.diff_lines &&
          diff_node == other.diff_node
      end
    end
  end
end
