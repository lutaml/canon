# frozen_string_literal: true

module Canon
  module Diff
    # Builds canonical XPath-like paths from TreeNodes or raw nodes
    # Generates paths with ordinal indices to uniquely identify nodes
    # regardless of the parsing library used (Nokogiri, Moxml, Canon, etc.)
    #
    # This is library-agnostic because it operates on different node types:
    # - TreeNodes (from semantic diff adapters) - uses `label` attribute
    # - Canon::Xml::Node (from DOM diff) - uses `name` attribute
    # - Nokogiri nodes (from HTML DOM diff) - uses `name` method
    #
    # @example Build path for a TreeNode
    #   path = PathBuilder.build(tree_node)
    #   # => "/#document-fragment/div[0]/p[1]/span[2]"
    #
    # @example Build path for a Canon::Xml::Node
    #   path = PathBuilder.build(canon_node)
    #   # => "/#document/root[0]/body[0]/p[1]"
    #
    # @example Build path for a Nokogiri node
    #   path = PathBuilder.build(nokogiri_node)
    #   # => "/#document/div[0]/p[1]/span[2]"
    class PathBuilder
      # Build canonical path from a node (TreeNode, Canon::Xml::Node, or Nokogiri)
      #
      # @param node [Object] Node to build path for
      # @param format [Symbol] Format (:document or :fragment)
      # @return [String] Canonical path with ordinal indices
      def self.build(node, format: :fragment)
        return "" if node.nil?

        # Build path segments from root to node
        segments = build_segments(node)

        # Join segments with /
        path = "/" + segments.join("/")

        path
      end

      # Build path segments (node names with ordinal indices)
      # Traverses from node up to root, then reverses
      # Handles both TreeNodes and raw nodes (Canon::Xml::Node, Nokogiri)
      #
      # @param tree_node [Object] Node to build segments for
      # @return [Array<String>] Path segments from root to node
      def self.build_segments(tree_node)
        segments = []
        current = tree_node
        max_depth = 1000 # Prevent infinite loops
        depth = 0

        # Traverse up to root
        while current && depth < max_depth
          segments.unshift(segment_for_node(current))

          # Move to parent if available
          break unless current.respond_to?(:parent)
          current = current.parent
          depth += 1
        end

        segments
      end

      # Build path segment for a single node
      # Returns label with ordinal index: "div[0]", "span[1]", etc.
      # Handles both TreeNodes (with label) and raw nodes (with name)
      #
      # @param tree_node [Object] Node (TreeNode, Canon::Xml::Node, or Nokogiri)
      # @return [String] Path segment with ordinal index
      def self.segment_for_node(tree_node)
        # Handle both TreeNodes (with label) and raw nodes (with name)
        label = if tree_node.respond_to?(:label)
                  tree_node.label
                elsif tree_node.respond_to?(:name)
                  tree_node.name
                else
                  "unknown"
                end

        # Get ordinal index (position among siblings with same label)
        index = ordinal_index(tree_node)

        "#{label}[#{index}]"
      end

      # Get ordinal index of node among its siblings with the same label
      # Handles both TreeNodes (with Array children) and raw nodes (with NodeSet children)
      #
      # @param tree_node [Object] Node (TreeNode, Canon::Xml::Node, or Nokogiri)
      # @return [Integer] Zero-based ordinal index
      def self.ordinal_index(tree_node)
        # Defensive: return 0 if no parent or doesn't respond to parent
        return 0 unless tree_node.respond_to?(:parent)
        return 0 unless tree_node.parent

        # Check if parent has children
        return 0 unless tree_node.parent.respond_to?(:children)

        siblings = tree_node.parent.children
        return 0 unless siblings

        # Convert to array if it's a NodeSet (Nokogiri) or similar
        siblings = siblings.to_a unless siblings.is_a?(Array)

        # Get the label/name for comparison
        my_label = if tree_node.respond_to?(:label)
                     tree_node.label
                   elsif tree_node.respond_to?(:name)
                     tree_node.name
                   else
                     nil
                   end

        return 0 unless my_label

        # Count siblings with same label that appear before this node
        same_label_siblings = siblings.select do |s|
          sibling_label = if s.respond_to?(:label)
                            s.label
                          elsif s.respond_to?(:name)
                            s.name
                          else
                            nil
                          end
          sibling_label == my_label
        end

        # Find position in same-label siblings
        same_label_siblings.index(tree_node) || 0
      end

      # Build human-readable path description
      # Alternative format that may be more useful for error messages
      # Handles both TreeNodes and raw nodes
      #
      # @param tree_node [Object] Node (TreeNode, Canon::Xml::Node, or Nokogiri)
      # @return [String] Human-readable path
      def self.human_path(tree_node)
        segments = build_segments(tree_node)
        segments.join(" → ")
      end
    end
  end
end
