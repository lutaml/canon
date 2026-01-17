# frozen_string_literal: true

module Canon
  module TreeDiff
    module OperationConverterHelpers
      # Post-processing of DiffNodes
      # Handles detection of attribute-order-only differences and other optimizations
      module PostProcessor
        # Detect INSERT/DELETE pairs that differ only in attribute order
        # and reclassify them to use the attribute_order dimension
        #
        # @param diff_nodes [Array<DiffNode>] Diff nodes to process
        # @param normative_determiner [#call] Proc/object to determine normative status
        # @return [Array<DiffNode>] Processed diff nodes
        def self.detect_attribute_order_diffs(diff_nodes, normative_determiner)
          # Group nodes by parent and element type
          deletes = diff_nodes.select { |dn| dn.node1 && !dn.node2 }
          inserts = diff_nodes.select { |dn| !dn.node1 && dn.node2 }

          # For each DELETE, try to find a matching INSERT
          deletes.each do |delete_node|
            node1 = delete_node.node1
            next unless node1.respond_to?(:name) && node1.respond_to?(:attributes)

            # Skip if node has no attributes (can't be attribute order diff)
            next if node1.attributes.nil? || node1.attributes.empty?

            # Find inserts with same element name at same position
            matching_insert = inserts.find do |insert_node|
              node2 = insert_node.node2
              next false unless node2.respond_to?(:name) && node2.respond_to?(:attributes)
              next false unless node1.name == node2.name

              # Must have attributes to differ in order
              next false if node2.attributes.nil? || node2.attributes.empty?

              # Check if they differ only in attribute order
              next false unless attributes_equal_ignoring_order?(
                node1.attributes, node2.attributes
              )

              # Ensure same content (text and children structure)
              nodes_same_except_attr_order?(node1, node2)
            end

            next unless matching_insert

            # Found an attribute-order-only difference
            # Reclassify both nodes to use attribute_order dimension
            delete_node.dimension = :attribute_order
            delete_node.reason = "attribute order changed"
            delete_node.normative = normative_determiner.call(:attribute_order)

            matching_insert.dimension = :attribute_order
            matching_insert.reason = "attribute order changed"
            matching_insert.normative = normative_determiner.call(:attribute_order)
          end

          diff_nodes
        end

        # Check if two attribute hashes are equal ignoring order
        #
        # @param attrs1 [Hash] First attribute hash
        # @param attrs2 [Hash] Second attribute hash
        # @return [Boolean] True if attributes are equal (ignoring order)
        def self.attributes_equal_ignoring_order?(attrs1, attrs2)
          return true if attrs1.nil? && attrs2.nil?
          return false if attrs1.nil? || attrs2.nil?

          # Convert to hashes if needed
          attrs1 = attrs1.to_h if attrs1.respond_to?(:to_h)
          attrs2 = attrs2.to_h if attrs2.respond_to?(:to_h)

          # Compare as sets (order-independent)
          attrs1.sort.to_h == attrs2.sort.to_h
        end

        # Check if two nodes are the same except for attribute order
        #
        # @param node1 [Nokogiri::XML::Node] First node
        # @param node2 [Nokogiri::XML::Node] Second node
        # @return [Boolean] True if nodes are same except attribute order
        def self.nodes_same_except_attr_order?(node1, node2)
          # Same text content
          return false if node1.text != node2.text

          # Same number of children
          return false if node1.children.length != node2.children.length

          # If has children, they should have same structure
          if node1.children.any?
            node1.children.zip(node2.children).all? do |child1, child2|
              child1.name == child2.name
            end
          else
            true
          end
        end
      end
    end
  end
end
