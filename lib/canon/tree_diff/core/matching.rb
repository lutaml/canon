# frozen_string_literal: true

module Canon
  module TreeDiff
    module Core
      # Matching stores and manages node pair matches
      #
      # A matching is a set of pairs (n1, n2) where:
      # 1. One-to-one: Each node appears in at most one pair
      # 2. Prefix closure: If (n1, n2) matched, ancestors can match
      #
      # Features:
      # - Efficient lookup: O(1) for checking if node is matched
      # - Validation: Ensures constraints are maintained
      # - Iteration: Supports enumeration of all pairs
      class Matching
        attr_reader :pairs

        # Initialize empty matching
        def initialize
          @pairs = []
          @tree1_map = {} # node => matched_node
          @tree2_map = {} # node => matched_node
        end

        # Add a matched pair
        #
        # @param node1 [TreeNode] Node from tree 1
        # @param node2 [TreeNode] Node from tree 2
        # @return [Boolean] true if added, false if violates constraints
        def add(node1, node2)
          return false unless valid_pair?(node1, node2)

          @pairs << [node1, node2]
          @tree1_map[node1] = node2
          @tree2_map[node2] = node1

          true
        end

        # Remove a matched pair
        #
        # @param node1 [TreeNode] Node from tree 1
        # @param node2 [TreeNode] Node from tree 2
        # @return [Boolean] true if removed, false if not found
        def remove(node1, node2)
          removed = @pairs.delete([node1, node2])
          return false unless removed

          @tree1_map.delete(node1)
          @tree2_map.delete(node2)

          true
        end

        # Check if a node from tree 1 is matched
        #
        # @param node [TreeNode] Node to check
        # @return [Boolean]
        def matched1?(node)
          @tree1_map.key?(node)
        end

        # Check if a node from tree 2 is matched
        #
        # @param node [TreeNode] Node to check
        # @return [Boolean]
        def matched2?(node)
          @tree2_map.key?(node)
        end

        # Get the match for a node from tree 1
        #
        # @param node [TreeNode] Node from tree 1
        # @return [TreeNode, nil] Matched node from tree 2, or nil
        def match_for1(node)
          @tree1_map[node]
        end

        # Get the match for a node from tree 2
        #
        # @param node [TreeNode] Node from tree 2
        # @return [TreeNode, nil] Matched node from tree 1, or nil
        def match_for2(node)
          @tree2_map[node]
        end

        # Get all unmatched nodes from tree 1
        #
        # @param nodes [Array<TreeNode>] All nodes from tree 1
        # @return [Array<TreeNode>]
        def unmatched1(nodes)
          nodes.reject { |node| matched1?(node) }
        end

        # Get all unmatched nodes from tree 2
        #
        # @param nodes [Array<TreeNode>] All nodes from tree 2
        # @return [Array<TreeNode>]
        def unmatched2(nodes)
          nodes.reject { |node| matched2?(node) }
        end

        # Get number of matched pairs
        #
        # @return [Integer]
        def size
          @pairs.size
        end

        # Check if matching is empty
        #
        # @return [Boolean]
        def empty?
          @pairs.empty?
        end

        # Iterate over all pairs
        #
        # @yield [node1, node2]
        def each(&block)
          @pairs.each(&block)
        end

        # Check if matching satisfies all constraints
        #
        # @return [Boolean]
        def valid?
          # Check one-to-one constraint
          return false unless one_to_one?

          # Check prefix closure constraint
          return false unless prefix_closure?

          true
        end

        # Check one-to-one constraint
        #
        # Each node appears in at most one pair
        #
        # @return [Boolean]
        def one_to_one?
          # Check tree1 map has unique values
          tree1_values = @tree1_map.values
          return false unless tree1_values.size == tree1_values.uniq.size

          # Check tree2 map has unique values
          tree2_values = @tree2_map.values
          return false unless tree2_values.size == tree2_values.uniq.size

          # Check maps are consistent
          @tree1_map.all? { |n1, n2| @tree2_map[n2] == n1 }
        end

        # Check prefix closure constraint
        #
        # If (n1, n2) matched and ancestors (a1, a2) matched,
        # then a1 is ancestor of n1 iff a2 is ancestor of n2
        #
        # @return [Boolean]
        def prefix_closure?
          @pairs.each do |node1, node2|
            # Check each ancestor pair
            node1.ancestors.each_with_index do |anc1, idx|
              anc2 = node2.ancestors[idx]

              # If ancestor matched, must be to corresponding ancestor
              if matched1?(anc1)
                match = match_for1(anc1)
                return false unless match == anc2
              end
            end
          end

          true
        end

        # Convert to array of pairs
        #
        # @return [Array<Array<TreeNode, TreeNode>>]
        def to_a
          @pairs.dup
        end

        # String representation
        #
        # @return [String]
        def to_s
          "#<Matching #{size} pairs>"
        end

        # Detailed inspection
        #
        # @return [String]
        def inspect
          pairs_str = @pairs.map do |n1, n2|
            "(#{n1.label} ↔ #{n2.label})"
          end.join(", ")

          "#<Matching [#{pairs_str}]>"
        end

        private

        # Check if a pair can be added without violating constraints
        #
        # @param node1 [TreeNode] Node from tree 1
        # @param node2 [TreeNode] Node from tree 2
        # @return [Boolean]
        def valid_pair?(node1, node2)
          # Check one-to-one constraint
          return false if matched1?(node1)
          return false if matched2?(node2)

          # Check prefix closure constraint
          # If ancestors are matched, they must be matched to each other
          node1.ancestors.each_with_index do |anc1, idx|
            # Get corresponding ancestor in tree2
            anc2_ancestors = node2.ancestors
            return false if idx >= anc2_ancestors.size

            anc2 = anc2_ancestors[idx]

            # If anc1 is matched, it must be matched to anc2
            if matched1?(anc1)
              return false unless match_for1(anc1) == anc2
            end

            # If anc2 is matched, it must be matched to anc1
            if matched2?(anc2)
              return false unless match_for2(anc2) == anc1
            end
          end

          true
        end
      end
    end
  end
end
