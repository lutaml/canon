# frozen_string_literal: true

require_relative "base_match_strategy"

module Canon
  module Comparison
    module Strategies
      # Factory for creating match strategies
      #
      # Selects the appropriate match strategy based on match options.
      # This provides a single point for strategy instantiation and enables
      # easy extension with new matching algorithms.
      #
      # @example Create a strategy
      #   strategy = MatchStrategyFactory.create(
      #     format: :xml,
      #     match_options: { semantic_diff: true }
      #   )
      #   differences = strategy.match(doc1, doc2)
      #
      class MatchStrategyFactory
        # Create appropriate match strategy
        #
        # Examines match options to determine which strategy to use:
        # - If semantic_diff is enabled: SemanticTreeMatchStrategy
        # - Otherwise (default): DomMatchStrategy
        #
        # Future strategies can be added here by checking additional
        # options and returning the appropriate strategy class.
        #
        # @param format [Symbol] Document format (:xml, :html, :json, :yaml)
        # @param match_options [Hash] Match options
        # @option match_options [Boolean] :semantic_diff Use semantic tree matching
        # @return [BaseMatchStrategy] Instantiated strategy
        #
        # @example DOM matching (default)
        #   strategy = MatchStrategyFactory.create(
        #     format: :xml,
        #     match_options: {}
        #   )
        #   # Returns DomMatchStrategy
        #
        # @example Semantic tree matching
        #   strategy = MatchStrategyFactory.create(
        #     format: :xml,
        #     match_options: { semantic_diff: true }
        #   )
        #   # Returns SemanticTreeMatchStrategy
        #
        def self.create(format:, match_options:)
          # Check for semantic diff option
          if match_options[:semantic_diff]
            require_relative "semantic_tree_match_strategy"
            SemanticTreeMatchStrategy.new(format: format,
                                          match_options: match_options)
          else
            # Default to DOM matching
            require_relative "dom_match_strategy"
            DomMatchStrategy.new(format: format, match_options: match_options)
          end

          # Future: Add more strategies here
          # Example:
          # elsif match_options[:hybrid_diff]
          #   require_relative "hybrid_match_strategy"
          #   HybridMatchStrategy.new(format, match_options)
          # elsif match_options[:fuzzy_diff]
          #   require_relative "fuzzy_match_strategy"
          #   FuzzyMatchStrategy.new(format, match_options)
        end
      end
    end
  end
end
