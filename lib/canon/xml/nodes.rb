# frozen_string_literal: true

module Canon
  module Xml
    # XPath data model node types. All nodes inherit from
    # {Canon::Xml::Node}. Children are autoloaded — never
    # `require_relative` them.
    module Nodes
      autoload :AttributeNode, "canon/xml/nodes/attribute_node"
      autoload :CommentNode, "canon/xml/nodes/comment_node"
      autoload :ElementNode, "canon/xml/nodes/element_node"
      autoload :NamespaceNode, "canon/xml/nodes/namespace_node"
      autoload :ProcessingInstructionNode,
               "canon/xml/nodes/processing_instruction_node"
      autoload :RootNode, "canon/xml/nodes/root_node"
      autoload :TextNode, "canon/xml/nodes/text_node"
    end
  end
end
