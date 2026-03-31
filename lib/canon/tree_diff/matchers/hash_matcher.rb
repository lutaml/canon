# frozen_string_literal: true

require_relative "../core/tree_node"
require_relative "../core/node_signature"
require_relative "../core/node_weight"
require_relative "../core/matching"
require_relative "../core/attribute_comparator"
require_relative "../core/xml_entity_decoder"

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
          build_signature_map

          tree2_nodes = collect_nodes(tree2).sort_by do |node|
            -Core::NodeWeight.for(node).value
          end

          tree2_nodes.each do |node2|
            next if @matched_tree2.include?(node2)

            match_node(node2)
          end

          @matching
        end

        private

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

        def match_node(node2)
          sig2 = Core::NodeSignature.for(node2)
          candidates = (@signature_map[sig2] || []).reject do |n|
            @matched_tree1.include?(n)
          end
          return if candidates.empty?

          best_match = find_best_match(node2, candidates)
          return unless best_match

          if @matching.add(best_match, node2)
            @matched_tree1 << best_match
            @matched_tree2 << node2
            propagate_to_ancestors(best_match, node2)
          end
        end

        # @return [TreeNode, nil]
        def find_best_match(node2, candidates)
          candidates.find { |node1| subtrees_match?(node1, node2) }
        end

        def subtrees_match?(node1, node2)
          return false unless nodes_match?(node1, node2)
          return false unless node1.children.size == node2.children.size

          node1.children.zip(node2.children).all? do |child1, child2|
            subtrees_match?(child1, child2)
          end
        end

        def nodes_match?(node1, node2)
          return false unless node1.label == node2.label
          return false unless text_equivalent?(node1, node2)

          # Check attribute KEYS match, not values — value diffs are reported as UPDATE
          return false unless node1.attributes.keys == node2.attributes.keys

          true
        end

        def text_equivalent?(node1, node2)
          text1 = node1.value
          text2 = node2.value

          return true if (text1.nil? || text1.empty?) && (text2.nil? || text2.empty?)
          return false if (text1.nil? || text1.empty?) || (text2.nil? || text2.empty?)

          norm1 = normalize_text(text1)
          norm2 = normalize_text(text2)
          return true if norm1.empty? && norm2.empty?

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

        def normalize_text(text)
          return "" if text.nil? || text.empty?

          normalized = Core::XmlEntityDecoder.decode_xml_entities(text)
          normalized.gsub(/\s+/, " ").strip
        end

        def propagate_to_ancestors(node1, node2)
          parent1 = node1.parent
          parent2 = node2.parent

          return unless parent1 && parent2
          return if @matched_tree1.include?(parent1)
          return if @matched_tree2.include?(parent2)

          sig1 = Core::NodeSignature.for(parent1)
          sig2 = Core::NodeSignature.for(parent2)
          return unless sig1 == sig2

          return unless nodes_match?(parent1, parent2)

          if @matching.add(parent1, parent2)
            @matched_tree1 << parent1
            @matched_tree2 << parent2
            propagate_to_ancestors(parent1, parent2)
          end
        end
      end
    end
  end
end
