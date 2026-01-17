# frozen_string_literal: true

require_relative "../../xml/namespace_helper"

module Canon
  class DiffFormatter
    module DiffDetailFormatterHelpers
      # Location extraction from diffs
      #
      # Extracts and formats location information (XPath, file position).
      module LocationExtractor
        # Extract location information from a diff
        #
        # @param diff [DiffNode, Hash] Difference node
        # @return [String] Location string
        def self.extract_location(diff)
          return "" unless diff

          # Get the appropriate node based on diff type
          node = if diff.respond_to?(:node1)
                   diff.node1 || diff.node2
                 elsif diff.is_a?(Hash)
                   diff[:node1] || diff[:node2]
                 end

          return "" unless node

          xpath = extract_xpath(node)
          xpath.empty? ? "" : "Location: #{xpath}"
        end

        # Extract XPath from a node
        #
        # @param node [Object] Node to extract XPath from
        # @return [String] XPath string
        def self.extract_xpath(node)
          return "" unless node

          # Use PathBuilder if available
          if defined?(Canon::Diff::PathBuilder)
            begin
              path = Canon::Diff::PathBuilder.build_path(node)
              return path unless path.nil? || path.empty?
            rescue StandardError
              # Fall through to manual extraction
            end
          end

          # Manual XPath extraction
          manual_xpath(node)
        end

        # Manual XPath extraction fallback
        #
        # @param node [Object] Node to extract XPath from
        # @return [String] XPath string
        def self.manual_xpath(node)
          return "" unless node

          parts = []
          current = node

          while current
            break unless current.respond_to?(:name)

            name = current.name
            break if name.nil? || name.empty?

            # Calculate position among siblings
            index = calculate_sibling_index(current, name)
            parts.unshift("#{name}[#{index}]")

            # Move to parent
            current = if current.respond_to?(:parent)
                        current.parent
                      elsif current.respond_to?(:parent_node)
                        current.parent_node
                      end

            # Stop at document root
            break if current.respond_to?(:document) && current == current.document
          end

          parts.empty? ? "" : "/#{parts.join('/')}"
        end

        # Calculate sibling index for XPath
        #
        # @param node [Object] Node to calculate index for
        # @param name [String] Node name
        # @return [Integer] 1-based index
        def self.calculate_sibling_index(node, name)
          return 1 unless node.respond_to?(:parent) || node.respond_to?(:parent_node)

          parent = if node.respond_to?(:parent)
                     node.parent
                   elsif node.respond_to?(:parent_node)
                     node.parent_node
                   end

          return 1 unless parent

          # Get siblings with same name
          siblings = if parent.respond_to?(:children)
                       parent.children.select do |n|
                         n.respond_to?(:name) && n.name == name
                       end
                     elsif parent.respond_to?(:child_nodes)
                       parent.child_nodes.select do |n|
                         n.respond_to?(:name) && n.name == name
                       end
                     else
                       [node]
                     end

          siblings.index(node) + 1
        end
      end
    end
  end
end
