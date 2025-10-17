# frozen_string_literal: true

module Canon
  module Diff
    # Represents a complete diff report containing multiple contexts
    #
    # A DiffReport is the top-level container for diff results between two
    # documents. It contains multiple DiffContext objects, each representing
    # a region with changes and surrounding context lines.
    #
    # @example Creating a diff report
    #   report = DiffReport.new(
    #     element_name: "root",
    #     file1_name: "expected.xml",
    #     file2_name: "actual.xml"
    #   )
    #   report.add_context(context1)
    #   report.add_context(context2)
    #
    # @attr_reader element_name [String] name of the root element being compared
    # @attr_reader file1_name [String] name/path of the first file
    # @attr_reader file2_name [String] name/path of the second file
    # @attr_reader contexts [Array<DiffContext>] array of diff contexts
    class DiffReport
      attr_reader :element_name, :file1_name, :file2_name, :contexts

      # Initialize a new diff report
      #
      # @param element_name [String] name of the root element being compared
      # @param file1_name [String, nil] name/path of the first file
      # @param file2_name [String, nil] name/path of the second file
      # @param contexts [Array<DiffContext>] initial array of contexts
      def initialize(element_name:, file1_name: nil, file2_name: nil,
                     contexts: [])
        @element_name = element_name
        @file1_name = file1_name
        @file2_name = file2_name
        @contexts = contexts
      end

      # Add a context to the report
      #
      # @param context [DiffContext] the context to add
      # @return [self] returns self for method chaining
      def add_context(context)
        @contexts << context
        self
      end

      # Get the total number of contexts in the report
      #
      # @return [Integer] number of contexts
      def context_count
        contexts.length
      end

      # Get the total number of diff blocks across all contexts
      #
      # @return [Integer] total number of blocks
      def block_count
        contexts.sum(&:block_count)
      end

      # Get the total number of changes (sum of all block sizes)
      #
      # @return [Integer] total number of changed lines
      def change_count
        contexts.sum do |context|
          context.blocks.sum(&:size)
        end
      end

      # Check if the report has any differences
      #
      # @return [Boolean] true if there are any contexts with differences
      def has_differences?
        !contexts.empty?
      end

      # Check if the report contains a specific change type
      #
      # @param type [String] the change type to check for ('+', '-', '!')
      # @return [Boolean] true if any context includes this type
      def includes_type?(type)
        contexts.any? { |context| context.includes_type?(type) }
      end

      # Filter contexts by change type
      #
      # @param type [String] the change type to filter by ('+', '-', '!')
      # @return [Array<DiffContext>] contexts that include the given type
      def contexts_with_type(type)
        contexts.select { |context| context.includes_type?(type) }
      end

      # Get summary statistics about the diff
      #
      # @return [Hash] hash with keys: :contexts, :blocks, :changes
      def summary
        {
          contexts: context_count,
          blocks: block_count,
          changes: change_count,
        }
      end

      # Convert to hash representation
      #
      # @return [Hash] hash representation of the report
      def to_h
        {
          element_name: element_name,
          file1_name: file1_name,
          file2_name: file2_name,
          contexts: contexts.map(&:to_h),
          summary: summary,
        }
      end

      # Compare equality with another report
      #
      # @param other [DiffReport] the report to compare with
      # @return [Boolean] true if reports are equal
      def ==(other)
        other.is_a?(DiffReport) &&
          element_name == other.element_name &&
          file1_name == other.file1_name &&
          file2_name == other.file2_name &&
          contexts == other.contexts
      end
    end
  end
end
