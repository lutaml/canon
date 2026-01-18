# frozen_string_literal: true

require_relative "base_dimension"

module Canon
  module Comparison
    module Dimensions
      # Element position dimension
      #
      # Handles comparison of element positions within their parent.
      # Supports :strict and :ignore behaviors.
      #
      # Behaviors:
      # - :strict - Elements must appear in the same position (index)
      # - :ignore - Element position doesn't matter
      class ElementPositionDimension < BaseDimension
        # Extract element position from a node
        #
        # Returns the index of this node among its siblings of the same type.
        #
        # @param node [Moxml::Node, Nokogiri::XML::Node] Node to extract from
        # @return [Integer] Position index (0-based)
        def extract_data(node)
          return 0 unless node

          # Handle Moxml nodes
          if node.is_a?(Moxml::Node)
            extract_from_moxml(node)
          # Handle Nokogiri nodes
          elsif node.is_a?(Nokogiri::XML::Node)
            extract_from_nokogiri(node)
          else
            0
          end
        end

        # Strict element position comparison
        #
        # @param pos1 [Integer] First position
        # @param pos2 [Integer] Second position
        # @return [Boolean] true if positions are equal
        def compare_strict(pos1, pos2)
          pos1 == pos2
        end

        private

        # Extract position from Moxml node
        #
        # @param node [Moxml::Node] Moxml node
        # @return [Integer] Position index
        def extract_from_moxml(node)
          return 0 unless node.parent

          # Find position among siblings of the same element name
          siblings = node.parent.children
          node.name

          siblings.each_with_index do |sibling, index|
            if sibling == node
              return index
            end
          end

          0
        end

        # Extract position from Nokogiri node
        #
        # @param node [Nokogiri::XML::Node] Nokogiri node
        # @return [Integer] Position index
        def extract_from_nokogiri(node)
          return 0 unless node.parent

          # Find position among siblings
          siblings = node.parent.children
          node.name

          siblings.each_with_index do |sibling, index|
            if sibling == node
              return index
            end
          end

          0
        end
      end
    end
  end
end
