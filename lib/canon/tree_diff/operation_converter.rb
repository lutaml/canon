# frozen_string_literal: true

require_relative "../diff/diff_node"
require_relative "../comparison/match_options"
# OperationConverter helper modules
require_relative "operation_converter_helpers/metadata_enricher"
require_relative "operation_converter_helpers/reason_builder"
require_relative "operation_converter_helpers/post_processor"
require_relative "operation_converter_helpers/update_change_handler"

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

      # Metadata/presentation elements that should be treated as informative
      # These elements don't affect semantic equivalence
      METADATA_ELEMENTS = %w[
        semx fmt-concept fmt-name fmt-title fmt-xref fmt-eref
        fmt-termref fmt-element-name fmt-link autonum
        meta link base title style script
      ].freeze

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
                              match: match_options,
                            )
                          when :json
                            Canon::Comparison::MatchOptions::Json.resolve(
                              format: format,
                              match: match_options,
                            )
                          when :yaml
                            Canon::Comparison::MatchOptions::Yaml.resolve(
                              format: format,
                              match: match_options,
                            )
                          else
                            raise ArgumentError, "Unknown format: #{format}"
                          end

        # Wrap in ResolvedMatchOptions
        @match_options = Canon::Comparison::ResolvedMatchOptions.new(
          match_opts_hash,
          format: format,
        )
      end

      # Convert array of Operations to array of DiffNodes
      #
      # @param operations [Array<Operation>] Operations to convert
      # @return [Array<DiffNode>] Converted diff nodes
      def convert(operations)
        diff_nodes = operations.flat_map do |operation|
          convert_operation(operation)
        end

        # Post-process to detect attribute-order-only differences
        OperationConverterHelpers::PostProcessor.detect_attribute_order_diffs(
          diff_nodes,
          ->(dimension) { determine_normative(dimension) }
        )
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
        tree_node2 = operation[:node] # TreeNode from adapter
        node2 = extract_source_node(tree_node2)

        # Enrich with path and serialized content
        metadata = OperationConverterHelpers::MetadataEnricher.enrich(nil, tree_node2, @format)

        diff_node = Canon::Diff::DiffNode.new(
          node1: nil,
          node2: node2,
          dimension: :element_structure,
          reason: OperationConverterHelpers::ReasonBuilder.build_insert_reason(operation),
          **metadata,
        )
        # Metadata elements are informative (don't affect equivalence)
        diff_node.normative = metadata_element?(node2) ? false : determine_normative(:element_structure)
        diff_node
      end

      # Convert DELETE operation to DiffNode
      #
      # @param operation [Operation] Delete operation
      # @return [DiffNode] Diff node representing deletion
      def convert_delete(operation)
        tree_node1 = operation[:node] # TreeNode from adapter
        node1 = extract_source_node(tree_node1)

        # Enrich with path and serialized content
        metadata = OperationConverterHelpers::MetadataEnricher.enrich(tree_node1, nil, @format)

        diff_node = Canon::Diff::DiffNode.new(
          node1: node1,
          node2: nil,
          dimension: :element_structure,
          reason: OperationConverterHelpers::ReasonBuilder.build_delete_reason(operation),
          **metadata,
        )
        # Metadata elements are informative (don't affect equivalence)
        diff_node.normative = metadata_element?(node1) ? false : determine_normative(:element_structure)
        diff_node
      end

      # Convert UPDATE operation to DiffNode(s)
      #
      # May return multiple DiffNodes if multiple dimensions changed
      #
      # @param operation [Operation] Update operation
      # @return [Array<DiffNode>] Diff nodes representing updates
      def convert_update(operation)
        tree_node1 = operation[:node1] # TreeNode from adapter
        tree_node2 = operation[:node2] # TreeNode from adapter

        # Enrich with path and serialized content (shared by all DiffNodes from this operation)
        metadata = OperationConverterHelpers::MetadataEnricher.enrich(tree_node1, tree_node2, @format)

        # Check if nodes are metadata elements
        node1 = extract_source_node(tree_node1)
        node2 = extract_source_node(tree_node2)
        is_metadata = metadata_element?(node1) || metadata_element?(node2)

        # Use UpdateChangeHandler to process different change types
        diff_nodes = OperationConverterHelpers::UpdateChangeHandler.convert(
          operation,
          metadata,
          is_metadata,
          ->(dimension) { determine_normative(dimension) }
        )

        diff_nodes
      end

      # Convert MOVE operation to DiffNode
      #
      # @param operation [Operation] Move operation
      # @return [DiffNode] Diff node representing move
      def convert_move(operation)
        tree_node1 = operation[:node1]
        tree_node2 = operation[:node2]
        node1 = extract_source_node(tree_node1)
        node2 = extract_source_node(tree_node2)

        # Enrich with path and serialized content
        metadata = OperationConverterHelpers::MetadataEnricher.enrich(tree_node1, tree_node2, @format)

        diff_node = Canon::Diff::DiffNode.new(
          node1: node1,
          node2: node2,
          dimension: :element_position,
          reason: OperationConverterHelpers::ReasonBuilder.build_move_reason(operation),
          **metadata,
        )
        # Metadata elements are informative (don't affect equivalence)
        is_metadata = metadata_element?(node1) || metadata_element?(node2)
        diff_node.normative = is_metadata ? false : determine_normative(:element_position)
        diff_node
      end

      # Convert MERGE operation to DiffNode
      #
      # @param operation [Operation] Merge operation
      # @return [DiffNode] Diff node representing merge
      def convert_merge(operation)
        # Merge combines multiple nodes into one
        # node1 represents the source nodes, node2 is the merged result
        tree_node1 = operation[:nodes]&.first
        tree_node2 = operation[:result]
        node1 = extract_source_node(tree_node1)
        node2 = extract_source_node(tree_node2)

        # Enrich with path and serialized content
        metadata = OperationConverterHelpers::MetadataEnricher.enrich(tree_node1, tree_node2, @format)

        diff_node = Canon::Diff::DiffNode.new(
          node1: node1,
          node2: node2,
          dimension: :element_structure,
          reason: "merged #{operation[:nodes]&.length || 0} nodes",
          **metadata,
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
        tree_node1 = operation[:node]
        tree_node2 = operation[:results]&.first
        node1 = extract_source_node(tree_node1)
        node2 = extract_source_node(tree_node2)

        # Enrich with path and serialized content
        metadata = OperationConverterHelpers::MetadataEnricher.enrich(tree_node1, tree_node2, @format)

        diff_node = Canon::Diff::DiffNode.new(
          node1: node1,
          node2: node2,
          dimension: :element_structure,
          reason: "split into #{operation[:results]&.length || 0} nodes",
          **metadata,
        )
        diff_node.normative = true # Splits are structural changes, always normative
        diff_node
      end

      # Convert UPGRADE operation to DiffNode (promote/decrease depth)
      #
      # @param operation [Operation] Upgrade operation
      # @return [DiffNode] Diff node representing upgrade
      def convert_upgrade(operation)
        tree_node1 = operation[:node1]
        tree_node2 = operation[:node2]
        node1 = extract_source_node(tree_node1)
        node2 = extract_source_node(tree_node2)

        # Enrich with path and serialized content
        metadata = OperationConverterHelpers::MetadataEnricher.enrich(tree_node1, tree_node2, @format)

        diff_node = Canon::Diff::DiffNode.new(
          node1: node1,
          node2: node2,
          dimension: :element_hierarchy,
          reason: "promoted to higher level",
          **metadata,
        )
        diff_node.normative = determine_normative(:element_hierarchy)
        diff_node
      end

      # Convert DOWNGRADE operation to DiffNode (demote/increase depth)
      #
      # @param operation [Operation] Downgrade operation
      # @return [DiffNode] Diff node representing downgrade
      def convert_downgrade(operation)
        tree_node1 = operation[:node1]
        tree_node2 = operation[:node2]
        node1 = extract_source_node(tree_node1)
        node2 = extract_source_node(tree_node2)

        # Enrich with path and serialized content
        metadata = OperationConverterHelpers::MetadataEnricher.enrich(tree_node1, tree_node2, @format)

        diff_node = Canon::Diff::DiffNode.new(
          node1: node1,
          node2: node2,
          dimension: :element_hierarchy,
          reason: "demoted to lower level",
          **metadata,
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

      # Check if a node is a metadata/presentation element
      #
      # @param node [Object] Node to check (could be TreeNode or Nokogiri node)
      # @return [Boolean] true if node is a metadata element
      def metadata_element?(node)
        return false if node.nil?

        # Get element name from node
        element_name = if node.respond_to?(:label)
                         node.label # TreeNode
                       elsif node.respond_to?(:name)
                         node.name # Nokogiri node
                       else
                         return false
                       end

        # Check if it's in our metadata elements list
        METADATA_ELEMENTS.include?(element_name)
      end
    end
  end
end
