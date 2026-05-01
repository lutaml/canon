# frozen_string_literal: true

module Canon
  module Xml
    # Base class for all XPath data model nodes
    class Node
      attr_reader :parent, :children

      def initialize
        @parent = nil
        @children = []
      end

      def add_child(child)
        child.parent = self
        @children << child
      end

      def in_node_set?
        instance_variable_defined?(:@in_node_set) ? @in_node_set : true
      end

      def in_node_set=(value)
        @in_node_set = value
      end

      # Parse-time errors carried alongside the node tree, captured at
      # parse boundaries (Canon::Xml::DataModel.from_xml, etc.) so the
      # diff report can surface libxml-level FATAL conditions that
      # would otherwise be silently swallowed and produce misleading
      # diffs against a partially-loaded tree.  See lutaml/canon#130.
      #
      # @return [Array<String>] Parse errors as strings (empty by default)
      def parse_errors
        instance_variable_defined?(:@parse_errors) ? @parse_errors : []
      end

      def parse_errors=(value)
        @parse_errors = Array(value)
      end

      # Return the text content of this node and all descendants.
      # ElementNode concatenates children's text_content; other nodes
      # (TextNode, CommentNode, etc.) return their value.
      def text_content
        children.map(&:text_content).join
      end

      protected

      attr_writer :parent
    end
  end
end
