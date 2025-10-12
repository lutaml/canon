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
        @in_node_set ||= true
      end

      def in_node_set=(value)
        @in_node_set = value
      end

      protected

      attr_writer :parent
    end
  end
end
