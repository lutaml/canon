# frozen_string_literal: true

require_relative "../core/tree_node"
require_relative "../core/node_weight"
require_relative "../core/matching"

module Canon
  module TreeDiff
    module Matchers
      # StructuralPropagator extends matches using structural relationships
      #
      # Based on XyDiff/Cobena (2002, INRIA) propagation strategies:
      # - Bottom-up: Match parents of matched children
      # - Top-down: Match children of matched parents (lazy propagation)
      #
      # Propagation depth formula: 1 + (W / W₀)
      # where W = node weight, W₀ = base weight threshold
      #
      # Features:
      # - Conservative propagation (only when safe)
      # - Weight-based depth control
      # - Handles unique child labels
      # - Preserves matching constraints
      class StructuralPropagator
        attr_reader :tree1, :tree2, :matching

        # Base weight threshold for propagation depth
        BASE_WEIGHT_THRESHOLD = 10.0

        # Initialize propagator with trees and existing matching
        #
        # @param tree1 [TreeNode] First tree root
        # @param tree2 [TreeNode] Second tree root
        # @param matching [Core::Matching] Existing matching
        def initialize(tree1, tree2, matching)
          @tree1 = tree1
          @tree2 = tree2
          @matching = matching
        end

        # Perform structural propagation
        #
        # @return [Core::Matching] Updated matching
        def propagate
          # Phase 1: Bottom-up propagation
          propagate_bottom_up

          # Phase 2: Top-down propagation
          propagate_top_down

          @matching
        end

        private

        # Bottom-up propagation: match parents of matched children
        #
        # If multiple children are matched and parents are compatible,
        # match the parents too
        def propagate_bottom_up
          # Get all matched pairs
          matched_pairs = @matching.to_a

          # Process in reverse (children before parents)
          matched_pairs.reverse.each do |node1, node2|
            propagate_to_parent(node1, node2)
          end
        end

        # Try to match parents of a matched pair
        #
        # @param node1 [TreeNode] Node from tree1
        # @param node2 [TreeNode] Node from tree2
        def propagate_to_parent(node1, node2)
          parent1 = node1.parent
          parent2 = node2.parent

          return unless parent1 && parent2
          return if @matching.matched1?(parent1)
          return if @matching.matched2?(parent2)

          # Check if parents are compatible
          return unless parents_compatible?(parent1, parent2)

          # Check propagation depth
          weight1 = Core::NodeWeight.for(parent1).value
          depth = propagation_depth(weight1)

          return if depth < 1

          # Try to match parents
          @matching.add(parent1, parent2)
        end

        # Check if two parent nodes are compatible for matching
        #
        # Parents are compatible if:
        # - Same label
        # - Similar attributes
        # - Matched children align properly
        #
        # @param parent1 [TreeNode] Parent from tree1
        # @param parent2 [TreeNode] Parent from tree2
        # @return [Boolean]
        def parents_compatible?(parent1, parent2)
          # Must have same label
          return false unless parent1.label == parent2.label

          # Must have similar attributes (allow some differences)
          attr_sim = 1.0 - parent1.attribute_difference(parent2)
          return false if attr_sim < 0.5

          # Check that matched children align
          matched_children_align?(parent1, parent2)
        end

        # Check if matched children of two parents align
        #
        # @param parent1 [TreeNode] Parent from tree1
        # @param parent2 [TreeNode] Parent from tree2
        # @return [Boolean]
        def matched_children_align?(parent1, parent2)
          # Get matched children
          matched1 = parent1.children.select { |c| @matching.matched1?(c) }
          matched2 = parent2.children.select { |c| @matching.matched2?(c) }

          return false if matched1.empty?

          # Check each matched child in parent1
          matched1.all? do |child1|
            # Get its match in tree2
            child2 = @matching.match_for1(child1)

            # Check if child2 is actually a child of parent2
            parent2.children.include?(child2)
          end
        end

        # Top-down propagation: match children of matched parents
        #
        # If parents are matched and have unique corresponding children,
        # match those children too
        def propagate_top_down
          # Get all matched pairs
          matched_pairs = @matching.to_a

          # Process each matched pair
          matched_pairs.each do |node1, node2|
            propagate_to_children(node1, node2)
          end
        end

        # Try to match children of a matched pair
        #
        # @param node1 [TreeNode] Node from tree1
        # @param node2 [TreeNode] Node from tree2
        def propagate_to_children(node1, node2)
          # Get unmatched children
          unmatched1 = node1.children.reject { |c| @matching.matched1?(c) }
          unmatched2 = node2.children.reject { |c| @matching.matched2?(c) }

          return if unmatched1.empty? || unmatched2.empty?

          # Find unique label correspondences
          find_unique_matches(unmatched1, unmatched2)
        end

        # Find and match children with unique labels
        #
        # If a label appears exactly once in each parent's unmatched children,
        # match those children
        #
        # @param children1 [Array<TreeNode>] Unmatched children from tree1
        # @param children2 [Array<TreeNode>] Unmatched children from tree2
        def find_unique_matches(children1, children2)
          # Group children by label
          by_label1 = children1.group_by(&:label)
          by_label2 = children2.group_by(&:label)

          # Find labels that appear exactly once in both
          by_label1.each do |label, nodes1|
            next unless nodes1.size == 1

            nodes2 = by_label2[label]
            next unless nodes2 && nodes2.size == 1

            child1 = nodes1.first
            child2 = nodes2.first

            # Check propagation depth
            weight1 = Core::NodeWeight.for(child1).value
            depth = propagation_depth(weight1)

            next if depth < 1

            # Try to match
            @matching.add(child1, child2)
          end
        end

        # Calculate propagation depth based on node weight
        #
        # Formula: 1 + floor(W / W₀)
        # where W = node weight, W₀ = base threshold
        #
        # @param weight [Float] Node weight
        # @return [Integer] Propagation depth
        def propagation_depth(weight)
          1 + (weight / BASE_WEIGHT_THRESHOLD).floor
        end
      end
    end
  end
end
