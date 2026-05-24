# frozen_string_literal: true

module Canon
  module Comparison
    module XmlComparatorHelpers
      # Node type comparison strategy for XML nodes
      #
      # Handles dispatching comparison logic based on node type.
      # Supports both Canon::Xml::Node (with symbolic node_type) and
      # backend nodes (Nokogiri/Moxml) via XmlParsing type checks.
      module NodeTypeComparator
        class << self
          def compare(node1, node2, comparator, opts, child_opts,
diff_children, differences)
            if node1.is_a?(Canon::Xml::Node) && node2.is_a?(Canon::Xml::Node)
              compare_by_symbolic_type(node1, node2, comparator, opts, child_opts,
                                       diff_children, differences)
            else
              compare_by_backend_type(node1, node2, comparator, opts, child_opts,
                                      diff_children, differences)
            end
          end

          private

          def compare_by_symbolic_type(node1, node2, comparator, opts, child_opts,
                                       diff_children, differences)
            case node1.node_type
            when :root
              comparator.compare_children(node1, node2, opts, child_opts,
                                          diff_children, differences)
            when :element
              comparator.compare_element_nodes(node1, node2, opts, child_opts,
                                               diff_children, differences)
            when :text
              comparator.compare_text_nodes(node1, node2, opts, differences)
            when :comment
              comparator.compare_comment_nodes(node1, node2, opts, differences)
            when :cdata
              comparator.compare_text_nodes(node1, node2, opts, differences)
            when :processing_instruction
              comparator.compare_processing_instruction_nodes(node1, node2, opts,
                                                              differences)
            else
              Comparison::EQUIVALENT
            end
          end

          def compare_by_backend_type(node1, node2, comparator, opts, child_opts,
                                      diff_children, differences)
            if Canon::XmlParsing.element?(node1)
              comparator.compare_element_nodes(node1, node2, opts, child_opts,
                                               diff_children, differences)
            elsif Canon::XmlParsing.text_node?(node1)
              comparator.compare_text_nodes(node1, node2, opts, differences)
            elsif Canon::XmlParsing.comment?(node1)
              comparator.compare_comment_nodes(node1, node2, opts, differences)
            elsif Canon::XmlParsing.cdata?(node1)
              comparator.compare_text_nodes(node1, node2, opts, differences)
            elsif Canon::XmlParsing.processing_instruction?(node1)
              comparator.compare_processing_instruction_nodes(node1, node2, opts,
                                                              differences)
            elsif Canon::XmlParsing.document?(node1)
              comparator.compare_document_nodes(node1, node2, opts, child_opts,
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
