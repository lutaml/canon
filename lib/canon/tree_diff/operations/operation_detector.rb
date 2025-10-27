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
        attr_reader :tree1, :tree2, :matching, :operations, :match_options

        # Initialize a new operation detector
        #
        # @param tree1 [TreeNode] First tree root
        # @param tree2 [TreeNode] Second tree root
        # @param matching [Matching] Matching between trees
        # @param match_options [Hash] Match options for comparison
        def initialize(tree1, tree2, matching, match_options = {})
          @tree1 = tree1
          @tree2 = tree2
          @matching = matching
          @match_options = match_options || {}
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

            # Skip if parent is also unmatched (parent will be reported instead)
            # This prevents redundant reporting of descendants
            parent2 = node2.parent
            next if parent2 && !@matching.matched2?(parent2)

            # Find position
            position = parent2 ? parent2.children.index(node2) : 0

            @operations << Operation.new(
              type: :insert,
              node: node2,
              parent: parent2,
              position: position,
              path: node2.xpath,
              content: extract_node_content(node2),
            )
          end
        end

        # Detect DELETE operations (nodes in tree1 not matched in tree2)
        def detect_deletes
          all_nodes1 = collect_all_nodes(tree1)

          all_nodes1.each do |node1|
            next if @matching.matched1?(node1)

            # Skip if parent is also unmatched (parent will be reported instead)
            # This prevents redundant reporting of descendants
            parent1 = node1.parent
            next if parent1 && !@matching.matched1?(parent1)

            # Find position
            position = parent1 ? parent1.children.index(node1) : 0

            @operations << Operation.new(
              type: :delete,
              node: node1,
              parent: parent1,
              position: position,
              path: node1.xpath,
              content: extract_node_content(node1),
            )
          end
        end

        # Detect UPDATE operations (matched nodes with different content)
        def detect_updates
          @matching.pairs.each do |node1, node2|
            # Detect what changed (including attribute order)
            changes = detect_changes(node1, node2)

            # Skip if truly identical (no changes detected)
            next if changes.empty?

            @operations << Operation.new(
              type: :update,
              node1: node1,
              node2: node2,
              changes: changes,
              path: node2.xpath,
              old_content: extract_node_content(node1),
              new_content: extract_node_content(node2),
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
              old_path: node1.xpath,
              new_path: node2.xpath,
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

          # CRITICAL FIX: Use normalized text comparison based on match_options
          if !text_equivalent?(node1, node2)
            changes[:value] =
              { old: node1.value, new: node2.value }
          end

          # Detect attribute changes (values or order)
          attrs1 = node1.attributes
          attrs2 = node2.attributes

          # Check if attribute values differ (ignoring order)
          if attrs1.sort.to_h != attrs2.sort.to_h
            # Actual attribute value differences
            changes[:attributes] = {
              old: attrs1,
              new: attrs2,
            }
          end

          # Check if attribute order differs (independently)
          # This can coexist with attribute value differences
          # Only detect order differences when the same attributes exist in different order
          # AND when attribute_order mode is :strict
          attribute_order_mode = @match_options[:attribute_order] || :ignore
          if attribute_order_mode == :strict &&
             attrs1.keys.sort == attrs2.keys.sort &&
             attrs1.keys != attrs2.keys
            # Same attributes but in different order
            changes[:attribute_order] = {
              old: attrs1.keys,
              new: attrs2.keys,
            }
          end

          changes
        end

        # Check if text values are equivalent according to match options
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

          # Check if node is in a whitespace-sensitive context
          is_ws_sensitive = whitespace_sensitive?(node1) || whitespace_sensitive?(node2)
          if is_ws_sensitive
            # For whitespace-sensitive elements, use strict comparison
            return text1 == text2
          end

          # For non-whitespace-sensitive elements, apply normalization
          norm1 = normalize_text(text1)
          norm2 = normalize_text(text2)

          # If both normalize to empty (whitespace-only), treat as equivalent
          # This only applies to non-whitespace-sensitive contexts
          return true if norm1.empty? && norm2.empty?

          # Apply normalization based on match_options
          text_content_mode = @match_options[:text_content] || :normalize

          case text_content_mode
          when :strict
            # Strict mode: must match exactly
            text1 == text2
          when :normalize, :normalized
            # Normalize mode: normalize whitespace before comparing
            norm1 == norm2
          else
            # Default to normalize behavior
            norm1 == norm2
          end
        end

        # Normalize text for comparison
        #
        # Collapses multiple whitespace into single space and strips.
        # This matches the behavior of Canon's text_content: normalize option.
        #
        # @param text [String, nil] Text to normalize
        # @return [String] Normalized text
        def normalize_text(text)
          return "" if text.nil? || text.empty?

          # Collapse multiple whitespace (including newlines) into single space
          # Then strip leading/trailing whitespace
          text.gsub(/\s+/, ' ').strip
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

        # Extract node content summary for display
        #
        # @param node [TreeNode] Node to extract from
        # @return [String] Content summary
        def extract_node_content(node)
          parts = []

          # Add label
          parts << "<#{node.label}>"

          # Add attributes if present
          unless node.attributes.empty?
            attrs = node.attributes.map { |k, v| "#{k}=\"#{v}\"" }.join(" ")
            parts << "[#{attrs}]"
          end

          # Add value/text if present
          if node.value && !node.value.empty?
            # Truncate long values
            value_preview = node.value.length > 50 ? "#{node.value[0..47]}..." : node.value
            parts << "\"#{value_preview}\""
          elsif !node.children.empty?
            parts << "(#{node.children.size} children)"
          end

          parts.join(" ")
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

        # Check if a node is in a whitespace-sensitive context
        #
        # HTML elements where whitespace is significant: <pre>, <code>, <textarea>, <script>, <style>
        #
        # @param node [TreeNode] Node to check
        # @return [Boolean] True if node is in whitespace-sensitive context
        def whitespace_sensitive?(node)
          return false unless node

          # List of HTML elements where whitespace is semantically significant
          whitespace_sensitive_tags = %w[pre code textarea script style]

          # Check if this node or any ancestor is whitespace-sensitive
          current = node
          while current
            if current.respond_to?(:label)
              label = current.label.to_s.downcase
              return true if whitespace_sensitive_tags.include?(label)
            end

            # Check parent
            current = current.parent if current.respond_to?(:parent)
            break unless current
          end

          false
        end
      end
    end
  end
end
