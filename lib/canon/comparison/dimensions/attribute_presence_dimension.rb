# frozen_string_literal: true

require_relative "base_dimension"

module Canon
  module Comparison
    module Dimensions
      # Attribute presence dimension
      #
      # Handles comparison of attribute presence (which attributes exist).
      # Supports :strict and :ignore behaviors.
      #
      # Behaviors:
      # - :strict - Attribute names must match exactly
      # - :ignore - Skip attribute presence comparison
      class AttributePresenceDimension < BaseDimension
        # Extract attribute names from a node
        #
        # @param node [Moxml::Node, Nokogiri::XML::Node] Node to extract from
        # @return [Array<Symbol>] Array of attribute names
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

        # Strict attribute presence comparison
        #
        # @param names1 [Array<Symbol>] First attribute names
        # @param names2 [Array<Symbol>] Second attribute names
        # @return [Boolean] true if attribute names are exactly equal
        def compare_strict(names1, names2)
          names1.sort == names2.sort
        end

        private

        # Extract attribute names from Moxml node
        #
        # @param node [Moxml::Node] Moxml node
        # @return [Array<Symbol>] Array of attribute names
        def extract_from_moxml(node)
          return [] unless node.node_type == :element

          node.attributes.map { |attr| attr.name.to_sym }
        end

        # Extract attribute names from Nokogiri node
        #
        # @param node [Nokogiri::XML::Node] Nokogiri node
        # @return [Array<Symbol>] Array of attribute names
        def extract_from_nokogiri(node)
          return [] unless node.node_type == Nokogiri::XML::Node::ELEMENT_NODE

          node.attribute_nodes.map { |attr| attr.name.to_sym }
        end
      end
    end
  end
end
