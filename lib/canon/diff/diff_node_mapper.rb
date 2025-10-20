# frozen_string_literal: true

module Canon
  module Diff
    # Maps semantic DiffNodes to text line positions
    # Bridges the gap between semantic differences and textual representation
    class DiffNodeMapper
      attr_reader :text1, :text2, :diff_nodes

      # @param text1 [String] The first text being compared
      # @param text2 [String] The second text being compared
      # @param diff_nodes [Array<DiffNode>] The semantic differences
      def initialize(text1:, text2:, diff_nodes:)
        @text1 = text1
        @text2 = text2
        @diff_nodes = diff_nodes
        @node_to_lines_map = {}
      end

      # Map diff nodes to line ranges in the text
      # @return [Hash] A hash mapping DiffNode to line ranges
      #   e.g., { diff_node => { text1: [5, 6], text2: [5, 7] } }
      def map_nodes_to_lines
        diff_nodes.each do |diff_node|
          @node_to_lines_map[diff_node] = find_line_ranges_for_node(diff_node)
        end
        @node_to_lines_map
      end

      # Get the line range for a specific diff node
      # @param diff_node [DiffNode] The diff node
      # @return [Hash, nil] Line ranges or nil if not found
      def line_range_for(diff_node)
        @node_to_lines_map[diff_node]
      end

      private

      # Find the line ranges in both texts that correspond to a diff node
      # @param diff_node [DiffNode] The diff node
      # @return [Hash] Line ranges for both texts
      def find_line_ranges_for_node(diff_node)
        # This is a placeholder implementation
        # The actual implementation will depend on the node type and format
        # For now, we'll return nil to indicate the mapping needs to be done
        # by the specific comparator (XML, JSON, etc.)
        {
          text1: nil,
          text2: nil,
        }
      end
    end
  end
end
