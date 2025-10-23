# frozen_string_literal: true

module Canon
  module Comparison
    # Encapsulates the result of a comparison operation
    # Provides methods to query equivalence based on normative diffs
    class ComparisonResult
      attr_reader :differences, :preprocessed_strings, :format, :html_version,
                  :match_options

      # @param differences [Array<DiffNode>] Array of difference nodes
      # @param preprocessed_strings [Array<String, String>] Pre-processed content for display
      # @param format [Symbol] Format type (:xml, :html, :json, :yaml)
      # @param html_version [Symbol, nil] HTML version (:html4 or :html5) for HTML format only
      # @param match_options [Hash, nil] Resolved match options used for comparison
      def initialize(differences:, preprocessed_strings:, format:,
html_version: nil, match_options: nil)
        @differences = differences
        @preprocessed_strings = preprocessed_strings
        @format = format
        @html_version = html_version
        @match_options = match_options
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
          elsif diff.is_a?(Hash)
            true
          else
            false
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
    end
  end
end
