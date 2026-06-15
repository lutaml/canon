# frozen_string_literal: true

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

          # Prefer pre-computed path if available (populated by MetadataEnricher)
          if diff.is_a?(Canon::Diff::DiffNode) && diff.path && !diff.path.empty?
            return diff.path
          end

          # Fall back to extracting from nodes
          node = if diff.is_a?(Canon::Diff::DiffNode)
                   diff.node1 || diff.node2
                 elsif diff.is_a?(Hash)
                   diff[:node1] || diff[:node2]
                 end

          return "" unless node

          extract_xpath(node)
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
            name = case current
                   when Canon::Xml::Node, Nokogiri::XML::Node
                     current.name
                   else
                     break
                   end
            break if name.nil? || name.empty?

            index = calculate_sibling_index(current, name)
            parts.unshift("#{name}[#{index}]")

            current = case current
                      when Canon::Xml::Node, Nokogiri::XML::Node
                        current.parent
                      else
                        break
                      end

            break if current.is_a?(Nokogiri::XML::Document) ||
              current.is_a?(Canon::Xml::Nodes::RootNode)
          end

          parts.empty? ? "" : "/#{parts.join('/')}"
        end

        # Calculate sibling index for XPath
        #
        # @param node [Object] Node to calculate index for
        # @param name [String] Node name
        # @return [Integer] 1-based index
        def self.calculate_sibling_index(node, name)
          parent = case node
                   when Canon::Xml::Node, Nokogiri::XML::Node
                     node.parent
                   end

          return 1 unless parent

          siblings = case parent
                     when Canon::Xml::Node, Nokogiri::XML::Node
                       parent.children.select do |n|
                         case n
                         when Canon::Xml::Node, Nokogiri::XML::Node
                           n.name == name
                         else
                           false
                         end
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
