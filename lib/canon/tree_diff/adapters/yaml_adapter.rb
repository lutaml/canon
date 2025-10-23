# frozen_string_literal: true

require "yaml"

module Canon
  module TreeDiff
    module Adapters
      # YAMLAdapter converts YAML structures to TreeNode structures and back,
      # enabling semantic tree diffing on YAML documents.
      #
      # This adapter:
      # - Converts Hash/Array YAML structures to TreeNode tree
      # - Handles nested objects, arrays, and primitive values
      # - Preserves type information for round-trip conversion
      # - Maps YAML structure to tree representation
      #
      # YAML to TreeNode mapping (similar to JSON):
      # - Objects (Hash): TreeNode with label "object", children for each key
      # - Arrays: TreeNode with label "array", indexed children
      # - Primitives: TreeNode with label "value", value stored directly
      #
      # @example Convert YAML to TreeNode
      #   yaml = { "name" => "John", "age" => 30 }
      #   adapter = YAMLAdapter.new
      #   tree = adapter.to_tree(yaml)
      #
      class YAMLAdapter
        # Convert YAML structure to TreeNode
        #
        # @param data [Hash, Array, String, Numeric, Boolean, nil] YAML data
        # @param key [String, nil] Key name if this is a hash value
        # @return [Core::TreeNode] Root tree node
        def to_tree(data, key = nil)
          case data
          when Hash
            convert_object(data, key)
          when Array
            convert_array(data, key)
          else
            convert_value(data, key)
          end
        end

        # Convert TreeNode back to YAML structure
        #
        # @param tree_node [Core::TreeNode] Root tree node
        # @return [Hash, Array, Object] YAML structure
        def from_tree(tree_node)
          case tree_node.label
          when "object"
            build_object(tree_node)
          when "array"
            build_array(tree_node)
          when "value"
            parse_value(tree_node)
          else
            # Fallback for custom labels
            tree_node.value
          end
        end

        private

        # Convert YAML object (Hash) to TreeNode
        #
        # @param hash [Hash] YAML object
        # @param key [String, nil] Key name if this is nested
        # @return [Core::TreeNode] Tree node
        def convert_object(hash, key = nil)
          attributes = key ? { "key" => key } : {}

          tree_node = Core::TreeNode.new(
            label: "object",
            value: nil,
            attributes: attributes
          )

          hash.each do |k, v|
            child = to_tree(v, k.to_s)
            tree_node.add_child(child)
          end

          tree_node
        end

        # Convert YAML array to TreeNode
        #
        # @param array [Array] YAML array
        # @param key [String, nil] Key name if this is nested
        # @return [Core::TreeNode] Tree node
        def convert_array(array, key = nil)
          attributes = key ? { "key" => key } : {}

          tree_node = Core::TreeNode.new(
            label: "array",
            value: nil,
            attributes: attributes
          )

          array.each_with_index do |item, index|
            child = to_tree(item, index.to_s)
            tree_node.add_child(child)
          end

          tree_node
        end

        # Convert primitive value to TreeNode
        #
        # @param value [String, Numeric, Boolean, nil] Primitive value
        # @param key [String, nil] Key name
        # @return [Core::TreeNode] Tree node
        def convert_value(value, key = nil)
          attributes = {}
          attributes["key"] = key if key
          attributes["type"] = value_type(value)

          Core::TreeNode.new(
            label: "value",
            value: value.to_s,
            attributes: attributes
          )
        end

        # Determine value type
        #
        # @param value [Object] Value
        # @return [String] Type name
        def value_type(value)
          case value
          when String then "string"
          when Integer then "integer"
          when Float then "float"
          when TrueClass, FalseClass then "boolean"
          when NilClass then "null"
          when Symbol then "symbol"
          when Date then "date"
          when Time, DateTime then "time"
          else "unknown"
          end
        end

        # Build Hash from object TreeNode
        #
        # @param tree_node [Core::TreeNode] Object tree node
        # @return [Hash] Reconstructed hash
        def build_object(tree_node)
          hash = {}

          tree_node.children.each do |child|
            key = child.attributes["key"]
            hash[key] = from_tree(child) if key
          end

          hash
        end

        # Build Array from array TreeNode
        #
        # @param tree_node [Core::TreeNode] Array tree node
        # @return [Array] Reconstructed array
        def build_array(tree_node)
          array = []

          tree_node.children.each do |child|
            array << from_tree(child)
          end

          array
        end

        # Parse value from value TreeNode
        #
        # @param tree_node [Core::TreeNode] Value tree node
        # @return [Object] Parsed value
        def parse_value(tree_node)
          type = tree_node.attributes["type"]
          value_str = tree_node.value

          case type
          when "string"
            value_str
          when "integer"
            value_str.to_i
          when "float"
            value_str.to_f
          when "boolean"
            value_str == "true"
          when "null"
            nil
          when "symbol"
            value_str.to_sym
          when "date"
            Date.parse(value_str)
          when "time"
            Time.parse(value_str)
          else
            value_str
          end
        end
      end
    end
  end
end
