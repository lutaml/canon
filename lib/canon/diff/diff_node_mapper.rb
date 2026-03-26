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
                                @diff_nodes.select do |n|
                                  n.dimension == :comments
                                end
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

        lcs_diffs.each do |change|
          diff_line = case change.action
                      when "="
                        DiffLine.new(
                          line_number: change.old_position,
                          new_position: change.new_position,
                          content: change.old_element,
                          type: :unchanged,
                          diff_node: nil,
                        )
                      when "-"
                        node = shared_informative_node ||
                          find_diff_node_for_line(
                            change.old_position, lines1, :removed,
                            comment_lines: @comment_lines1
                          )

                        formatting = formatting?(node, change.old_element, "")

                        DiffLine.new(
                          line_number: change.old_position,
                          content: change.old_element,
                          type: :removed,
                          diff_node: node,
                          formatting: formatting,
                        )
                      when "+"
                        node = shared_informative_node ||
                          find_diff_node_for_line(
                            change.new_position, lines2, :added,
                            comment_lines: @comment_lines2
                          )

                        formatting = formatting?(node, "", change.new_element)

                        DiffLine.new(
                          line_number: change.new_position,
                          content: change.new_element,
                          type: :added,
                          diff_node: node,
                          formatting: formatting,
                        )
                      when "!"
                        node = shared_informative_node ||
                          find_diff_node_for_line(
                            change.new_position, lines2, :changed,
                            comment_lines: @comment_lines2,
                            old_content: change.old_element
                          )

                        formatting = formatting?(node,
                                                 change.old_element,
                                                 change.new_element)

                        DiffLine.new(
                          line_number: change.old_position,
                          content: change.new_element,
                          type: :changed,
                          diff_node: node,
                          formatting: formatting,
                          new_position: change.new_position,
                        )
                      end

          diff_lines << diff_line
        end

        # Post-process: detect multi-line formatting changes that
        # per-line comparison misses (e.g., tag wrapping from 2 lines to 1,
        # element reflow with different line counts).
        apply_block_formatting!(diff_lines, lcs_diffs)

        # Post-process: merge adjacent "-" lines into preceding "!" changes
        # when the removed content already appears in the new line.
        # This handles the case where N old lines map to 1 new line
        # (e.g., closing tag on its own line merged into previous line).
        merge_adjacent_removals!(diff_lines, lines1)

        diff_lines
      end

      private

      # Post-process consecutive change blocks to detect multi-line
      # formatting changes that per-line comparison misses.
      #
      # When a tag wraps across different numbers of lines (e.g., 2 old lines
      # → 1 new line), individual line pairs can't be compared. By joining
      # all old parts and all new parts within a consecutive change block,
      # we can detect formatting-only changes at the block level.
      #
      # For blocks containing multiple elements (e.g., list-item a reflow
      # followed by list-item b), we greedily find formatting prefix sub-blocks.
      #
      # @param diff_lines [Array<DiffLine>] The diff lines to update
      # @param lcs_diffs [Array<Diff::LCS::Change>] The LCS changes
      def apply_block_formatting!(diff_lines, lcs_diffs)
        require_relative "formatting_detector"

        blocks = group_change_blocks(lcs_diffs)

        blocks.each do |block|
          next if block[:old_parts].empty? || block[:new_parts].empty?

          # Try simple join-and-compare (handles single-element blocks)
          if FormattingDetector.formatting_block?(block[:old_parts],
                                                  block[:new_parts])
            mark_block_lines_formatting!(diff_lines, block,
                                         block[:old_parts].length,
                                         block[:new_parts].length)
            next
          end

          # Try finding a formatting prefix sub-block
          match = FormattingDetector.formatting_prefix(block[:old_parts],
                                                       block[:new_parts])
          if match
            mark_block_lines_formatting!(diff_lines, block,
                                         match[:old_end], match[:new_end])
          end
        end
      end

      # Group consecutive non-unchanged LCS changes into blocks.
      #
      # @param lcs_diffs [Array<Diff::LCS::Change>] The LCS changes
      # @return [Array<Hash>] Blocks with :indices, :old_parts, :new_parts
      def group_change_blocks(lcs_diffs)
        blocks = []
        current_block = nil

        lcs_diffs.each_with_index do |change, idx|
          if change.action == "="
            blocks << current_block if current_block
            current_block = nil
            next
          end

          current_block ||=
            { indices: [], old_parts: [], new_parts: [] }
          current_block[:indices] << idx

          case change.action
          when "-"
            current_block[:old_parts] << change.old_element
          when "+"
            current_block[:new_parts] << change.new_element
          when "!"
            current_block[:old_parts] << change.old_element
            current_block[:new_parts] << change.new_element
          end
        end

        blocks << current_block if current_block
        blocks
      end

      # Mark lines within a block as formatting-only.
      # Only marks lines that don't already have a non-formatting DiffNode.
      #
      # @param diff_lines [Array<DiffLine>] The diff lines to update
      # @param block [Hash] The change block from group_change_blocks
      # @param old_count [Integer] Number of old parts to mark
      # @param new_count [Integer] Number of new parts to mark
      def mark_block_lines_formatting!(diff_lines, block, old_count,
                                       new_count)
        old_marked = 0
        new_marked = 0

        block[:indices].each do |idx|
          dl = diff_lines[idx]
          next if dl.type == :unchanged
          next if dl.diff_node && !dl.formatting?

          case dl.type
          when :removed
            if old_marked < old_count
              dl.formatting = true
              old_marked += 1
            end
          when :added
            if new_marked < new_count
              dl.formatting = true
              new_marked += 1
            end
          when :changed
            if old_marked < old_count
              dl.formatting = true
              old_marked += 1
            end
            if new_marked < new_count
              dl.formatting = true
              new_marked += 1
            end
          end
        end
      end

      # Check if two lines differ only in formatting (whitespace)
      # @param line1 [String] First line
      # @param line2 [String] Second line
      # @return [Boolean] true if formatting-only difference
      def formatting_only_line?(line1, line2)
        require_relative "formatting_detector"
        FormattingDetector.formatting_only?(line1, line2)
      end

      # Merge adjacent "-" lines into a preceding "!" change when the
      # removed content already appears in the changed line's new content.
      #
      # This handles the common case where N old lines map to 1 new line
      # (e.g., a closing tag on its own line gets merged into the previous
      # line in the reformatted document). Without this merge, the closing
      # tag would appear as a spurious deletion even though it still exists.
      #
      # @param diff_lines [Array<DiffLine>] The diff lines to update in place
      # @param lines1 [Array<String>] Lines from text1 for content lookup
      def merge_adjacent_removals!(diff_lines, lines1)
        i = 0
        while i < diff_lines.length
          dl = diff_lines[i]
          unless dl.changed?
            i += 1
            next
          end

          j = i + 1
          while j < diff_lines.length && diff_lines[j].removed?
            removed = diff_lines[j]
            removed_stripped = removed.content.strip

            # Only merge if the removed content actually appears in the
            # new line — it's not a real deletion, just a line-wrap change
            if removed_stripped.empty? || !dl.content.include?(removed_stripped)
              j += 1
              next
            end

            # Extend old_content to span multiple old lines
            dl.old_content ||= lines1[dl.line_number]
            dl.old_content += "\n#{lines1[removed.line_number]}"

            # Remove the absorbed line
            diff_lines[j] = nil
            j += 1
          end

          i = j
        end

        diff_lines.compact!
      end

      # Determine formatting status for a changed line.
      # Checks: DiffNode formatting flag → line-level formatting → comment-only heuristic
      #
      # @param node [DiffNode, nil] Associated diff node
      # @param line1 [String] Old line content (for -/!)
      # @param line2 [String] New line content (for +/!)
      # @return [Boolean] true if formatting-only
      def formatting?(node, line1, line2)
        return true if node.respond_to?(:formatting?) && node.formatting?
        return false if node
        return true if comment_only_line?(line1) || comment_only_line?(line2)

        formatting_only_line?(line1, line2)
      end

      # Check if a line is entirely an XML comment (possibly with whitespace).
      # Used as heuristic: comment-only lines with no DiffNode are likely
      # filtered/ignored comments, not normative differences.
      #
      # @param line [String, nil] Line content
      # @return [Boolean] true if line is comment-only
      def comment_only_line?(line)
        return false if line.nil?

        stripped = line.strip
        stripped.start_with?("<!--") && stripped.end_with?("-->")
      end

      # Find the DiffNode associated with a line
      # Uses comment range matching for multi-line comments,
      # then element name matching for other elements
      def find_diff_node_for_line(line_num, lines, change_type,
                                   comment_lines: nil, old_content: nil)
        return nil if @diff_nodes.nil? || @diff_nodes.empty?

        line_content = lines[line_num]
        return nil if line_content.nil?

        # Check comment range first (handles multi-line comments where
        # only the first line has <!--, but all lines are part of the comment)
        if comment_lines&.include?(line_num)
          node = find_comment_diff_node_for_line(line_num, lines)
          return node if node
        end

        # Extract element name from the line
        line_element_name = extract_element_name(line_content)
        return nil unless line_element_name

        # Find DiffNode whose element name matches this line's element
        # Exclude comment DiffNodes for lines that don't contain comment
        # markers — closing tags like </mml:mrow> should not match comment
        # DiffNodes via parent.name, but lines with inline comments like
        # <item>before<!-- mid -->after</item> should still match.
        # For changed lines, also check old_content since the comment
        # may have been in the old text but not the new text.
        line_has_comment = line_content.include?("<!--") ||
          old_content&.include?("<!--")
        candidates = if line_has_comment
                       @diff_nodes
                     else
                       @diff_nodes.reject { |dn| dn.dimension == :comments }
                     end
        return nil if candidates.empty?

        candidates.find do |diff_node|
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
