# frozen_string_literal: true

require_relative "character_encoder"
require_relative "namespace_handler"
require_relative "attribute_handler"
require_relative "xml_base_handler"

module Canon
  module Xml
    # C14N 1.1 processor
    # Processes XPath data model and generates canonical form
    class Processor
      def initialize(with_comments: false)
        @with_comments = with_comments
        @encoder = CharacterEncoder.new
        @namespace_handler = NamespaceHandler.new(@encoder)
        @attribute_handler = AttributeHandler.new(@encoder)
        @xml_base_handler = XmlBaseHandler.new
      end

      # Process a node-set and generate canonical form
      def process(root_node)
        output = String.new(encoding: "UTF-8")
        process_node(root_node, output)
        output
      end

      private

      def process_node(node, output, parent_element = nil,
                       omitted_ancestors = [])
        case node.node_type
        when :root
          process_root_node(node, output)
        when :element
          process_element_node(node, output, parent_element,
                               omitted_ancestors)
        when :text
          process_text_node(node, output)
        when :comment
          process_comment_node(node, output, parent_element)
        when :processing_instruction
          process_pi_node(node, output, parent_element)
        end
      end

      def process_root_node(node, output)
        # Process children in document order
        node.children.each do |child|
          process_node(child, output)
        end
      end

      def process_element_node(node, output, parent_element,
                               omitted_ancestors)
        if node.in_node_set?
          # Element is in node-set, render it
          render_element(node, output, parent_element, omitted_ancestors)
        else
          # Element is not in node-set, but process its children
          new_omitted = omitted_ancestors + [node]
          node.children.each do |child|
            process_node(child, output, parent_element, new_omitted)
          end
        end
      end

      def render_element(node, output, parent_element, omitted_ancestors)
        # Opening tag
        output << "<" << node.qname

        # Process namespace axis
        @namespace_handler.process_namespaces(node, output, parent_element)

        # Process attribute axis with xml:base fixup if needed
        process_element_attributes(node, output, omitted_ancestors)

        output << ">"

        # Process children
        node.children.each do |child|
          process_node(child, output, node, [])
        end

        # Closing tag
        output << "</" << node.qname << ">"
      end

      def process_element_attributes(node, output, omitted_ancestors)
        # First process regular attributes
        @attribute_handler.process_attributes(node, output,
                                              omitted_ancestors)

        # Then handle xml:base fixup if needed
        if omitted_ancestors.any?
          fixed_base = @xml_base_handler.fixup_xml_base(node,
                                                         omitted_ancestors)
          if fixed_base && !fixed_base.empty?
            # Check if element already has xml:base
            has_base = node.attribute_nodes.any?(&:xml_base?)
            unless has_base
              output << ' xml:base="'
              output << @encoder.encode_attribute(fixed_base)
              output << '"'
            end
          end
        end
      end

      def process_text_node(node, output)
        return unless node.in_node_set?

        output << @encoder.encode_text(node.value)
      end

      def process_comment_node(node, output, parent_element)
        return unless @with_comments
        return unless node.in_node_set?

        # Add line break before comment if it's outside document element
        output << "\n" if parent_element.nil? && output.length > 0

        output << "<!--" << node.value << "-->"

        # Add line break after comment if it's outside document element
        output << "\n" if parent_element.nil?
      end

      def process_pi_node(node, output, parent_element)
        return unless node.in_node_set?

        # Add line break before PI if it's outside document element
        output << "\n" if parent_element.nil? && output.length > 0

        output << "<?" << node.target

        unless node.data.empty?
          output << " " << node.data
        end

        output << "?>"

        # Add line break after PI if it's outside document element
        output << "\n" if parent_element.nil?
      end
    end
  end
end
