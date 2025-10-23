# frozen_string_literal: true

module Canon
  module TreeDiff
    module Matchers
      # UniversalMatcher orchestrates the complete matching process by combining
      # hash-based, similarity-based, and structural propagation matching strategies.
      #
      # This is the main entry point for tree matching and follows a multi-phase
      # pipeline approach:
      #
      # Phase 1: Hash Matching (XyDiff BULD)
      #   - Exact signature matching for identical subtrees
      #   - O(n log n) complexity via priority queue
      #   - Processes heaviest nodes first
      #
      # Phase 2: Similarity Matching (JATS-diff)
      #   - Content-based similarity via Jaccard index
      #   - Configurable threshold (default 0.95)
      #   - Groups by signature for efficiency
      #
      # Phase 3: Structural Propagation (XyDiff)
      #   - Bottom-up: match parents of matched children
      #   - Top-down: match children of matched parents
      #   - Adaptive propagation depth based on weight
      #
      # @example Basic usage
      #   matcher = UniversalMatcher.new
      #   matching = matcher.match(tree1, tree2)
      #   puts "Matched #{matching.size} nodes"
      #
      # @example With custom options
      #   matcher = UniversalMatcher.new(
      #     similarity_threshold: 0.9,
      #     enable_propagation: false
      #   )
      #   matching = matcher.match(tree1, tree2)
      #
      class UniversalMatcher
        # Default options for the matching process
        DEFAULT_OPTIONS = {
          # Minimum Jaccard similarity for content matching
          similarity_threshold: 0.95,

          # Enable hash-based exact matching
          enable_hash_matching: true,

          # Enable similarity-based matching
          enable_similarity_matching: true,

          # Enable structural propagation
          enable_propagation: true,

          # Maximum propagation depth (nil = adaptive)
          max_propagation_depth: nil,

          # Minimum weight for propagation
          min_propagation_weight: 2.0
        }.freeze

        attr_reader :options, :statistics

        # Initialize a new UniversalMatcher
        #
        # @param options [Hash] Configuration options
        # @option options [Float] :similarity_threshold (0.95)
        #   Minimum similarity for content matching
        # @option options [Boolean] :enable_hash_matching (true)
        #   Enable hash-based exact matching
        # @option options [Boolean] :enable_similarity_matching (true)
        #   Enable similarity-based matching
        # @option options [Boolean] :enable_propagation (true)
        #   Enable structural propagation
        # @option options [Integer, nil] :max_propagation_depth (nil)
        #   Maximum propagation depth (nil = adaptive)
        # @option options [Float] :min_propagation_weight (2.0)
        #   Minimum weight for propagation
        def initialize(options = {})
          @options = DEFAULT_OPTIONS.merge(options)
          @statistics = {}
        end

        # Match two trees and return a Matching object
        #
        # @param tree1 [TreeNode] First tree root
        # @param tree2 [TreeNode] Second tree root
        # @return [Matching] Matching object with all matched pairs
        def match(tree1, tree2)
          reset_statistics(tree1, tree2)

          matching = Core::Matching.new

          # Phase 1: Hash-based exact matching
          if @options[:enable_hash_matching]
            hash_matching_phase(tree1, tree2, matching)
          end

          # Phase 2: Similarity-based matching
          if @options[:enable_similarity_matching]
            similarity_matching_phase(tree1, tree2, matching)
          end

          # Phase 3: Structural propagation
          if @options[:enable_propagation]
            propagation_phase(tree1, tree2, matching)
          end

          finalize_statistics(matching)
          matching
        end

        private

        # Reset statistics for a new matching process
        #
        # @param tree1 [TreeNode] First tree root
        # @param tree2 [TreeNode] Second tree root
        def reset_statistics(tree1, tree2)
          @statistics = {
            tree1_nodes: count_nodes(tree1),
            tree2_nodes: count_nodes(tree2),
            hash_matches: 0,
            similarity_matches: 0,
            propagation_matches: 0,
            total_matches: 0,
            match_ratio_tree1: 0.0,
            match_ratio_tree2: 0.0,
            phases_executed: []
          }
        end

        # Execute hash-based matching phase
        #
        # @param tree1 [TreeNode] First tree root
        # @param tree2 [TreeNode] Second tree root
        # @param matching [Matching] Matching object to update
        def hash_matching_phase(tree1, tree2, matching)
          @statistics[:phases_executed] << :hash_matching

          hash_matcher = HashMatcher.new(tree1, tree2)
          temp_matching = hash_matcher.match

          # Transfer matches to the main matching object
          temp_matching.pairs.each do |node1, node2|
            matching.add(node1, node2)
          end

          @statistics[:hash_matches] = temp_matching.size
        end

        # Execute similarity-based matching phase
        #
        # @param tree1 [TreeNode] First tree root
        # @param tree2 [TreeNode] Second tree root
        # @param matching [Matching] Matching object to update
        def similarity_matching_phase(tree1, tree2, matching)
          @statistics[:phases_executed] << :similarity_matching

          before_count = matching.size

          similarity_matcher = SimilarityMatcher.new(
            tree1,
            tree2,
            matching,
            threshold: @options[:similarity_threshold]
          )
          similarity_matcher.match

          @statistics[:similarity_matches] = matching.size - before_count
        end

        # Execute structural propagation phase
        #
        # @param tree1 [TreeNode] First tree root
        # @param tree2 [TreeNode] Second tree root
        # @param matching [Matching] Matching object to update
        def propagation_phase(tree1, tree2, matching)
          @statistics[:phases_executed] << :propagation

          before_count = matching.size

          propagator = StructuralPropagator.new(tree1, tree2, matching)
          propagator.propagate

          @statistics[:propagation_matches] = matching.size - before_count
        end

        # Finalize statistics after matching is complete
        #
        # @param matching [Matching] Final matching object
        def finalize_statistics(matching)
          @statistics[:total_matches] = matching.size

          # Calculate match ratios
          if @statistics[:tree1_nodes] > 0
            @statistics[:match_ratio_tree1] =
              matching.size.to_f / @statistics[:tree1_nodes]
          end

          if @statistics[:tree2_nodes] > 0
            @statistics[:match_ratio_tree2] =
              matching.size.to_f / @statistics[:tree2_nodes]
          end
        end

        # Count total nodes in a tree
        #
        # @param node [TreeNode] Tree root
        # @return [Integer] Total node count
        def count_nodes(node)
          count = 1
          node.children.each do |child|
            count += count_nodes(child)
          end
          count
        end
      end
    end
  end
end
