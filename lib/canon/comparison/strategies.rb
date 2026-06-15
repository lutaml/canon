# frozen_string_literal: true

module Canon
  module Comparison
    # Match strategy framework. Children are autoloaded — never
    # `require_relative` them.
    module Strategies
      autoload :BaseMatchStrategy,
               "canon/comparison/strategies/base_match_strategy"
      autoload :MatchStrategyFactory,
               "canon/comparison/strategies/match_strategy_factory"
      autoload :SemanticTreeMatchStrategy,
               "canon/comparison/strategies/semantic_tree_match_strategy"
    end
  end
end
