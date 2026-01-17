# frozen_string_literal: true

require_relative "base_dimension"

module Canon
  module Comparison
    module Dimensions
      # Attribute order dimension
      #
      # Handles comparison of attribute ordering.
      # Supports :strict and :ignore behaviors.
      #
      # Behaviors:
      # - :strict - Attributes must appear in the same order
      # - :ignore - Attribute order doesn't matter
      class AttributeOrderDimension < BaseDimension
        # Extract attribute order from a node
        #
        # @param node [Moxml::Node, Nokogiri::XML::Node] Node to extract from
        # @return [Array<Symbol>] Array of attribute names in order
        def extract_data(node)
          return [] unless node

          # Handle Moxml nodes
          if node.is_a?(Moxml::Node)
            extract_from_moxml(node)
          # Handle Nokogiri nodes
          elsif node.is_a?(Nokogiri::XML::Node)
            extract_from_nokogiri(node)
          else
            []
          end
        end

        # Strict attribute order comparison
        #
        # @param order1 [Array<Symbol>] First attribute order
        # @param order2 [Array<Symbol>] Second attribute order
        # @return [Boolean] true if attribute order is exactly the same
        def compare_strict(order1, order2)
          order1 == order2
        end

        private

        # Extract attribute order from Moxml node
        #
        # @param node [Moxml::Node] Moxml node
        # @return [Array<Symbol>] Array of attribute names in order
        def extract_from_moxml(node)
          return [] unless node.node_type == :element

          node.attributes.map { |attr| attr.name.to_sym }
        end

        # Extract attribute order from Nokogiri node
        #
        # @param node [Nokogiri::XML::Node] Nokogiri node
        # @return [Array<Symbol>] Array of attribute names in order
        def extract_from_nokogiri(node)
          return [] unless node.node_type == Nokogiri::XML::Node::ELEMENT_NODE

          node.attribute_nodes.map { |attr| attr.name.to_sym }
        end
      end
    end
  end
end
