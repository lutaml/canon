# frozen_string_literal: true

module Canon
  module Comparison
    # Encapsulates the result of running both DOM and Tree diff algorithms
    # Provides unified interface while preserving individual results
    class CombinedComparisonResult
      attr_reader :dom_result, :tree_result, :decision_algorithm

      # @param dom_result [ComparisonResult] Result from DOM diff algorithm
      # @param tree_result [ComparisonResult] Result from Tree diff algorithm
      # @param decision_algorithm [Symbol] Which algorithm to use for pass/fail decision (:dom or :semantic)
      def initialize(dom_result, tree_result, decision_algorithm: :dom)
        @dom_result = dom_result
        @tree_result = tree_result
        @decision_algorithm = decision_algorithm
      end

      # Check if documents are semantically equivalent using the decision algorithm
      #
      # @return [Boolean] true if the decision algorithm reports equivalence
      def equivalent?
        case @decision_algorithm
        when :semantic
          @tree_result.equivalent?
        else # :dom (default)
          @dom_result.equivalent?
        end
      end

      # Get combined differences from both algorithms
      #
      # @return [Array<DiffNode>] Combined differences from both algorithms
      def differences
        @dom_result.differences + @tree_result.differences
      end

      # Get preprocessed strings (use DOM result as primary)
      #
      # @return [Array<String, String>] Preprocessed content for display
      def preprocessed_strings
        @dom_result.preprocessed_strings
      end

      # Get format (both should be the same)
      #
      # @return [Symbol] Format type (:xml, :html, :json, :yaml)
      def format
        @dom_result.format
      end

      # Get HTML version (both should be the same)
      #
      # @return [Symbol, nil] HTML version (:html4 or :html5) for HTML format only
      def html_version
        @dom_result.html_version
      end

      # Get match options (use DOM result as primary)
      #
      # @return [Hash, nil] Resolved match options used for comparison
      def match_options
        @dom_result.match_options
      end

      # Combined result uses :both as algorithm identifier
      #
      # @return [Symbol] Always returns :both
      def algorithm
        :both
      end

      # Check if there are any normative diffs in either algorithm
      #
      # @return [Boolean] true if at least one normative diff exists
      def has_normative_diffs?
        @dom_result.has_normative_diffs? || @tree_result.has_normative_diffs?
      end

      # Check if there are any informative diffs in either algorithm
      #
      # @return [Boolean] true if at least one informative diff exists
      def has_informative_diffs?
        @dom_result.has_informative_diffs? || @tree_result.has_informative_diffs?
      end

      # Get all normative differences from both algorithms
      #
      # @return [Array<DiffNode>] Normative differences only
      def normative_differences
        @dom_result.normative_differences + @tree_result.normative_differences
      end

      # Get all informative differences from both algorithms
      #
      # @return [Array<DiffNode>] Informative differences only
      def informative_differences
        @dom_result.informative_differences + @tree_result.informative_differences
      end

      # Get tree diff operations (only from tree result)
      #
      # @return [Array<Operation>] Array of tree diff operations
      def operations
        @tree_result.operations
      end

      # Iterate over both results for sequential rendering
      #
      # @yield [ComparisonResult] Yields DOM result then Tree result
      def each_result
        yield @dom_result
        yield @tree_result
      end

      # Get both results as an array
      #
      # @return [Array<ComparisonResult, ComparisonResult>] [dom_result, tree_result]
      def results
        [@dom_result, @tree_result]
      end
    end
  end
end
