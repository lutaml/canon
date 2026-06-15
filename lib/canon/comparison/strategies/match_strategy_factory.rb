# frozen_string_literal: true

module Canon
  module Comparison
    module Strategies
      # Factory for creating match strategies
      #
      # After semantic dispatch normalization, this factory is only called
      # with semantic_diff: true. DOM matching is handled directly by
      # the format comparators (XmlComparator, HtmlComparator, etc.).
      class MatchStrategyFactory
        def self.create(format:, match_options:)
          unless match_options[:semantic_diff]
            raise ArgumentError,
                  "MatchStrategyFactory requires semantic_diff: true; " \
                  "DOM matching is handled by format comparators directly"
          end

          SemanticTreeMatchStrategy.new(format: format,
                                        match_options: match_options)
        end
      end
    end
  end
end
