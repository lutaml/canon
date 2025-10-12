# frozen_string_literal: true

module Canon
  module Xml
    # Attribute handler for C14N 1.1
    # Handles attribute processing per spec
    class AttributeHandler
      def initialize(encoder)
        @encoder = encoder
      end

      # Process attribute axis of an element
      # Includes handling of simple inheritable attributes for document subsets
      def process_attributes(element, output, omitted_ancestors = [])
        return unless element.in_node_set?

        # Collect attributes including inherited simple inheritable ones
        attributes = collect_attributes(element, omitted_ancestors)

        # Sort and process attributes
        attributes.each do |attr|
          output << " "
          output << attr.qname
          output << '="'
          output << @encoder.encode_attribute(attr.value)
          output << '"'
        end
      end

      private

      # Collect attributes including inherited simple inheritable attributes
      def collect_attributes(element, omitted_ancestors)
        attributes = element.sorted_attribute_nodes.select(&:in_node_set?)

        # Add inherited simple inheritable attributes if needed
        if omitted_ancestors.any?
          inherited = collect_inherited_attributes(element, omitted_ancestors)
          attributes = merge_attributes(attributes, inherited)
        end

        attributes
      end

      # Collect simple inheritable attributes from omitted ancestors
      def collect_inherited_attributes(element, omitted_ancestors)
        inherited = []
        seen = Set.new

        # Track which simple inheritable attributes element already has
        element.attribute_nodes.each do |attr|
          seen.add(attr.name) if attr.simple_inheritable?
        end

        # Walk up omitted ancestors to find inheritable attributes
        omitted_ancestors.reverse.each do |ancestor|
          ancestor.attribute_nodes.each do |attr|
            next unless attr.simple_inheritable?
            next if seen.include?(attr.name)

            inherited << attr
            seen.add(attr.name)
          end
        end

        inherited
      end

      # Merge and sort attributes
      def merge_attributes(element_attrs, inherited_attrs)
        all_attrs = element_attrs + inherited_attrs
        all_attrs.sort_by do |attr|
          [attr.namespace_uri.to_s, attr.local_name]
        end
      end
    end
  end
end
