# frozen_string_literal: true

module Canon
  module TreeDiff
    module Operations
      # OperationDetector analyzes tree matching results to detect high-level
      # semantic operations.
      #
      # Based on research from XDiff, XyDiff, and JATS-diff, this detector
      # identifies operations in three levels:
      #
      # Level 1: Basic operations (INSERT, DELETE, UPDATE)
      # Level 2: Structural operations (MOVE)
      # Level 3: Semantic operations (MERGE, SPLIT, UPGRADE, DOWNGRADE)
      #
      # @example
      #   detector = OperationDetector.new(tree1, tree2, matching)
      #   operations = detector.detect
      #   operations.each { |op| puts op.inspect }
      #
      class OperationDetector
        attr_reader :tree1, :tree2, :matching, :operations

        # Initialize a new operation detector
        #
        # @param tree1 [TreeNode] First tree root
        # @param tree2 [TreeNode] Second tree root
        # @param matching [Matching] Matching between trees
        def initialize(tree1, tree2, matching)
          @tree1 = tree1
          @tree2 = tree2
          @matching = matching
          @operations = []
        end

        # Detect all operations
        #
        # @return [Array<Operation>] Detected operations
        def detect
          @operations = []

          # Level 1: Basic operations
          detect_inserts
          detect_deletes
          detect_updates

          # Level 2: Structural operations
          detect_moves

          # Level 3: Semantic operations
          # These require more sophisticated pattern analysis
          detect_merges
          detect_splits
          detect_upgrades
          detect_downgrades

          @operations
        end

        private

        # Detect INSERT operations (nodes in tree2 not matched in tree1)
        def detect_inserts
          all_nodes2 = collect_all_nodes(tree2)

          all_nodes2.each do |node2|
            next if @matching.matched2?(node2)

            # Find parent context
            parent2 = node2.parent
            position = parent2 ? parent2.children.index(node2) : 0

            @operations << Operation.new(
              type: :insert,
              node: node2,
              parent: parent2,
              position: position,
            )
          end
        end

        # Detect DELETE operations (nodes in tree1 not matched in tree2)
        def detect_deletes
          all_nodes1 = collect_all_nodes(tree1)

          all_nodes1.each do |node1|
            next if @matching.matched1?(node1)

            # Find parent context
            parent1 = node1.parent
            position = parent1 ? parent1.children.index(node1) : 0

            @operations << Operation.new(
              type: :delete,
              node: node1,
              parent: parent1,
              position: position,
            )
          end
        end

        # Detect UPDATE operations (matched nodes with different content)
        def detect_updates
          @matching.pairs.each do |node1, node2|
            next if nodes_identical?(node1, node2)

            # Detect what changed
            changes = detect_changes(node1, node2)

            @operations << Operation.new(
              type: :update,
              node1: node1,
              node2: node2,
              changes: changes,
            )
          end
        end

        # Detect MOVE operations (nodes that moved in the tree structure)
        def detect_moves
          @matching.pairs.each do |node1, node2|
            next unless moved?(node1, node2)

            @operations << Operation.new(
              type: :move,
              node1: node1,
              node2: node2,
              old_parent: node1.parent,
              new_parent: node2.parent,
              old_position: node1.parent&.children&.index(node1),
              new_position: node2.parent&.children&.index(node2),
            )
          end
        end

        # Check if a node moved between trees
        #
        # @param node1 [TreeNode] Node in tree1
        # @param node2 [TreeNode] Node in tree2
        # @return [Boolean]
        def moved?(node1, node2)
          # Node moved if parents don't match
          parent1 = node1.parent
          parent2 = node2.parent

          return false if parent1.nil? && parent2.nil?
          return true if parent1.nil? || parent2.nil?

          # Check if parents match
          matched_parent2 = @matching.match_for1(parent1)
          matched_parent2 != parent2
        end

        # Check if two nodes are identical
        #
        # @param node1 [TreeNode] First node
        # @param node2 [TreeNode] Second node
        # @return [Boolean]
        def nodes_identical?(node1, node2)
          node1.label == node2.label &&
            node1.value == node2.value &&
            node1.attributes == node2.attributes
        end

        # Detect specific changes between two nodes
        #
        # @param node1 [TreeNode] Original node
        # @param node2 [TreeNode] Modified node
        # @return [Hash] Hash of changes
        def detect_changes(node1, node2)
          changes = {}

          if node1.label != node2.label
            changes[:label] =
              { old: node1.label, new: node2.label }
          end
          if node1.value != node2.value
            changes[:value] =
              { old: node1.value, new: node2.value }
          end

          if node1.attributes != node2.attributes
            changes[:attributes] = {
              old: node1.attributes,
              new: node2.attributes,
            }
          end

          changes
        end

        # Collect all nodes in a tree (depth-first)
        #
        # @param node [TreeNode] Root node
        # @return [Array<TreeNode>] All nodes
        def collect_all_nodes(node)
          nodes = [node]
          node.children.each do |child|
            nodes.concat(collect_all_nodes(child))
          end
          nodes
        end

        # Detect MERGE operations
        # Pattern: Multiple sibling nodes in tree1 combined into one node in tree2
        # (n-1) × DELETE + 1 × UPDATE with content similarity
        def detect_merges
          deletes = @operations.select { |op| op.type == :delete }
          updates = @operations.select { |op| op.type == :update }

          # Group deletes by parent
          deletes_by_parent = deletes.group_by { |op| op[:parent] }

          deletes_by_parent.each do |parent1, del_ops|
            next if del_ops.size < 2 # Need at least 2 deletes for merge

            # Find potential merge target in updates with same parent
            parent2 = @matching.match_for1(parent1)
            next unless parent2

            updates.each do |update_op|
              node2 = update_op[:node2]
              next unless node2.parent == parent2

              # Check if deleted content was merged into this node
              if content_merged?(del_ops.map do |op|
                op[:node]
              end, update_op[:node1], node2)
                # Remove the component operations
                @operations.delete_if do |op|
                  del_ops.include?(op) || op == update_op
                end

                # Add merge operation
                @operations << Operation.new(
                  type: :merge,
                  source_nodes: del_ops.map { |op| op[:node] },
                  target_node: node2,
                  merged_from: del_ops.map { |op| op[:node].label },
                )
              end
            end
          end
        end

        # Detect SPLIT operations
        # Pattern: One node in tree1 split into multiple nodes in tree2
        # 1 × DELETE + n × INSERT with content similarity
        def detect_splits
          deletes = @operations.select { |op| op.type == :delete }
          inserts = @operations.select { |op| op.type == :insert }

          # Group inserts by parent
          inserts_by_parent = inserts.group_by { |op| op[:parent] }

          deletes.each do |delete_op|
            node1 = delete_op[:node]
            parent1 = delete_op[:parent]
            parent2 = @matching.match_for1(parent1) if parent1

            next unless parent2

            # Find inserts with the same parent in tree2
            candidate_inserts = inserts_by_parent[parent2] || []
            next if candidate_inserts.size < 2 # Need at least 2 inserts for split

            # Check if this node's content was split into multiple inserts
            if content_split?(node1, candidate_inserts.map { |op| op[:node] })
              # Remove the component operations
              @operations.delete(delete_op)
              @operations.delete_if { |op| candidate_inserts.include?(op) }

              # Add split operation
              @operations << Operation.new(
                type: :split,
                source_node: node1,
                target_nodes: candidate_inserts.map { |op| op[:node] },
                split_into: candidate_inserts.map { |op| op[:node].label },
              )
            end
          end
        end

        # Detect UPGRADE operations
        # Pattern: Node moved to shallower depth (promoted in hierarchy)
        # DELETE + INSERT at shallower depth with similar content
        def detect_upgrades
          deletes = @operations.select { |op| op.type == :delete }
          inserts = @operations.select { |op| op.type == :insert }

          deletes.each do |delete_op|
            node1 = delete_op[:node]
            depth1 = calculate_depth(node1)

            inserts.each do |insert_op|
              node2 = insert_op[:node]
              depth2 = calculate_depth(node2)

              # Upgrade means shallower depth (smaller number)
              next unless depth2 < depth1

              # Check if nodes are similar (same label, similar content)
              if nodes_similar_for_hierarchy_change?(node1, node2)
                # Remove the component operations
                @operations.delete(delete_op)
                @operations.delete(insert_op)

                # Add upgrade operation
                @operations << Operation.new(
                  type: :upgrade,
                  node1: node1,
                  node2: node2,
                  from_depth: depth1,
                  to_depth: depth2,
                  promoted_by: depth1 - depth2,
                )
              end
            end
          end
        end

        # Detect DOWNGRADE operations
        # Pattern: Node moved to deeper depth (demoted in hierarchy)
        # DELETE + INSERT at deeper depth with similar content
        def detect_downgrades
          deletes = @operations.select { |op| op.type == :delete }
          inserts = @operations.select { |op| op.type == :insert }

          deletes.each do |delete_op|
            node1 = delete_op[:node]
            depth1 = calculate_depth(node1)

            inserts.each do |insert_op|
              node2 = insert_op[:node]
              depth2 = calculate_depth(node2)

              # Downgrade means deeper depth (larger number)
              next unless depth2 > depth1

              # Check if nodes are similar (same label, similar content)
              if nodes_similar_for_hierarchy_change?(node1, node2)
                # Remove the component operations
                @operations.delete(delete_op)
                @operations.delete(insert_op)

                # Add downgrade operation
                @operations << Operation.new(
                  type: :downgrade,
                  node1: node1,
                  node2: node2,
                  from_depth: depth1,
                  to_depth: depth2,
                  demoted_by: depth2 - depth1,
                )
              end
            end
          end
        end

        # Check if content from multiple nodes was merged into target
        #
        # @param source_nodes [Array<TreeNode>] Source nodes
        # @param original_target [TreeNode] Original target node in tree1
        # @param merged_target [TreeNode] Merged target node in tree2
        # @return [Boolean]
        def content_merged?(source_nodes, original_target, merged_target)
          # Collect all text content
          source_text = source_nodes.map do |n|
            extract_text_content(n)
          end.join(" ")
          original_text = extract_text_content(original_target)
          merged_text = extract_text_content(merged_target)

          # Check if merged text contains both original and source content
          return false if merged_text.empty?

          similarity = text_similarity("#{source_text} #{original_text}",
                                       merged_text)
          similarity >= 0.8 # 80% similarity threshold for merge detection
        end

        # Check if content from one node was split into multiple nodes
        #
        # @param source_node [TreeNode] Source node
        # @param target_nodes [Array<TreeNode>] Target nodes
        # @return [Boolean]
        def content_split?(source_node, target_nodes)
          source_text = extract_text_content(source_node)
          target_text = target_nodes.map do |n|
            extract_text_content(n)
          end.join(" ")

          return false if source_text.empty? || target_text.empty?

          similarity = text_similarity(source_text, target_text)
          similarity >= 0.8 # 80% similarity threshold for split detection
        end

        # Check if two nodes are similar enough for hierarchy change
        #
        # @param node1 [TreeNode] First node
        # @param node2 [TreeNode] Second node
        # @return [Boolean]
        def nodes_similar_for_hierarchy_change?(node1, node2)
          # Must have same label
          return false unless node1.label == node2.label

          # Compare content similarity
          text1 = extract_text_content(node1)
          text2 = extract_text_content(node2)

          return true if text1.empty? && text2.empty?
          return false if text1.empty? || text2.empty?

          similarity = text_similarity(text1, text2)
          similarity >= 0.9 # 90% similarity for hierarchy changes
        end

        # Extract all text content from a node and its descendants
        #
        # @param node [TreeNode] Node to extract from
        # @return [String] Combined text content
        def extract_text_content(node)
          texts = []
          texts << node.value if node.value && !node.value.empty?

          node.children.each do |child|
            texts << extract_text_content(child)
          end

          texts.join(" ").strip
        end

        # Calculate text similarity using Jaccard index
        #
        # @param text1 [String] First text
        # @param text2 [String] Second text
        # @return [Float] Similarity score (0.0 to 1.0)
        def text_similarity(text1, text2)
          tokens1 = text1.downcase.split(/\s+/)
          tokens2 = text2.downcase.split(/\s+/)

          return 0.0 if tokens1.empty? && tokens2.empty?
          return 0.0 if tokens1.empty? || tokens2.empty?

          intersection = (tokens1 & tokens2).size
          union = (tokens1 | tokens2).size

          intersection.to_f / union
        end

        # Calculate depth of a node in the tree
        #
        # @param node [TreeNode] Node to calculate depth for
        # @return [Integer] Depth (0 for root)
        def calculate_depth(node)
          depth = 0
          current = node
          while current.parent
            depth += 1
            current = current.parent
          end
          depth
        end
      end
    end
  end
end
