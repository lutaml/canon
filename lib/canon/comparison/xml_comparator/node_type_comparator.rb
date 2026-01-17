# frozen_string_literal: true

module Canon
  module Comparison
    module XmlComparatorHelpers
      # Node type comparison strategy for XML nodes
      #
      # Handles dispatching comparison logic based on node type.
      # Supports both Canon::Xml::Node (with symbolic node_type) and
      # Moxml/Nokogiri nodes (with predicate methods like element?, text?, etc.)
      #
      # This module encapsulates the complex node type detection and dispatch
      # logic, making the main XmlComparator cleaner and more maintainable.
      module NodeTypeComparator
        class << self
          # Compare two nodes by dispatching to appropriate comparison method
          #
          # @param node1 [Object] First node
          # @param node2 [Object] Second node
          # @param comparator [XmlComparator] The comparator instance for method delegation
          # @param opts [Hash] Comparison options
          # @param child_opts [Hash] Options for child comparison
          # @param diff_children [Boolean] Whether to diff children
          # @param differences [Array] Array to collect differences
          # @return [Integer] Comparison result code
          def compare(node1, node2, comparator, opts, child_opts, diff_children, differences)
            # Dispatch based on node type
            # Canon::Xml::Node types use .node_type method that returns symbols
            # Nokogiri also has .node_type but returns integers, so check for Symbol
            if node1.respond_to?(:node_type) && node2.respond_to?(:node_type) &&
                node1.node_type.is_a?(Symbol) && node2.node_type.is_a?(Symbol)
              compare_by_symbolic_type(node1, node2, comparator, opts, child_opts,
                                       diff_children, differences)
            # Moxml/Nokogiri types use .element?, .text?, etc. methods
            else
              compare_by_predicate_methods(node1, node2, comparator, opts, child_opts,
                                           diff_children, differences)
            end
          end

          private

          # Compare nodes using symbolic node_type (Canon::Xml::Node)
          def compare_by_symbolic_type(node1, node2, comparator, opts, child_opts,
                                       diff_children, differences)
            case node1.node_type
            when :root
              comparator.send(:compare_children, node1, node2, opts, child_opts,
                              diff_children, differences)
            when :element
              comparator.send(:compare_element_nodes, node1, node2, opts, child_opts,
                              diff_children, differences)
            when :text
              comparator.send(:compare_text_nodes, node1, node2, opts, differences)
            when :comment
              comparator.send(:compare_comment_nodes, node1, node2, opts, differences)
            when :cdata
              comparator.send(:compare_text_nodes, node1, node2, opts, differences)
            when :processing_instruction
              comparator.send(:compare_processing_instruction_nodes, node1, node2, opts,
                              differences)
            else
              Comparison::EQUIVALENT
            end
          end

          # Compare nodes using predicate methods (Moxml/Nokogiri)
          def compare_by_predicate_methods(node1, node2, comparator, opts, child_opts,
                                           diff_children, differences)
            if node1.respond_to?(:element?) && node1.element?
              comparator.send(:compare_element_nodes, node1, node2, opts, child_opts,
                              diff_children, differences)
            elsif node1.respond_to?(:text?) && node1.text?
              comparator.send(:compare_text_nodes, node1, node2, opts, differences)
            elsif node1.respond_to?(:comment?) && node1.comment?
              comparator.send(:compare_comment_nodes, node1, node2, opts, differences)
            elsif node1.respond_to?(:cdata?) && node1.cdata?
              comparator.send(:compare_text_nodes, node1, node2, opts, differences)
            elsif node1.respond_to?(:processing_instruction?) &&
                node1.processing_instruction?
              comparator.send(:compare_processing_instruction_nodes, node1, node2, opts,
                              differences)
            elsif node1.respond_to?(:root)
              # Document node (Moxml/Nokogiri - legacy path)
              comparator.send(:compare_document_nodes, node1, node2, opts, child_opts,
                              diff_children, differences)
            else
              Comparison::EQUIVALENT
            end
          end
        end
      end
    end
  end
end
