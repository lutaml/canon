# frozen_string_literal: true

require_relative "../node"

module Canon
  module Xml
    module Nodes
      # Element node in the XPath data model
      class ElementNode < Node
        attr_reader :name, :namespace_uri, :prefix, :namespace_nodes,
                    :attribute_nodes

        def initialize(name:, namespace_uri: nil, prefix: nil)
          super()
          @name = name
          @namespace_uri = namespace_uri
          @prefix = prefix
          @namespace_nodes = []
          @attribute_nodes = []
        end

        def node_type
          :element
        end

        def qname
          prefix.nil? || prefix.empty? ? name : "#{prefix}:#{name}"
        end

        def add_namespace(namespace_node)
          namespace_node.parent = self
          @namespace_nodes << namespace_node
        end

        def add_attribute(attribute_node)
          attribute_node.parent = self
          @attribute_nodes << attribute_node
        end

        # Get namespace nodes in sorted order (lexicographically by local name)
        def sorted_namespace_nodes
          @namespace_nodes.sort_by do |ns|
            ns.local_name.to_s
          end
        end

        # Get attribute nodes in sorted order (by namespace URI then local name)
        def sorted_attribute_nodes
          @attribute_nodes.sort_by do |attr|
            [attr.namespace_uri.to_s, attr.local_name]
          end
        end
      end
    end
  end
end
