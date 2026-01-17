# frozen_string_literal: true

module Canon
  module Comparison
    # Base class for markup document comparison (XML/HTML)
    #
    # Provides common comparison functionality for markup-based formats.
    # Subclasses (XmlComparer, HtmlComparer) provide format-specific behavior.
    #
    # @abstract Subclass and override format-specific methods
    class MarkupComparer
      class << self
        # Compare two markup documents
        #
        # @param doc1 [String, Object] First document
        # @param doc2 [String, Object] Second document
        # @param opts [Hash] Comparison options
        # @return [Boolean, ComparisonResult] Result of comparison
        def compare(doc1, doc2, opts = {})
          raise NotImplementedError, "Subclass must implement #compare"
        end

        # Parse a document from string or return as-is
        #
        # @param doc [String, Object] Document to parse
        # @param preprocessing [Symbol] Preprocessing option
        # @return [Object] Parsed document
        def parse_document(doc, preprocessing = :none)
          raise NotImplementedError, "Subclass must implement #parse_document"
        end

        # Serialize a document to string for display
        #
        # @param doc [Object] Document to serialize
        # @return [String] Serialized document
        def serialize_document(doc)
          raise NotImplementedError,
                "Subclass must implement #serialize_document"
        end

        # Main comparison dispatcher for markup nodes
        #
        # This method handles the high-level comparison logic, delegating
        # to specific comparison methods based on node types.
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param opts [Hash] Comparison options
        # @param child_opts [Hash] Options for child comparison
        # @param diff_children [Boolean] Whether to diff children
        # @param differences [Array] Array to append differences to
        # @return [Symbol] Comparison result constant
        def compare_nodes(node1, node2, opts, child_opts, diff_children,
differences)
          # Handle DocumentFragment nodes - compare their children instead
          if node1.is_a?(Nokogiri::XML::DocumentFragment) &&
              node2.is_a?(Nokogiri::XML::DocumentFragment)
            return compare_document_fragments(node1, node2, opts, child_opts,
                                              diff_children, differences)
          end

          # Check if nodes should be excluded
          return Comparison::EQUIVALENT if node_excluded?(node1, opts) &&
            node_excluded?(node2, opts)

          if node_excluded?(node1, opts) || node_excluded?(node2, opts)
            add_difference(node1, node2, Comparison::MISSING_NODE,
                           Comparison::MISSING_NODE, :text_content, opts,
                           differences)
            return Comparison::MISSING_NODE
          end

          # Check node types match
          unless same_node_type?(node1, node2)
            add_difference(node1, node2, Comparison::UNEQUAL_NODES_TYPES,
                           Comparison::UNEQUAL_NODES_TYPES, :text_content, opts,
                           differences)
            return Comparison::UNEQUAL_NODES_TYPES
          end

          # Dispatch based on node type
          dispatch_by_node_type(node1, node2, opts, child_opts, diff_children,
                                differences)
        end

        # Filter children based on options
        #
        # Removes nodes that should be excluded from comparison based on
        # options like :ignore_nodes, :ignore_comments, etc.
        #
        # @param children [Array] Array of child nodes
        # @param opts [Hash] Comparison options
        # @return [Array] Filtered array of children
        def filter_children(children, opts)
          children.reject do |child|
            node_excluded?(child, opts)
          end
        end

        private

        # Compare document fragments by comparing their children
        #
        # @param node1 [Nokogiri::XML::DocumentFragment] First fragment
        # @param node2 [Nokogiri::XML::DocumentFragment] Second fragment
        # @param opts [Hash] Comparison options
        # @param child_opts [Hash] Options for child comparison
        # @param diff_children [Boolean] Whether to diff children
        # @param differences [Array] Array to append differences to
        # @return [Symbol] Comparison result constant
        def compare_document_fragments(node1, node2, opts, child_opts,
                                       diff_children, differences)
          children1 = node1.children.to_a
          children2 = node2.children.to_a

          if children1.length != children2.length
            add_difference(node1, node2, Comparison::UNEQUAL_ELEMENTS,
                           Comparison::UNEQUAL_ELEMENTS, :text_content, opts,
                           differences)
            Comparison::UNEQUAL_ELEMENTS
          elsif children1.empty?
            Comparison::EQUIVALENT
          else
            # Compare each pair of children
            result = Comparison::EQUIVALENT
            children1.zip(children2).each do |child1, child2|
              child_result = compare_nodes(child1, child2, opts, child_opts,
                                           diff_children, differences)
              result = child_result unless result == Comparison::EQUIVALENT
            end
            result
          end
        end

        # Dispatch comparison based on node type
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param opts [Hash] Comparison options
        # @param child_opts [Hash] Options for child comparison
        # @param diff_children [Boolean] Whether to diff children
        # @param differences [Array] Array to append differences to
        # @return [Symbol] Comparison result constant
        def dispatch_by_node_type(node1, node2, opts, child_opts,
diff_children, differences)
          # Canon::Xml::Node types use .node_type method that returns symbols
          # Nokogiri also has .node_type but returns integers, so check for Symbol
          if node1.respond_to?(:node_type) && node2.respond_to?(:node_type) &&
              node1.node_type.is_a?(Symbol) && node2.node_type.is_a?(Symbol)
            dispatch_canon_node_type(node1, node2, opts, child_opts,
                                     diff_children, differences)
          # Moxml/Nokogiri types use .element?, .text?, etc. methods
          else
            dispatch_legacy_node_type(node1, node2, opts, child_opts,
                                      diff_children, differences)
          end
        end

        # Dispatch by Canon::Xml::Node type
        def dispatch_canon_node_type(node1, node2, opts, child_opts,
diff_children, differences)
          require_relative "../xml_comparator"

          case node1.node_type
          when :root
            XmlComparator.compare_children(node1, node2, opts, child_opts,
                                           diff_children, differences)
          when :element
            XmlComparator.compare_element_nodes(node1, node2, opts, child_opts,
                                                diff_children, differences)
          when :text
            XmlComparator.compare_text_nodes(node1, node2, opts, differences)
          when :comment
            XmlComparator.compare_comment_nodes(node1, node2, opts, differences)
          when :cdata
            XmlComparator.compare_text_nodes(node1, node2, opts, differences)
          when :processing_instruction
            XmlComparator.compare_processing_instruction_nodes(node1, node2,
                                                               opts, differences)
          else
            Comparison::EQUIVALENT
          end
        end

        # Dispatch by legacy Nokogiri/Moxml node type
        def dispatch_legacy_node_type(node1, node2, opts, child_opts,
diff_children, differences)
          require_relative "../xml_comparator"

          if node1.respond_to?(:element?) && node1.element?
            XmlComparator.compare_element_nodes(node1, node2, opts, child_opts,
                                                diff_children, differences)
          elsif node1.respond_to?(:text?) && node1.text?
            XmlComparator.compare_text_nodes(node1, node2, opts, differences)
          elsif node1.respond_to?(:comment?) && node1.comment?
            XmlComparator.compare_comment_nodes(node1, node2, opts, differences)
          elsif node1.respond_to?(:cdata?) && node1.cdata?
            XmlComparator.compare_text_nodes(node1, node2, opts, differences)
          elsif node1.respond_to?(:processing_instruction?) && node1.processing_instruction?
            XmlComparator.compare_processing_instruction_nodes(node1, node2,
                                                               opts, differences)
          elsif node1.respond_to?(:root)
            XmlComparator.compare_document_nodes(node1, node2, opts,
                                                 child_opts, diff_children, differences)
          else
            Comparison::EQUIVALENT
          end
        end

        # Check if a node should be excluded from comparison
        #
        # @param node [Object] Node to check
        # @param opts [Hash] Comparison options
        # @return [Boolean] true if node should be excluded
        def node_excluded?(node, opts)
          return false if node.nil?
          return true if opts[:ignore_nodes]&.include?(node)
          return true if opts[:ignore_comments] && comment_node?(node)
          return true if opts[:ignore_text_nodes] && text_node?(node)

          false
        end

        # Check if two nodes are of the same type
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @return [Boolean] true if nodes are same type
        def same_node_type?(node1, node2)
          return false if node1.class != node2.class

          # For Nokogiri/Canon::Xml nodes, check node type
          if node1.respond_to?(:node_type) && node2.respond_to?(:node_type)
            node1.node_type == node2.node_type
          else
            true
          end
        end

        # Check if a node is a comment node
        #
        # @param node [Object] Node to check
        # @return [Boolean] true if node is a comment
        def comment_node?(node)
          node.respond_to?(:comment?) && node.comment? ||
            node.respond_to?(:node_type) && node.node_type == :comment
        end

        # Check if a node is a text node
        #
        # @param node [Object] Node to check
        # @return [Boolean] true if node is a text node
        def text_node?(node)
          node.respond_to?(:text?) && node.text? &&
            !node.respond_to?(:element?) ||
            node.respond_to?(:node_type) && node.node_type == :text
        end

        # Add a difference to the differences array
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param diff1 [Symbol] Difference type for node1
        # @param diff2 [Symbol] Difference type for node2
        # @param dimension [Symbol] The dimension of the difference
        # @param opts [Hash] Comparison options
        # @param differences [Array] Array to append difference to
        def add_difference(node1, node2, diff1, diff2, dimension, opts,
differences)
          return unless opts[:verbose]

          require_relative "../xml_comparator"
          XmlComparator.add_difference(node1, node2, diff1, diff2, dimension,
                                       opts, differences)
        end
      end
    end
  end
end
