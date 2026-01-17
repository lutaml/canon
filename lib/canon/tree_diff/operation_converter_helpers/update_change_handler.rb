# frozen_string_literal: true

require_relative "../operation_converter_helpers/reason_builder"

module Canon
  module TreeDiff
    module OperationConverterHelpers
      # Handles UPDATE operation conversion
      # Processes different change types (attributes, attribute_order, value, label)
      module UpdateChangeHandler
        # Convert UPDATE operation to DiffNode(s)
        #
        # May return multiple DiffNodes if multiple dimensions changed
        #
        # @param operation [Operation] Update operation
        # @param metadata [Hash] Enriched metadata from MetadataEnricher
        # @param is_metadata [Boolean] Whether nodes are metadata elements
        # @param normative_determiner [#call] Proc/object to determine normative status
        # @return [Array<DiffNode>] Diff nodes representing updates
        def self.convert(operation, metadata, is_metadata, normative_determiner)
          tree_node1 = operation[:node1] # TreeNode from adapter
          tree_node2 = operation[:node2] # TreeNode from adapter
          node1 = tree_node1.respond_to?(:source_node) ? tree_node1.source_node : tree_node1
          node2 = tree_node2.respond_to?(:source_node) ? tree_node2.source_node : tree_node2
          changes = operation[:changes]

          # Handle case where changes is a boolean or non-hash value
          changes = {} unless changes.is_a?(Hash)

          diff_nodes = []

          # Create separate DiffNode for each change dimension
          # This ensures each dimension can be classified independently

          if changes.key?(:attributes)
            diff_nodes << create_attribute_value_diff(
              node1, node2, changes[:attributes], metadata, is_metadata, normative_determiner
            )
          end

          if changes.key?(:attribute_order)
            diff_nodes << create_attribute_order_diff(
              node1, node2, changes[:attribute_order], metadata, is_metadata, normative_determiner
            )
          end

          if changes.key?(:value)
            diff_nodes << create_text_content_diff(
              node1, node2, changes[:value], metadata, is_metadata, normative_determiner
            )
          end

          if changes.key?(:label)
            diff_nodes << create_element_name_diff(
              node1, node2, changes[:label], metadata, is_metadata, normative_determiner
            )
          end

          # If no specific changes detected, create a generic update
          if diff_nodes.empty?
            diff_nodes << create_generic_update_diff(
              node1, node2, metadata, is_metadata, normative_determiner
            )
          end

          diff_nodes
        end

        # Create DiffNode for attribute value differences
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param changes [Object] Attribute changes
        # @param metadata [Hash] Enriched metadata
        # @param is_metadata [Boolean] Whether nodes are metadata elements
        # @param normative_determiner [#call] Proc to determine normative status
        # @return [DiffNode] Diff node for attribute value differences
        def self.create_attribute_value_diff(node1, node2, changes, metadata,
is_metadata, normative_determiner)
          diff_details = ReasonBuilder.build_attribute_value_reason(changes)

          diff_node = Canon::Diff::DiffNode.new(
            node1: node1,
            node2: node2,
            dimension: :attribute_values,
            reason: diff_details,
            **metadata,
          )
          diff_node.normative = is_metadata ? false : normative_determiner.call(:attribute_values)
          diff_node
        end

        # Create DiffNode for attribute order differences
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param changes [Object] Attribute order changes
        # @param metadata [Hash] Enriched metadata
        # @param is_metadata [Boolean] Whether nodes are metadata elements
        # @param normative_determiner [#call] Proc to determine normative status
        # @return [DiffNode] Diff node for attribute order differences
        def self.create_attribute_order_diff(node1, node2, changes, metadata,
is_metadata, normative_determiner)
          reason = ReasonBuilder.build_attribute_order_reason(changes)

          diff_node = Canon::Diff::DiffNode.new(
            node1: node1,
            node2: node2,
            dimension: :attribute_order,
            reason: reason,
            **metadata,
          )
          diff_node.normative = is_metadata ? false : normative_determiner.call(:attribute_order)
          diff_node
        end

        # Create DiffNode for text content differences
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param changes [Object] Value changes
        # @param metadata [Hash] Enriched metadata
        # @param is_metadata [Boolean] Whether nodes are metadata elements
        # @param normative_determiner [#call] Proc to determine normative status
        # @return [DiffNode] Diff node for text content differences
        def self.create_text_content_diff(node1, node2, changes, metadata,
is_metadata, normative_determiner)
          reason = ReasonBuilder.build_text_content_reason(changes)

          diff_node = Canon::Diff::DiffNode.new(
            node1: node1,
            node2: node2,
            dimension: :text_content,
            reason: reason,
            **metadata,
          )
          diff_node.normative = is_metadata ? false : normative_determiner.call(:text_content)
          diff_node
        end

        # Create DiffNode for element name differences
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param changes [Object] Label changes
        # @param metadata [Hash] Enriched metadata
        # @param is_metadata [Boolean] Whether nodes are metadata elements
        # @param normative_determiner [#call] Proc to determine normative status
        # @return [DiffNode] Diff node for element name differences
        def self.create_element_name_diff(node1, node2, changes, metadata,
is_metadata, normative_determiner)
          reason = ReasonBuilder.build_element_name_reason(changes)

          diff_node = Canon::Diff::DiffNode.new(
            node1: node1,
            node2: node2,
            dimension: :element_structure,
            reason: reason,
            **metadata,
          )
          diff_node.normative = is_metadata ? false : normative_determiner.call(:element_structure)
          diff_node
        end

        # Create generic update DiffNode
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param metadata [Hash] Enriched metadata
        # @param is_metadata [Boolean] Whether nodes are metadata elements
        # @param normative_determiner [#call] Proc to determine normative status
        # @return [DiffNode] Generic update diff node
        def self.create_generic_update_diff(node1, node2, metadata,
is_metadata, normative_determiner)
          diff_node = Canon::Diff::DiffNode.new(
            node1: node1,
            node2: node2,
            dimension: :text_content,
            reason: "content differs",
            **metadata,
          )
          diff_node.normative = is_metadata ? false : normative_determiner.call(:text_content)
          diff_node
        end
      end
    end
  end
end
