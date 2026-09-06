# frozen_string_literal: true

module Canon
  module Xml
    # Base class for all XPath data model nodes
    class Node
      # Shared by every childless node: leaves (text, attributes,
      # namespaces, comments, PIs) and empty elements read `children`
      # without materializing a private array. Mutating the returned
      # array is a bug — writers go through add_child/children=, which
      # install a private array first.
      EMPTY_CHILDREN = [].freeze

      attr_reader :parent

      def initialize
        @parent = nil
        @children = nil
        @in_node_set = true
      end

      def children
        @children || EMPTY_CHILDREN
      end

      def children=(new_children)
        @children = new_children
      end

      def add_child(child)
        child.parent = self
        (@children ||= []) << child
      end

      def in_node_set?
        @in_node_set
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
        @parse_errors || []
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
