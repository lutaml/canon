# frozen_string_literal: true

module Canon
  module TreeDiff
    module Core
      # TreeNode represents a node in a semantic tree structure
      #
      # This is the fundamental data structure for tree-based diffing,
      # supporting both XML and JSON trees in a format-agnostic way.
      #
      # Key features:
      # - Label: Node name/key (e.g., element name, object key)
      # - Value: Leaf node content (text, number, boolean, etc.)
      # - Children: Ordered list of child nodes
      # - Parent: Reference to parent node (nil for root)
      # - Attributes: Key-value metadata (e.g., XML attributes)
      # - Signature: Computed path-based identifier (XDiff-style)
      # - Weight: Subtree size metric (XyDiff-style)
      # - XID: External identifier for matching (e.g., XML id attribute)
      class TreeNode
        attr_accessor :label, :value, :children, :parent, :attributes,
                      :signature, :weight, :xid, :source_node
        attr_reader :metadata

        # Initialize a new TreeNode
        #
        # @param label [String] Node name/key
        # @param value [String, Numeric, Boolean, nil] Leaf value
        # @param children [Array<TreeNode>] Child nodes
        # @param parent [TreeNode, nil] Parent node
        # @param attributes [Hash] Node attributes
        # @param xid [String, nil] External identifier
        # @param source_node [Object, nil] Original source node (e.g., Nokogiri node)
        def initialize(label:, value: nil, children: [], parent: nil,
                       attributes: {}, xid: nil, source_node: nil)
          @label = label
          @value = value
          @children = children
          @parent = parent
          @attributes = attributes
          @xid = xid
          @source_node = source_node
          @metadata = {}

          # Set this node as parent for all children
          @children.each { |child| child.parent = self }

          # Computed lazily
          @signature = nil
          @weight = nil
        end

        # Check if this is a leaf node (no children)
        #
        # @return [Boolean]
        def leaf?
          children.empty?
        end

        # Check if this is a text node (leaf with value)
        #
        # @return [Boolean]
        def text?
          leaf? && !value.nil?
        end

        # Check if this is an element node (has children or attributes)
        #
        # @return [Boolean]
        def element?
          !leaf? || !attributes.empty?
        end

        # Get the root node of this tree
        #
        # @return [TreeNode]
        def root
          node = self
          node = node.parent while node.parent
          node
        end

        # Get all ancestor nodes from parent to root
        #
        # @return [Array<TreeNode>]
        def ancestors
          result = []
          node = parent
          while node
            result << node
            node = node.parent
          end
          result
        end

        # Get all descendant nodes (depth-first)
        #
        # @return [Array<TreeNode>]
        def descendants
          result = []
          children.each do |child|
            result << child
            result.concat(child.descendants)
          end
          result
        end

        # Get sibling nodes (nodes with same parent)
        #
        # @return [Array<TreeNode>]
        def siblings
          return [] unless parent

          parent.children.reject { |child| child == self }
        end

        # Get left siblings (siblings before this node)
        #
        # @return [Array<TreeNode>]
        def left_siblings
          return [] unless parent

          index = parent.children.index(self)
          return [] unless index

          parent.children[0...index]
        end

        # Get right siblings (siblings after this node)
        #
        # @return [Array<TreeNode>]
        def right_siblings
          return [] unless parent

          index = parent.children.index(self)
          return [] unless index

          parent.children[(index + 1)..]
        end

        # Get the position of this node among its siblings
        #
        # @return [Integer, nil] 0-based index, or nil if no parent
        def position
          return nil unless parent

          parent.children.index(self)
        end

        # Get depth of this node (distance from root)
        #
        # @return [Integer]
        def depth
          ancestors.size
        end

        # Get height of this node (max distance to any leaf)
        #
        # @return [Integer]
        def height
          return 0 if leaf?

          1 + children.map(&:height).max
        end

        # Get the size of subtree rooted at this node
        #
        # @return [Integer]
        def size
          1 + children.sum(&:size)
        end

        # Add a child node
        #
        # @param child [TreeNode] Child to add
        # @param position [Integer, nil] Optional position to insert at
        # @return [TreeNode] The added child
        def add_child(child, position: nil)
          child.parent = self

          if position
            children.insert(position, child)
          else
            children << child
          end

          # Invalidate cached computations
          invalidate_cache

          child
        end

        # Remove a child node
        #
        # @param child [TreeNode] Child to remove
        # @return [TreeNode, nil] The removed child, or nil if not found
        def remove_child(child)
          removed = children.delete(child)
          removed&.parent = nil

          # Invalidate cached computations
          invalidate_cache if removed

          removed
        end

        # Replace a child node with another
        #
        # @param old_child [TreeNode] Child to replace
        # @param new_child [TreeNode] New child
        # @return [TreeNode, nil] The replaced child, or nil if not found
        def replace_child(old_child, new_child)
          index = children.index(old_child)
          return nil unless index

          old_child.parent = nil
          new_child.parent = self
          children[index] = new_child

          # Invalidate cached computations
          invalidate_cache

          old_child
        end

        # Check if two nodes match exactly
        #
        # Exact match requires:
        # - Same label
        # - Same value (for text nodes)
        # - Same attributes (key-value pairs)
        # - Same number of children with same labels
        #
        # @param other [TreeNode] Node to compare with
        # @return [Boolean]
        def matches?(other)
          return false unless other.is_a?(TreeNode)
          return false unless label == other.label
          return false unless value == other.value
          return false unless attributes == other.attributes
          return false unless children.size == other.children.size

          # Check children have same labels
          children.map(&:label) == other.children.map(&:label)
        end

        # Calculate similarity score with another node
        #
        # Uses Jaccard index on combined content:
        # - Label
        # - Value
        # - Attribute keys and values
        # - Child labels
        #
        # @param other [TreeNode] Node to compare with
        # @return [Float] Similarity score 0.0 to 1.0
        def similarity_to(other)
          return 0.0 unless other.is_a?(TreeNode)

          # Extract comparable elements
          set1 = content_set
          set2 = other.content_set

          # Jaccard index: |intersection| / |union|
          return 0.0 if set1.empty? && set2.empty?

          intersection = (set1 & set2).size.to_f
          union = (set1 | set2).size.to_f

          intersection / union
        end

        # Calculate semantic distance to another node
        #
        # Semantic distance considers:
        # - Depth difference (structural distance)
        # - Content similarity (inverse)
        # - Attribute differences
        #
        # @param other [TreeNode] Node to compare with
        # @return [Float] Distance metric (0 = identical)
        def semantic_distance_to(other)
          return Float::INFINITY unless other.is_a?(TreeNode)

          # Component 1: Depth difference (structural)
          depth_diff = (depth - other.depth).abs.to_f

          # Component 2: Content dissimilarity
          content_diff = 1.0 - similarity_to(other)

          # Component 3: Attribute differences
          attr_diff = attribute_difference(other)

          # Weighted combination
          depth_diff * 0.3 + content_diff * 0.5 + attr_diff * 0.2
        end

        # Get content as a set for similarity calculation
        #
        # @return [Set<String>]
        def content_set
          result = Set.new

          # Add label
          result << "label:#{label}" if label

          # Add value
          result << "value:#{value}" if value

          # Add attributes
          attributes.each do |key, val|
            result << "attr:#{key}=#{val}"
          end

          # Add child labels
          children.each do |child|
            result << "child:#{child.label}"
          end

          result
        end

        # Calculate attribute difference with another node
        #
        # @param other [TreeNode] Node to compare with
        # @return [Float] Difference score 0.0 to 1.0
        def attribute_difference(other)
          keys1 = Set.new(attributes.keys)
          keys2 = Set.new(other.attributes.keys)

          all_keys = keys1 | keys2
          return 0.0 if all_keys.empty?

          diff_count = 0

          all_keys.each do |key|
            val1 = attributes[key]
            val2 = other.attributes[key]

            diff_count += 1 if val1 != val2
          end

          diff_count.to_f / all_keys.size
        end

        # Get XPath for this node
        #
        # @return [String] XPath expression
        def xpath
          # If we have a source node that supports xpath, use it
          if @source_node && @source_node.respond_to?(:path)
            return @source_node.path
          end

          # Otherwise construct path from tree structure
          construct_path
        end

        # Construct path from tree structure
        #
        # @return [String] Path expression
        def construct_path
          segments = []
          node = self

          while node
            if node.parent
              # Get position among siblings with same label
              siblings = node.parent.children.select { |c| c.label == node.label }
              position = siblings.index(node)

              if siblings.size > 1
                segments.unshift("#{node.label}[#{position}]")
              else
                segments.unshift(node.label)
              end
            else
              segments.unshift(node.label)
            end

            node = node.parent
          end

          "/" + segments.join("/")
        end

        # Deep clone this node and its subtree
        #
        # @return [TreeNode]
        def deep_clone
          cloned_children = children.map(&:deep_clone)

          TreeNode.new(
            label: label,
            value: value,
            children: cloned_children,
            parent: nil,
            attributes: attributes.dup,
            xid: xid,
            source_node: source_node, # Preserve source node reference
          )
        end

        # Convert to hash representation
        #
        # @return [Hash]
        def to_h
          result = {
            label: label,
            value: value,
            attributes: attributes,
            xid: xid,
            children: children.map(&:to_h),
          }

          result[:signature] = signature if signature
          result[:weight] = weight if weight

          result
        end

        # String representation for debugging
        #
        # @return [String]
        def inspect
          attrs = []
          attrs << "label=#{label.inspect}"
          attrs << "value=#{value.inspect}" if value
          attrs << "xid=#{xid.inspect}" if xid
          attrs << "children=#{children.size}" unless children.empty?
          attrs << "attributes=#{attributes.size}" unless attributes.empty?

          "#<TreeNode #{attrs.join(' ')}>"
        end

        alias to_s inspect

        private

        # Invalidate cached computations
        def invalidate_cache
          @signature = nil
          @weight = nil

          # Propagate upward
          parent&.send(:invalidate_cache)
        end
      end
    end
  end
end
