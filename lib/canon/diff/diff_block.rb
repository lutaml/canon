# frozen_string_literal: true

module Canon
  module Diff
    # Represents a contiguous block of changes in a diff
    # A diff block is a run of consecutive change lines (-, +, !)
    class DiffBlock
      attr_reader :start_idx, :end_idx, :types, :diff_lines, :diff_node
      attr_accessor :normative

      def initialize(start_idx:, end_idx:, types: [], diff_lines: [],
diff_node: nil)
        @start_idx = start_idx
        @end_idx = end_idx
        @types = types
        @diff_lines = diff_lines
        @diff_node = diff_node
        @normative = nil
      end

      # Number of lines in this block
      def size
        end_idx - start_idx + 1
      end

      # @return [Boolean] true if this block represents a normative difference
      def normative?
        return @normative unless @normative.nil?

        # If we have a diff_node, use its normative status
        return diff_node.normative? if diff_node

        # If we have diff_lines, check if any are normative
        return diff_lines.any?(&:normative?) if diff_lines&.any?

        # Default to true (treat as normative if we can't determine)
        true
      end

      # @return [Boolean] true if this block represents an informative-only difference
      def informative?
        !normative?
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
          normative: normative?,
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
