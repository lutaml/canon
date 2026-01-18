# frozen_string_literal: true

require_relative "../../xml/namespace_helper"

module Canon
  class DiffFormatter
    module DiffDetailFormatterHelpers
      # Node utility methods
      #
      # Provides helper methods for extracting information from nodes.
      module NodeUtils
        # Get attribute names from a node
        #
        # @param node [Object] Node to extract attributes from
        # @return [Array<String>] Array of attribute names
        def self.get_attribute_names(node)
          return [] unless node

          attrs = if node.respond_to?(:attribute_nodes)
                    node.attribute_nodes
                  elsif node.respond_to?(:attributes)
                    node.attributes
                  elsif node.respond_to?(:[]) && node.respond_to?(:each)
                    # Hash-like node
                    node.keys
                  else
                    []
                  end

          return [] unless attrs

          # Handle different attribute formats
          if attrs.is_a?(Array)
            attrs.map { |attr| attr.respond_to?(:name) ? attr.name : attr.to_s }
          elsif attrs.respond_to?(:keys)
            attrs.keys.map(&:to_s)
          else
            []
          end
        end

        # Find all differing attributes between two nodes
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @return [Array<String>] Array of attribute names with different values
        def self.find_all_differing_attributes(node1, node2)
          return [] unless node1 && node2

          attrs1 = get_attributes_hash(node1)
          attrs2 = get_attributes_hash(node2)

          all_keys = (attrs1.keys | attrs2.keys)

          all_keys.reject do |key|
            attrs1[key.to_s] == attrs2[key.to_s]
          end
        end

        # Get attribute names in order from a node
        #
        # @param node [Object] Node to extract from
        # @return [Array<String>] Ordered array of attribute names
        def self.get_attribute_names_in_order(node)
          return [] unless node

          attrs = if node.respond_to?(:attribute_nodes)
                    node.attribute_nodes
                  elsif node.respond_to?(:attributes)
                    node.attributes
                  else
                    []
                  end

          return [] unless attrs

          if attrs.is_a?(Array)
            attrs.map { |attr| attr.respond_to?(:name) ? attr.name : attr.to_s }
          else
            attrs.keys.map(&:to_s)
          end
        end

        # Get attributes as a hash
        #
        # @param node [Object] Node to extract from
        # @return [Hash] Attributes hash
        def self.get_attributes_hash(node)
          return {} unless node

          attrs = if node.respond_to?(:attribute_nodes)
                    node.attribute_nodes
                  elsif node.respond_to?(:attributes)
                    node.attributes
                  else
                    {}
                  end

          return {} unless attrs

          result = {}
          if attrs.is_a?(Array)
            attrs.each do |attr|
              name = attr.respond_to?(:name) ? attr.name : attr.to_s
              value = attr.respond_to?(:value) ? attr.value : attr.to_s
              result[name] = value
            end
          elsif attrs.respond_to?(:each)
            attrs.each do |key, val|
              name = key.to_s
              value = if val.respond_to?(:value)
                        val.value
                      elsif val.respond_to?(:content)
                        val.content
                      else
                        val.to_s
                      end
              result[name] = value
            end
          end

          result
        end

        # Get attribute value from a node
        #
        # @param node [Object] Node to extract from
        # @param attr_name [String] Attribute name
        # @return [String, nil] Attribute value or nil
        def self.get_attribute_value(node, attr_name)
          return nil unless node && attr_name

          if node.respond_to?(:[])
            value = node[attr_name]
            if value.respond_to?(:value)
              value.value
            elsif value.respond_to?(:content)
              value.content
            elsif value.respond_to?(:to_s)
              value.to_s
            else
              value
            end
          elsif node.respond_to?(:get_attribute)
            attr = node.get_attribute(attr_name)
            attr.respond_to?(:value) ? attr.value : attr
          end
        end

        # Get text content from a node
        #
        # @param node [Object] Node to extract from
        # @return [String] Text content
        def self.get_node_text(node)
          return "" unless node

          if node.respond_to?(:text)
            node.text
          elsif node.respond_to?(:content)
            node.content
          elsif node.respond_to?(:inner_text)
            node.inner_text
          else
            ""
          end.to_s.strip
        end

        # Get element name for display
        #
        # @param node [Object] Node to get name from
        # @return [String] Element name
        def self.get_element_name_for_display(node)
          return "" unless node

          if node.respond_to?(:name)
            node.name.to_s
          else
            node.class.name
          end
        end

        # Get namespace URI for display
        #
        # @param node [Object] Node to get namespace from
        # @return [String] Namespace URI
        def self.get_namespace_uri_for_display(node)
          return "" unless node

          if node.respond_to?(:namespace_uri)
            node.namespace_uri.to_s
          elsif node.respond_to?(:namespace)
            ns = node.namespace
            ns.respond_to?(:href) ? ns.href.to_s : ""
          else
            ""
          end
        end

        # Format node briefly for display
        #
        # @param node [Object] Node to format
        # @return [String] Brief node description
        def self.format_node_brief(node)
          return "" unless node

          name = get_element_name_for_display(node)
          text = get_node_text(node)

          if text && !text.empty?
            "#{name}(\"#{text}\")"
          else
            name
          end
        end

        # Check if node is inside a preserve-whitespace element
        #
        # @param node [Object] Node to check
        # @return [Boolean] true if inside preserve element
        def self.inside_preserve_element?(node)
          return false unless node

          preserve_elements = %w[pre code textarea script style]

          # Check the node itself
          if node.respond_to?(:name) && preserve_elements.include?(node.name.to_s.downcase)
            return true
          end

          # Check ancestors
          current = node
          while current
            if current.respond_to?(:parent)
              current = current.parent
            elsif current.respond_to?(:parent_node)
              current = current.parent_node
            else
              break
            end

            next unless current

            if current.respond_to?(:name) && preserve_elements.include?(current.name.to_s.downcase)
              return true
            end
          end

          false
        end
      end
    end
  end
end
