# frozen_string_literal: true

require_relative "../core/tree_node"
require_relative "../core/node_signature"
require_relative "../core/matching"

module Canon
  module TreeDiff
    module Matchers
      # SimilarityMatcher performs similarity-based matching
      #
      # Based on JATS-diff (2022) approach:
      # - Use Jaccard index for content similarity
      # - Configurable similarity threshold (default 0.95)
      # - Group candidates by signature for efficiency
      # - Extend matches for unmatched nodes
      #
      # Features:
      # - Handles text-centric documents
      # - Fuzzy matching for similar but not identical nodes
      # - Threshold-based filtering
      # - Efficient signature-based grouping
      class SimilarityMatcher
        attr_reader :tree1, :tree2, :matching, :threshold

        # Initialize matcher with two trees and existing matching
        #
        # @param tree1 [TreeNode] First tree root
        # @param tree2 [TreeNode] Second tree root
        # @param matching [Core::Matching] Existing matching from previous phase
        # @param threshold [Float] Similarity threshold (0.0 to 1.0)
        def initialize(tree1, tree2, matching, threshold: 0.95)
          @tree1 = tree1
          @tree2 = tree2
          @matching = matching
          @threshold = threshold
        end

        # Perform similarity-based matching
        #
        # @return [Core::Matching] Updated matching
        def match
          # Get unmatched nodes from both trees
          all_nodes1 = collect_nodes(tree1)
          all_nodes2 = collect_nodes(tree2)

          unmatched1 = @matching.unmatched1(all_nodes1)
          unmatched2 = @matching.unmatched2(all_nodes2)

          # Group unmatched nodes by signature for efficiency
          groups1 = group_by_signature(unmatched1)
          groups2 = group_by_signature(unmatched2)

          # For each signature group, find similar matches
          groups2.each do |sig, nodes2|
            # Find corresponding group in tree1
            nodes1 = groups1[sig] || []
            next if nodes1.empty?

            # Match nodes within this signature group
            match_group(nodes1, nodes2)
          end

          @matching
        end

        private

        # Collect all nodes from a tree
        #
        # @param root [TreeNode] Root of tree
        # @return [Array<TreeNode>]
        def collect_nodes(root)
          nodes = [root]
          nodes.concat(root.descendants)
          nodes
        end

        # Group nodes by signature
        #
        # @param nodes [Array<TreeNode>] Nodes to group
        # @return [Hash<NodeSignature, Array<TreeNode>>]
        def group_by_signature(nodes)
          nodes.group_by { |node| Core::NodeSignature.for(node) }
        end

        # Match nodes within a signature group
        #
        # @param nodes1 [Array<TreeNode>] Nodes from tree1
        # @param nodes2 [Array<TreeNode>] Nodes from tree2
        def match_group(nodes1, nodes2)
          # Create similarity matrix
          matches = []

          nodes2.each do |node2|
            next if @matching.matched2?(node2)

            # Find best match in nodes1
            best_match = nil
            best_similarity = @threshold

            nodes1.each do |node1|
              next if @matching.matched1?(node1)

              similarity = node1.similarity_to(node2)

              if similarity > best_similarity
                best_similarity = similarity
                best_match = node1
              end
            end

            # Record match if found
            if best_match
              matches << [best_match, node2, best_similarity]
            end
          end

          # Sort matches by similarity (highest first)
          matches.sort_by! { |_, _, sim| -sim }

          # Add matches in order of similarity
          matches.each do |node1, node2, _similarity|
            # Skip if already matched (by a higher-similarity match)
            next if @matching.matched1?(node1)
            next if @matching.matched2?(node2)

            # Try to add match
            @matching.add(node1, node2)
          end
        end
      end
    end
  end
end
