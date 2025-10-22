# frozen_string_literal: true

module Canon
  module Comparison
    # Encapsulates the result of a comparison operation
    # Provides methods to query equivalence based on active diffs
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

      # Check if documents are semantically equivalent (no active diffs)
      #
      # @return [Boolean] true if no active differences present
      def equivalent?
        !has_active_diffs?
      end

      # Check if there are any active (semantic) differences
      # Includes both DiffNode objects marked as active AND legacy Hash differences
      # (which represent structural differences like element name mismatches)
      #
      # @return [Boolean] true if at least one active diff exists
      def has_active_diffs?
        @differences.any? do |diff|
          # DiffNode objects - check if marked active
          if diff.is_a?(Canon::Diff::DiffNode)
            diff.active?
          # Legacy Hash format - always considered active (structural differences)
          elsif diff.is_a?(Hash)
            true
          else
            false
          end
        end
      end

      # Check if there are any inactive (textual-only) differences
      #
      # @return [Boolean] true if at least one inactive diff exists
      def has_inactive_diffs?
        @differences.any? do |diff|
          diff.is_a?(Canon::Diff::DiffNode) && diff.inactive?
        end
      end

      # Get all active differences
      #
      # @return [Array<DiffNode>] Active differences only
      def active_differences
        @differences.select do |diff|
          diff.is_a?(Canon::Diff::DiffNode) && diff.active?
        end
      end

      # Get all inactive differences
      #
      # @return [Array<DiffNode>] Inactive differences only
      def inactive_differences
        @differences.select do |diff|
          diff.is_a?(Canon::Diff::DiffNode) && diff.inactive?
        end
      end
    end
  end
end
