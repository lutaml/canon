# frozen_string_literal: true

require_relative "../diff/diff_node"
require_relative "../comparison/match_options"

module Canon
  module TreeDiff
    # Converts TreeDiff Operations to DiffNodes for integration with Canon's
    # existing diff pipeline.
    #
    # This class bridges the semantic tree diff system with Canon's DOM-based
    # diff architecture by mapping operations to match dimensions and creating
    # DiffNode objects that can be processed by the standard diff formatter.
    #
    # @example Convert operations to diff nodes
    #   converter = OperationConverter.new(format: :xml, match_options: opts)
    #   diff_nodes = converter.convert(operations)
    #
    class OperationConverter
      # Mapping from operation types to match dimensions
      OPERATION_TO_DIMENSION = {
        insert: :element_structure,
        delete: :element_structure,
        update: :text_content, # Default, refined based on what changed
        move: :element_position,
        merge: :element_structure,
        split: :element_structure,
        upgrade: :element_hierarchy,
        downgrade: :element_hierarchy,
      }.freeze

      attr_reader :format, :match_options

      # Initialize converter
      #
      # @param format [Symbol] Document format (:xml, :html, :json, :yaml)
      # @param match_options [Hash] Match options for determining normative/informative
    def initialize(format:, match_options: {})
      @format = format

      # Resolve match options using format-specific module
      match_opts_hash = case format
      when :xml, :html, :html4, :html5
        Canon::Comparison::MatchOptions::Xml.resolve(
          format: format,
          match: match_options
        )
      when :json
        Canon::Comparison::MatchOptions::Json.resolve(
          format: format,
          match: match_options
        )
      when :yaml
        Canon::Comparison::MatchOptions::Yaml.resolve(
          format: format,
          match: match_options
        )
      else
        raise ArgumentError, "Unknown format: #{format}"
      end

      # Wrap in ResolvedMatchOptions
      @match_options = Canon::Comparison::ResolvedMatchOptions.new(
        match_opts_hash,
        format: format
      )
    end

      # Convert array of Operations to array of DiffNodes
      #
      # @param operations [Array<Operation>] Operations to convert
      # @return [Array<DiffNode>] Converted diff nodes
      def convert(operations)
        diff_nodes = operations.flat_map { |operation| convert_operation(operation) }

        # Post-process to detect attribute-order-only differences
        detect_attribute_order_diffs(diff_nodes)
      end

      private

      # Convert a single Operation to a DiffNode
      #
      # @param operation [Operation] Operation to convert
      # @return [DiffNode] Converted diff node
      def convert_operation(operation)
        case operation.type
        when :insert
          convert_insert(operation)
        when :delete
          convert_delete(operation)
        when :update
          convert_update(operation)
        when :move
          convert_move(operation)
        when :merge
          convert_merge(operation)
        when :split
          convert_split(operation)
        when :upgrade
          convert_upgrade(operation)
        when :downgrade
          convert_downgrade(operation)
        else
          raise ArgumentError, "Unknown operation type: #{operation.type}"
        end
      end

      # Convert INSERT operation to DiffNode
      #
      # @param operation [Operation] Insert operation
      # @return [DiffNode] Diff node representing insertion
      def convert_insert(operation)
        node2 = extract_source_node(operation[:node])

        diff_node = Canon::Diff::DiffNode.new(
          node1: nil,
          node2: node2,
          dimension: :element_structure,
          reason: build_insert_reason(operation)
        )
        diff_node.normative = determine_normative(:element_structure)
        diff_node
      end

      # Convert DELETE operation to DiffNode
      #
      # @param operation [Operation] Delete operation
      # @return [DiffNode] Diff node representing deletion
      def convert_delete(operation)
        node1 = extract_source_node(operation[:node])

        diff_node = Canon::Diff::DiffNode.new(
          node1: node1,
          node2: nil,
          dimension: :element_structure,
          reason: build_delete_reason(operation)
        )
        diff_node.normative = determine_normative(:element_structure)
        diff_node
      end

      # Convert UPDATE operation to DiffNode(s)
      #
      # May return multiple DiffNodes if multiple dimensions changed
      #
      # @param operation [Operation] Update operation
      # @return [Array<DiffNode>] Diff nodes representing updates
      def convert_update(operation)
        node1 = extract_source_node(operation[:node1])
        node2 = extract_source_node(operation[:node2])
        changes = operation[:changes] || {}

        diff_nodes = []

        # Create separate DiffNode for each change dimension
        # This ensures each dimension can be classified independently

        if changes.key?(:attributes)
          # Attribute value differences
          diff_node = Canon::Diff::DiffNode.new(
            node1: node1,
            node2: node2,
            dimension: :attribute_values,
            reason: "attribute values differ"
          )
          diff_node.normative = determine_normative(:attribute_values)
          diff_nodes << diff_node
        end

        if changes.key?(:attribute_order)
          # Attribute order differences
          diff_node = Canon::Diff::DiffNode.new(
            node1: node1,
            node2: node2,
            dimension: :attribute_order,
            reason: "attribute order differs"
          )
          diff_node.normative = determine_normative(:attribute_order)
          diff_nodes << diff_node
        end

        if changes.key?(:value)
          # Text content differences
          diff_node = Canon::Diff::DiffNode.new(
            node1: node1,
            node2: node2,
            dimension: :text_content,
            reason: "text content differs"
          )
          diff_node.normative = determine_normative(:text_content)
          diff_nodes << diff_node
        end

        if changes.key?(:label)
          # Element name differences
          diff_node = Canon::Diff::DiffNode.new(
            node1: node1,
            node2: node2,
            dimension: :element_structure,
            reason: "element name differs"
          )
          diff_node.normative = determine_normative(:element_structure)
          diff_nodes << diff_node
        end

        # If no specific changes detected, create a generic update
        if diff_nodes.empty?
          diff_node = Canon::Diff::DiffNode.new(
            node1: node1,
            node2: node2,
            dimension: :text_content,
            reason: "content differs"
          )
          diff_node.normative = determine_normative(:text_content)
          diff_nodes << diff_node
        end

        diff_nodes
      end

      # Convert MOVE operation to DiffNode
      #
      # @param operation [Operation] Move operation
      # @return [DiffNode] Diff node representing move
      def convert_move(operation)
        node1 = extract_source_node(operation[:node1])
        node2 = extract_source_node(operation[:node2])

        diff_node = Canon::Diff::DiffNode.new(
          node1: node1,
          node2: node2,
          dimension: :element_position,
          reason: build_move_reason(operation)
        )
        diff_node.normative = determine_normative(:element_position)
        diff_node
      end

      # Convert MERGE operation to DiffNode
      #
      # @param operation [Operation] Merge operation
      # @return [DiffNode] Diff node representing merge
      def convert_merge(operation)
        # Merge combines multiple nodes into one
        # node1 represents the source nodes, node2 is the merged result
        node1 = extract_source_node(operation[:nodes]&.first)
        node2 = extract_source_node(operation[:result])

        diff_node = Canon::Diff::DiffNode.new(
          node1: node1,
          node2: node2,
          dimension: :element_structure,
          reason: "merged #{operation[:nodes]&.length || 0} nodes"
        )
        diff_node.normative = true # Merges are structural changes, always normative
        diff_node
      end

      # Convert SPLIT operation to DiffNode
      #
      # @param operation [Operation] Split operation
      # @return [DiffNode] Diff node representing split
      def convert_split(operation)
        # Split divides one node into multiple
        # node1 is the original, node2 represents the split results
        node1 = extract_source_node(operation[:node])
        node2 = extract_source_node(operation[:results]&.first)

        diff_node = Canon::Diff::DiffNode.new(
          node1: node1,
          node2: node2,
          dimension: :element_structure,
          reason: "split into #{operation[:results]&.length || 0} nodes"
        )
        diff_node.normative = true # Splits are structural changes, always normative
        diff_node
      end

      # Convert UPGRADE operation to DiffNode (promote/decrease depth)
      #
      # @param operation [Operation] Upgrade operation
      # @return [DiffNode] Diff node representing upgrade
      def convert_upgrade(operation)
        node1 = extract_source_node(operation[:node1])
        node2 = extract_source_node(operation[:node2])

        diff_node = Canon::Diff::DiffNode.new(
          node1: node1,
          node2: node2,
          dimension: :element_hierarchy,
          reason: "promoted to higher level"
        )
        diff_node.normative = determine_normative(:element_hierarchy)
        diff_node
      end

      # Convert DOWNGRADE operation to DiffNode (demote/increase depth)
      #
      # @param operation [Operation] Downgrade operation
      # @return [DiffNode] Diff node representing downgrade
      def convert_downgrade(operation)
        node1 = extract_source_node(operation[:node1])
        node2 = extract_source_node(operation[:node2])

        diff_node = Canon::Diff::DiffNode.new(
          node1: node1,
          node2: node2,
          dimension: :element_hierarchy,
          reason: "demoted to lower level"
        )
        diff_node.normative = determine_normative(:element_hierarchy)
        diff_node
      end

      # Extract source node from TreeNode
      #
      # @param tree_node [TreeNode, nil] Tree node wrapper
      # @return [Object, nil] Source node (Nokogiri, Hash, etc.)
      def extract_source_node(tree_node)
        return nil if tree_node.nil?
        tree_node.respond_to?(:source_node) ? tree_node.source_node : tree_node
      end

      # Determine update dimension based on what changed
      #
      # @param operation [Operation] Update operation
      # @return [Symbol] Match dimension
      def determine_update_dimension(operation)
        changes = operation[:changes] || {}

        # Check what actually changed
        if changes.key?(:attribute_order)
          # Only attribute order changed
          :attribute_order
        elsif changes.key?(:attributes)
          # Attribute values changed
          :attribute_values
        elsif changes.key?(:value)
          # Text content changed
          :text_content
        elsif changes.key?(:label)
          # Element name changed (rare)
          :element_structure
        else
          # Default to text_content for generic updates
          :text_content
        end
      end

      # Determine if a diff is normative based on match options
      #
      # @param dimension [Symbol] Match dimension
      # @return [Boolean] true if normative (should be shown)
      def determine_normative(dimension)
        # Check match options behavior for this dimension
        behavior = @match_options.behavior_for(dimension)

        # If behavior is :ignore, it's informative (not shown by default)
        # Otherwise it's normative (shown)
        behavior != :ignore
      end

      # Build reason string for INSERT operation
      #
      # @param operation [Operation] Operation
      # @return [String] Reason description
      def build_insert_reason(operation)
        node = operation[:node]
        if node && node.respond_to?(:label)
          "inserted <#{node.label}>"
        else
          "inserted element"
        end
      end

      # Build reason string for DELETE operation
      #
      # @param operation [Operation] Operation
      # @return [String] Reason description
      def build_delete_reason(operation)
        node = operation[:node]
        if node && node.respond_to?(:label)
          "deleted <#{node.label}>"
        else
          "deleted element"
        end
      end

      # Build reason string for UPDATE operation
      #
      # @param operation [Operation] Operation
      # @return [String] Reason description
      def build_update_reason(operation)
        change_type = operation[:change_type] || "content"
        "updated #{change_type}"
      end

      # Build reason string for MOVE operation
      #
      # @param operation [Operation] Operation
      # @return [String] Reason description
      def build_move_reason(operation)
        from_pos = operation[:from_position]
        to_pos = operation[:to_position]

        if from_pos && to_pos
          "moved from position #{from_pos} to #{to_pos}"
        else
          "moved to different position"
        end
      end

      # Detect INSERT/DELETE pairs that differ only in attribute order
      # and reclassify them to use the attribute_order dimension
      #
      # @param diff_nodes [Array<DiffNode>] Diff nodes to process
      # @return [Array<DiffNode>] Processed diff nodes
      def detect_attribute_order_diffs(diff_nodes)
        # Group nodes by parent and element type
        deletes = diff_nodes.select { |dn| dn.node1 && !dn.node2 }
        inserts = diff_nodes.select { |dn| !dn.node1 && dn.node2 }

        # For each DELETE, try to find a matching INSERT
        deletes.each do |delete_node|
          node1 = delete_node.node1
          next unless node1.respond_to?(:name) && node1.respond_to?(:attributes)

          # Find inserts with same element name at same position
          matching_insert = inserts.find do |insert_node|
            node2 = insert_node.node2
            next false unless node2.respond_to?(:name) && node2.respond_to?(:attributes)
            next false unless node1.name == node2.name

            # Check if they differ only in attribute order
            attributes_equal_ignoring_order?(node1.attributes, node2.attributes)
          end

          next unless matching_insert

          # Found an attribute-order-only difference
          # Reclassify both nodes to use attribute_order dimension
          delete_node.dimension = :attribute_order
          delete_node.reason = "attribute order changed"
          delete_node.normative = determine_normative(:attribute_order)

          matching_insert.dimension = :attribute_order
          matching_insert.reason = "attribute order changed"
          matching_insert.normative = determine_normative(:attribute_order)
        end

        diff_nodes
      end

      # Check if two attribute hashes are equal ignoring order
      #
      # @param attrs1 [Hash] First attribute hash
      # @param attrs2 [Hash] Second attribute hash
      # @return [Boolean] True if attributes are equal (ignoring order)
      def attributes_equal_ignoring_order?(attrs1, attrs2)
        return true if attrs1.nil? && attrs2.nil?
        return false if attrs1.nil? || attrs2.nil?

        # Convert to hashes if needed
        attrs1 = attrs1.to_h if attrs1.respond_to?(:to_h)
        attrs2 = attrs2.to_h if attrs2.respond_to?(:to_h)

        # Compare as sets (order-independent)
        attrs1.sort.to_h == attrs2.sort.to_h
      end
    end
  end
end
