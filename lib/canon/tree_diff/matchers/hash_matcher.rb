# frozen_string_literal: true

require_relative "../core/tree_node"
require_relative "../core/node_signature"
require_relative "../core/node_weight"
require_relative "../core/matching"
require_relative "../core/attribute_comparator"

module Canon
  module TreeDiff
    module Matchers
      # HashMatcher performs fast exact subtree matching
      #
      # Based on XyDiff/Cobena (2002, INRIA) BULD algorithm:
      # - Build signature map for tree1
      # - Process nodes by weight (heaviest first)
      # - Match identical subtrees via signature lookup
      # - Propagate matches to ancestors
      #
      # Complexity: O(n log n) where n is number of nodes
      #
      # Features:
      # - Hash-based exact matching (O(1) lookup)
      # - Weight-based prioritization (largest subtrees first)
      # - Automatic ancestor propagation
      # - Handles both element and text nodes
      class HashMatcher
        attr_reader :tree1, :tree2, :matching, :match_options

        # Initialize matcher with two trees
        #
        # @param tree1 [TreeNode] First tree root
        # @param tree2 [TreeNode] Second tree root
        # @param options [Hash] Match options (includes text_content, attribute_order, etc.)
        def initialize(tree1, tree2, options = {})
          @tree1 = tree1
          @tree2 = tree2
          @matching = Core::Matching.new
          @signature_map = {}
          @matched_tree1 = Set.new
          @matched_tree2 = Set.new
          @options = options
          @match_options = options # Store full match options for text comparison
          @attribute_comparator = Core::AttributeComparator.new(
            attribute_order: options[:attribute_order] || :ignore,
          )
        end

        # Perform hash-based matching
        #
        # @return [Core::Matching] The resulting matching
        def match
          # Step 1: Build signature map for tree1
          build_signature_map

          # Step 2: Get all nodes from tree2 sorted by weight (heaviest first)
          tree2_nodes = collect_nodes(tree2).sort_by do |node|
            -Core::NodeWeight.for(node).value
          end

          # Step 3: Match nodes from tree2 to tree1 via signatures
          tree2_nodes.each do |node2|
            next if @matched_tree2.include?(node2)

            match_node(node2)
          end

          @matching
        end

        private

        # Build signature map for tree1
        #
        # Maps signatures to arrays of nodes (multiple nodes can share signature)
        def build_signature_map
          collect_nodes(tree1).each do |node|
            sig = Core::NodeSignature.for(node)
            @signature_map[sig] ||= []
            @signature_map[sig] << node
          end
        end

        # Collect all nodes from a tree (depth-first)
        #
        # @param root [TreeNode] Root of tree
        # @return [Array<TreeNode>]
        def collect_nodes(root)
          nodes = [root]
          nodes.concat(root.descendants)
          nodes
        end

        # Try to match a node from tree2 to tree1
        #
        # @param node2 [TreeNode] Node from tree2
        def match_node(node2)
          sig2 = Core::NodeSignature.for(node2)

          # Find candidate nodes in tree1 with same signature
          candidates = @signature_map[sig2] || []

          # Filter to unmatched candidates
          candidates = candidates.reject { |n| @matched_tree1.include?(n) }

          return if candidates.empty?

          # Find best match among candidates
          best_match = find_best_match(node2, candidates)

          return unless best_match

          # Add match if it satisfies constraints
          if @matching.add(best_match, node2)
            @matched_tree1 << best_match
            @matched_tree2 << node2

            # Try to propagate match to ancestors
            propagate_to_ancestors(best_match, node2)
          end
        end

        # Find best match among candidates
        #
        # For exact matching, we need:
        # 1. Same signature (already filtered)
        # 2. Matching subtrees (same structure and values)
        #
        # @param node2 [TreeNode] Node from tree2
        # @param candidates [Array<TreeNode>] Candidate nodes from tree1
        # @return [TreeNode, nil]
        def find_best_match(node2, candidates)
          # For hash matching, we want exact subtree equality
          # Find first candidate that has matching subtree
          candidates.find do |node1|
            subtrees_match?(node1, node2)
          end
        end

        # Check if two subtrees match exactly
        #
        # @param node1 [TreeNode] Node from tree1
        # @param node2 [TreeNode] Node from tree2
        # @return [Boolean]
        def subtrees_match?(node1, node2)
          # Check root nodes match
          return false unless nodes_match?(node1, node2)

          # Check children count
          return false unless node1.children.size == node2.children.size

          # Check each child subtree matches
          node1.children.zip(node2.children).all? do |child1, child2|
            subtrees_match?(child1, child2)
          end
        end

        # Check if two nodes match (not including subtrees)
        #
        # Uses normalized text comparison based on match_options.
        #
        # @param node1 [TreeNode] Node from tree1
        # @param node2 [TreeNode] Node from tree2
        # @return [Boolean]
        def nodes_match?(node1, node2)
          return false unless node1.label == node2.label

          # CRITICAL FIX: Use normalized text comparison
          return false unless text_equivalent?(node1, node2)

          return false unless @attribute_comparator.equal?(node1.attributes,
                                                           node2.attributes)

          true
        end

        # Check if text values are equivalent according to match options
        #
        # Same logic as in OperationDetector for consistency.
        #
        # @param node1 [TreeNode] First node
        # @param node2 [TreeNode] Second node
        # @return [Boolean] True if text values are equivalent
        def text_equivalent?(node1, node2)
          text1 = node1.value
          text2 = node2.value

          # Both nil or empty = equivalent
          return true if (text1.nil? || text1.empty?) && (text2.nil? || text2.empty?)
          return false if (text1.nil? || text1.empty?) || (text2.nil? || text2.empty?)

          # If both normalize to empty (whitespace-only), treat as equivalent
          norm1 = normalize_text(text1)
          norm2 = normalize_text(text2)
          return true if norm1.empty? && norm2.empty?

          # Apply normalization based on match_options
          text_content_mode = @match_options[:text_content] || :normalize

          case text_content_mode
          when :strict
            text1 == text2
          when :normalize, :normalized
            norm1 == norm2
          else
            norm1 == norm2
          end
        end

        # Normalize text for comparison
        #
        # @param text [String, nil] Text to normalize
        # @return [String] Normalized text
        def normalize_text(text)
          return "" if text.nil? || text.empty?
          text.gsub(/\s+/, ' ').strip
        end

        # Propagate match to ancestors if possible
        #
        # If both nodes have parents and:
        # - Parents have same signature
        # - Parents are not yet matched
        # - All matched children align
        # Then match the parents too
        #
        # @param node1 [TreeNode] Matched node from tree1
        # @param node2 [TreeNode] Matched node from tree2
        def propagate_to_ancestors(node1, node2)
          parent1 = node1.parent
          parent2 = node2.parent

          return unless parent1 && parent2
          return if @matched_tree1.include?(parent1)
          return if @matched_tree2.include?(parent2)

          # Check if parents have same signature
          sig1 = Core::NodeSignature.for(parent1)
          sig2 = Core::NodeSignature.for(parent2)
          return unless sig1 == sig2

          # Check if parents match structurally
          return unless nodes_match?(parent1, parent2)

          # Try to match parents
          if @matching.add(parent1, parent2)
            @matched_tree1 << parent1
            @matched_tree2 << parent2

            # Recursively propagate upward
            propagate_to_ancestors(parent1, parent2)
          end
        end
      end
    end
  end
end
