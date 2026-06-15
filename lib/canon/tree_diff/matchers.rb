# frozen_string_literal: true

module Canon
  module TreeDiff
    # Tree-matching strategies — hash-based, similarity-based,
    # structural propagation, and the universal fallback.
    module Matchers
      autoload :HashMatcher, "canon/tree_diff/matchers/hash_matcher"
      autoload :SimilarityMatcher, "canon/tree_diff/matchers/similarity_matcher"
      autoload :StructuralPropagator,
               "canon/tree_diff/matchers/structural_propagator"
      autoload :UniversalMatcher, "canon/tree_diff/matchers/universal_matcher"
    end
  end
end
