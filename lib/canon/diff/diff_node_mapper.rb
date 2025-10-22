# frozen_string_literal: true

require_relative "diff_line"

module Canon
  module Diff
    # Maps semantic DiffNodes to textual DiffLines
    # This is Layer 2 of the diff pipeline, bridging semantic differences
    # (from comparators) to textual representation (for formatters)
    class DiffNodeMapper
      # Map diff nodes to diff lines
      #
      # @param diff_nodes [Array<DiffNode>] The semantic differences
      # @param text1 [String] The first text being compared
      # @param text2 [String] The second text being compared
      # @param options [Hash] Mapping options
      # @option options [Hash] :line_map1 Pre-built line range map for text1
      # @option options [Hash] :line_map2 Pre-built line range map for text2
      # @return [Array<DiffLine>] Diff lines with semantic linkage
      def self.map(diff_nodes, text1, text2, options = {})
        new(diff_nodes, text1, text2, options).map
      end

      def initialize(diff_nodes, text1, text2, options = {})
        @diff_nodes = diff_nodes
        @text1 = text1
        @text2 = text2
        @line_map1 = options[:line_map1]
        @line_map2 = options[:line_map2]
      end

      def map
        lines1 = @text1.split("\n")
        lines2 = @text2.split("\n")

        # Use LCS to get structural diff
        require "diff/lcs"
        lcs_diffs = ::Diff::LCS.sdiff(lines1, lines2)

        # Check if ALL DiffNodes are inactive
        all_inactive = @diff_nodes && !@diff_nodes.empty? &&
                       @diff_nodes.all?(&:inactive?)

        # Convert LCS diffs to DiffLines
        # If all DiffNodes are inactive, we create a single shared inactive DiffNode
        # for all changed lines (this avoids complex linking)
        shared_inactive_node = if all_inactive
                                 @diff_nodes.first # Use any inactive node
                               end

        diff_lines = []
        line_num = 0

        lcs_diffs.each do |change|
          diff_line = case change.action
                      when "="
                        DiffLine.new(
                          line_number: line_num,
                          content: change.old_element,
                          type: :unchanged,
                          diff_node: nil,
                        )
                      when "-"
                        DiffLine.new(
                          line_number: line_num,
                          content: change.old_element,
                          type: :removed,
                          diff_node: shared_inactive_node || find_diff_node_for_line(line_num, lines1, :removed),
                        )
                      when "+"
                        DiffLine.new(
                          line_number: line_num,
                          content: change.new_element,
                          type: :added,
                          diff_node: shared_inactive_node || find_diff_node_for_line(line_num, lines2, :added),
                        )
                      when "!"
                        DiffLine.new(
                          line_number: line_num,
                          content: change.new_element,
                          type: :changed,
                          diff_node: shared_inactive_node || find_diff_node_for_line(line_num, lines2, :changed),
                        )
                      end

          diff_lines << diff_line
          line_num += 1
        end

        diff_lines
      end

      private

      # Find the DiffNode associated with a line
      # Uses element name matching for precise line-level linking
      def find_diff_node_for_line(line_num, lines, change_type)
        return nil if @diff_nodes.nil? || @diff_nodes.empty?

        line_content = lines[line_num]
        return nil if line_content.nil?

        # Extract element name from the line
        line_element_name = extract_element_name(line_content)
        return nil unless line_element_name

        # Find DiffNode whose element name matches this line's element
        @diff_nodes.find do |diff_node|
          # For changed lines, we need to check BOTH nodes since the line
          # could represent either the old or new content
          nodes_to_check = case change_type
                          when :removed
                            [diff_node.node1]
                          when :added
                            [diff_node.node2]
                          when :changed
                            # Check both old and new - the line could be either
                            [diff_node.node1, diff_node.node2]
                          end

          nodes_to_check.any? do |node|
            next unless node.respond_to?(:name)
            node.name == line_element_name
          end
        end
      end

      # Extract element name from an XML line
      # Examples:
      #   "<bibitem ...>" => "bibitem"
      #   "</bibitem>" => "bibitem"
      #   "<ns:element ...>" => "ns:element"
      def extract_element_name(line)
        # Match opening or closing tag: <element ...> or </element>
        # Supports namespaces (e.g., ns:element)
        match = line.match(/<\/?([a-zA-Z0-9_:-]+)/)
        match[1] if match
      end
    end
  end
end
