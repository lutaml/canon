# frozen_string_literal: true

module Canon
  module Xml
    module Nodes
      class ElementNode < Node
        attr_reader :name, :namespace_uri, :prefix

        def initialize(name:, namespace_uri: nil, prefix: nil)
          super()
          @name = name
          @namespace_uri = namespace_uri
          @prefix = prefix
          @namespace_nodes = nil
          @attribute_nodes = nil
        end

        # Lazy: most elements carry no attributes, and inherited
        # namespace nodes arrive as one shared frozen array (see
        # TreeBuilder#attach_namespace_scope) — eager per-element arrays
        # were the largest retained-allocation source in a built tree.
        def namespace_nodes
          @namespace_nodes ||= []
        end

        def namespace_nodes=(nodes)
          @namespace_nodes = nodes
        end

        def attribute_nodes
          @attribute_nodes ||= []
        end

        def node_type
          :element
        end

        def qname
          prefix.nil? || prefix.empty? ? name : "#{prefix}:#{name}"
        end

        def add_namespace(namespace_node)
          namespace_node.parent = self
          namespace_nodes << namespace_node
        end

        def add_attribute(attribute_node)
          attribute_node.parent = self
          attribute_nodes << attribute_node
        end

        # Get namespace nodes in sorted order (lexicographically by local name)
        def sorted_namespace_nodes
          namespace_nodes.sort_by(&:local_name)
        end

        # Get attribute nodes in sorted order (by namespace URI then local name)
        def sorted_attribute_nodes
          attribute_nodes.sort_by do |attr|
            [attr.namespace_uri.to_s, attr.local_name]
          end
        end

        def node_info
          "name: #{name} namespace_uri: #{namespace_uri} prefix: #{prefix}"
        end

        def to_s
          "<#{qname}>"
        end
      end
    end
  end
end
