# frozen_string_literal: true

module Canon
  module Xml
    # Namespace handler for C14N 1.1
    # Handles namespace declaration processing per spec
    class NamespaceHandler
      def initialize(encoder)
        @encoder = encoder
      end

      # Process namespace axis of an element
      def process_namespaces(element, output, parent_element = nil)
        return unless element.in_node_set?

        namespaces = element.sorted_namespace_nodes.select(&:in_node_set?)

        # Check if we need to emit xmlns="" for empty default namespace
        if should_emit_empty_default_namespace?(element, namespaces,
                                                 parent_element)
          output << ' xmlns=""'
        end

        # Process each namespace node
        namespaces.each do |ns|
          next if should_skip_namespace?(ns, element, parent_element)

          output << " "
          if ns.default_namespace?
            output << "xmlns"
          else
            output << "xmlns:#{ns.prefix}"
          end
          output << '="'
          output << @encoder.encode_attribute(ns.uri)
          output << '"'
        end
      end

      private

      # Check if we should emit xmlns="" for empty default namespace
      # Per spec: emit if and only if:
      # 1. The element E is in the node-set
      # 2. The first namespace node is not the default namespace node
      # 3. The nearest ancestor element of E in the node-set has a
      #    default namespace node in the node-set with non-empty value
      def should_emit_empty_default_namespace?(element, namespaces,
                                               parent_element)
        return false unless element.in_node_set?
        return false if namespaces.first&.default_namespace?
        return false unless parent_element

        # Check if parent has non-empty default namespace
        parent_default_ns = parent_element.namespace_nodes.find do |ns|
          ns.default_namespace? && ns.in_node_set?
        end

        parent_default_ns && !parent_default_ns.uri.empty?
      end

      # Check if a namespace node should be skipped
      def should_skip_namespace?(ns, element, parent_element)
        # Skip xml namespace with standard URI
        return true if ns.xml_namespace?

        # Skip if an ancestor already declared this namespace
        return true if namespace_declared_by_ancestor?(ns, parent_element)

        false
      end

      # Check if a namespace is already declared by an ancestor
      def namespace_declared_by_ancestor?(ns, parent_element)
        return false unless parent_element

        parent_ns = parent_element.namespace_nodes.find do |parent_ns|
          parent_ns.prefix == ns.prefix && parent_ns.in_node_set?
        end

        parent_ns && parent_ns.uri == ns.uri
      end
    end
  end
end
