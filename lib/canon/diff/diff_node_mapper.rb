# frozen_string_literal: true

require_relative "diff_line"
require "set"

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

        # Pre-compute comment line ranges for multi-line comment handling
        @comment_lines1 = build_comment_lines(@text1)
        @comment_lines2 = build_comment_lines(@text2)
        @comment_diff_nodes = if @diff_nodes
                                @diff_nodes.select { |n| n.dimension == :comments }
                              else
                                []
                              end
      end

      def map
        lines1 = @text1.split("\n")
        lines2 = @text2.split("\n")

        # Use LCS to get structural diff
        require "diff/lcs"
        lcs_diffs = ::Diff::LCS.sdiff(lines1, lines2)

        # Check if ALL DiffNodes are informative
        all_informative = @diff_nodes && !@diff_nodes.empty? &&
          @diff_nodes.all?(&:informative?)

        # Convert LCS diffs to DiffLines
        # If all DiffNodes are informative, we create a single shared informative DiffNode
        # for all changed lines (this avoids complex linking)
        shared_informative_node = if all_informative
                                    @diff_nodes.first # Use any informative node
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
                        # Find the diff node for this line
                        # Check comment range first (handles multi-line comments),
                        # then fall back to element name matching
                        node = shared_informative_node ||
                          find_diff_node_for_line(
                            line_num, lines1, :removed,
                            comment_lines: @comment_lines1
                          )

                        # Check if this is formatting-only:
                        # 1. First check if the DiffNode itself is marked as formatting-only
                        # 2. Otherwise, check line-level formatting
                        formatting = if node.respond_to?(:formatting?) && node.formatting?
                                       true
                                     else
                                       formatting_only_line?(
                                         change.old_element, ""
                                       )
                                     end

                        DiffLine.new(
                          line_number: line_num,
                          content: change.old_element,
                          type: :removed,
                          diff_node: node,
                          formatting: formatting,
                        )
                      when "+"
                        # Find the diff node for this line
                        node = shared_informative_node ||
                          find_diff_node_for_line(
                            line_num, lines2, :added,
                            comment_lines: @comment_lines2
                          )

                        # Check if this is formatting-only:
                        # 1. First check if the DiffNode itself is marked as formatting-only
                        # 2. Otherwise, check line-level formatting
                        formatting = if node.respond_to?(:formatting?) && node.formatting?
                                       true
                                     else
                                       formatting_only_line?("",
                                                             change.new_element)
                                     end

                        DiffLine.new(
                          line_number: line_num,
                          content: change.new_element,
                          type: :added,
                          diff_node: node,
                          formatting: formatting,
                        )
                      when "!"
                        # Find the diff node for this line
                        # For changed lines, check comment ranges in both texts
                        node = shared_informative_node ||
                          find_diff_node_for_line(
                            line_num, lines2, :changed,
                            comment_lines: @comment_lines2,
                            comment_lines_alt: @comment_lines1
                          )

                        # Check if this is formatting-only:
                        # 1. First check if the DiffNode itself is marked as formatting-only
                        # 2. Otherwise, check line-level formatting
                        formatting = if node.respond_to?(:formatting?) && node.formatting?
                                       true
                                     else
                                       formatting_only_line?(
                                         change.old_element, change.new_element
                                       )
                                     end

                        DiffLine.new(
                          line_number: line_num,
                          content: change.new_element,
                          type: :changed,
                          diff_node: node,
                          formatting: formatting,
                        )
                      end

          diff_lines << diff_line
          line_num += 1
        end

        diff_lines
      end

      private

      # Check if two lines differ only in formatting (whitespace)
      # @param line1 [String] First line
      # @param line2 [String] Second line
      # @return [Boolean] true if formatting-only difference
      def formatting_only_line?(line1, line2)
        require_relative "formatting_detector"
        FormattingDetector.formatting_only?(line1, line2)
      end

      # Find the DiffNode associated with a line
      # Uses comment range matching for multi-line comments,
      # then element name matching for other elements
      def find_diff_node_for_line(line_num, lines, change_type,
                                   comment_lines: nil, comment_lines_alt: nil)
        return nil if @diff_nodes.nil? || @diff_nodes.empty?

        line_content = lines[line_num]
        return nil if line_content.nil?

        # Check comment range first (handles multi-line comments where
        # only the first line has <!--, but all lines are part of the comment)
        if comment_lines&.include?(line_num)
          node = find_comment_diff_node_for_line(line_num, lines)
          return node if node
        end

        # For changed lines, also check the alternate text's comment ranges
        if comment_lines_alt&.include?(line_num)
          node = find_comment_diff_node_for_line(line_num, lines)
          return node if node
        end

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
            # Check if the node itself has the matching name
            if node.respond_to?(:name) && node.name == line_element_name
              true
            # Check if the node's parent has the matching name (for TextNode diffs)
            elsif node.respond_to?(:parent) && node.parent.respond_to?(:name) && node.parent.name == line_element_name # rubocop:disable Style/IfWithBooleanLiteralBranches
              true
            else
              false
            end
          end
        end
      end

      # Extract element name from an XML line
      # Examples:
      #   "<bibitem ...>" => "bibitem"
      #   "</bibitem>" => "bibitem"
      #   "<ns:element ...>" => "ns:element"
      #   "<!-- comment -->" => "comment"
      def extract_element_name(line)
        # Check for XML comments first
        return "comment" if line.include?("<!--")

        # Match opening or closing tag: <element ...> or </element>
        # Supports namespaces (e.g., ns:element)
        match = line.match(/<\/?([a-zA-Z0-9_:-]+)/)
        match[1] if match
      end

      # Build a Set of line numbers that fall within XML comment blocks.
      # A single comment can span multiple lines when formatted; this method
      # maps the comment's character range to the line numbers it covers,
      # so that all lines of a multi-line comment can be linked to the
      # same DiffNode.
      #
      # @param text [String] The formatted text to scan
      # @return [Set<Integer>] Set of 0-based line numbers inside comments
      def build_comment_lines(text)
        lines = text.split("\n")
        comment_lines = Set.new
        in_comment = false

        lines.each_with_index do |line, idx|
          if in_comment
            comment_lines.add(idx)
            if line.include?("-->")
              in_comment = false
            end
          elsif line.include?("<!--")
            comment_lines.add(idx)
            # Check if comment opens AND closes on the same line
            # (single-line comment like <!-- text -->)
            in_comment = true unless line.include?("-->")
          end
        end

        comment_lines
      end

      # Find a comment DiffNode for a line that falls within a comment range.
      # Matches by checking if the DiffNode's source node has name "comment".
      #
      # @param line_num [Integer] Line number (0-based)
      # @param lines [Array<String>] Lines of the text
      # @return [DiffNode, nil] The matching comment DiffNode, or nil
      def find_comment_diff_node_for_line(_line_num, _lines)
        @comment_diff_nodes&.find do |diff_node|
          nodes_to_check = [diff_node.node1, diff_node.node2].compact
          nodes_to_check.any? do |node|
            node.respond_to?(:name) && node.name == "comment"
          end
        end
      end
    end
  end
end
