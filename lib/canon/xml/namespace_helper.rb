# frozen_string_literal: true

module Canon
  module Xml
    # Helper module for formatting namespace information in diff output
    module NamespaceHelper
      # Format a namespace URI for display in diff output
      #
      # @param namespace_uri [String, nil] The namespace URI to format
      # @return [String] Formatted namespace string
      #
      # @example Empty namespace
      #   format_namespace(nil) #=> "ns:[{blank}]"
      #   format_namespace("") #=> "ns:[{blank}]"
      #
      # @example Populated namespace
      #   format_namespace("http://example.com") #=> "ns:[http://example.com]"
      def self.format_namespace(namespace_uri)
        if namespace_uri.nil? || namespace_uri.empty?
          "ns:[{blank}]"
        else
          "ns:[#{namespace_uri}]"
        end
      end

      # Determine the type of mismatch between two nodes
      #
      # @param node1 [Object] First node (ElementNode or AttributeNode)
      # @param node2 [Object] Second node (ElementNode or AttributeNode)
      # @return [Symbol] Type of mismatch (:name, :namespace, :both, :none)
      def self.mismatch_type(node1, node2)
        return :none unless node1 && node2

        name_differs = node1.name != node2.name
        namespace_differs = normalize_namespace(node1.namespace_uri) !=
          normalize_namespace(node2.namespace_uri)

        if name_differs && namespace_differs
          :both
        elsif name_differs
          :name
        elsif namespace_differs
          :namespace
        else
          :none
        end
      end

      # Generate a mismatch message for element differences
      #
      # @param node1 [ElementNode] First element
      # @param node2 [ElementNode] Second element
      # @return [String] Human-readable mismatch message
      def self.element_mismatch_message(node1, node2)
        type = mismatch_type(node1, node2)

        case type
        when :name
          ns = format_namespace(node1.namespace_uri)
          "mismatched element name: '#{node1.name}' vs '#{node2.name}' (#{ns})"
        when :namespace
          "mismatched element namespace: '#{node1.name}' " \
          "(#{format_namespace(node1.namespace_uri)} vs " \
          "#{format_namespace(node2.namespace_uri)})"
        when :both
          "mismatched element name and namespace: " \
          "'#{node1.name}' (#{format_namespace(node1.namespace_uri)}) vs " \
          "'#{node2.name}' (#{format_namespace(node2.namespace_uri)})"
        else
          "elements differ"
        end
      end

      # Generate a mismatch message for attribute differences
      #
      # @param node1 [AttributeNode] First attribute
      # @param node2 [AttributeNode] Second attribute
      # @return [String] Human-readable mismatch message
      def self.attribute_mismatch_message(node1, node2)
        type = mismatch_type(node1, node2)

        case type
        when :name
          ns = format_namespace(node1.namespace_uri)
          "mismatched attribute name: '#{node1.name}' vs '#{node2.name}' (#{ns})"
        when :namespace
          "mismatched attribute namespace: '#{node1.name}' " \
          "(#{format_namespace(node1.namespace_uri)} vs " \
          "#{format_namespace(node2.namespace_uri)})"
        when :both
          "mismatched attribute name and namespace: " \
          "'#{node1.name}' (#{format_namespace(node1.namespace_uri)}) vs " \
          "'#{node2.name}' (#{format_namespace(node2.namespace_uri)})"
        else
          "attributes differ"
        end
      end

      # Normalize namespace URI for comparison
      #
      # @param namespace_uri [String, nil] Namespace URI
      # @return [String] Normalized namespace (empty string for nil)
      def self.normalize_namespace(namespace_uri)
        namespace_uri.to_s
      end

      private_class_method :normalize_namespace
    end
  end
end
