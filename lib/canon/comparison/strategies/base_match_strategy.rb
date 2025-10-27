# frozen_string_literal: true

module Canon
  module Comparison
    module Strategies
      # Abstract base class for match strategies
      #
      # All match strategies must inherit from this class and implement:
      # - match(doc1, doc2) → Array<DiffNode>
      # - preprocess_for_display(doc1, doc2) → [String, String]
      #
      # This provides a common interface for different matching algorithms,
      # enabling the Strategy Pattern for extensible comparison methods.
      #
      # @example Create a custom match strategy
      #   class MyMatchStrategy < BaseMatchStrategy
      #     def match(doc1, doc2)
      #       # Custom matching logic
      #       # Must return Array<Canon::Diff::DiffNode>
      #     end
      #
      #     def preprocess_for_display(doc1, doc2)
      #       # Format documents for diff display
      #       # Must return [String, String]
      #     end
      #   end
      #
      class BaseMatchStrategy
        attr_reader :format, :match_options

        # Initialize strategy
        #
        # @param format [Symbol] Document format (:xml, :html, :json, :yaml)
        # @param match_options [Hash] Match options for comparison
        def initialize(format:, match_options:)
          @format = format
          @match_options = match_options
        end

        # Perform matching and return DiffNodes
        #
        # This is the core method that implements the matching algorithm.
        # All strategies must implement this to produce DiffNodes that
        # flow through the standard diff rendering pipeline.
        #
        # @param doc1 [Object] First document
        # @param doc2 [Object] Second document
        # @return [Array<Canon::Diff::DiffNode>] Array of differences
        # @raise [NotImplementedError] If not implemented by subclass
        def match(doc1, doc2)
          raise NotImplementedError,
                "#{self.class} must implement #match(doc1, doc2)"
        end

        # Preprocess documents for display in diff output
        #
        # This method formats the documents into strings suitable for
        # line-by-line diff display. The format must be consistent across
        # all strategies for the same format to ensure the diff rendering
        # pipeline produces correct output.
        #
        # @param doc1 [Object] First document
        # @param doc2 [Object] Second document
        # @return [Array<String>] Preprocessed [doc1_string, doc2_string]
        # @raise [NotImplementedError] If not implemented by subclass
        def preprocess_for_display(doc1, doc2)
          raise NotImplementedError,
                "#{self.class} must implement #preprocess_for_display(doc1, doc2)"
        end

        # Optional metadata to include in ComparisonResult
        #
        # Subclasses can override this to provide algorithm-specific
        # metadata such as statistics, configuration, etc.
        #
        # @return [Hash] Additional metadata
        def metadata
          {}
        end

        # Algorithm name derived from class name
        #
        # Automatically generates algorithm identifier from class name.
        # For example:
        # - DomMatchStrategy → :dom
        # - SemanticTreeMatchStrategy → :semantic_tree
        #
        # @return [Symbol] Algorithm identifier
        def algorithm_name
          self.class.name.split("::").last
            .gsub("MatchStrategy", "")
            .gsub(/([A-Z])/, '_\1')
            .downcase[1..]
            .to_sym
        end
      end
    end
  end
end
