# frozen_string_literal: true

require_relative "diff_line"
require_relative "formatting_detector"

module Canon
  module Diff
    # Assembles DiffLines from enriched DiffNodes.
    #
    # This is Phase 2 of the two-phase diff pipeline. It runs after
    # DiffNodeEnricher and before DiffBlockBuilder. It does NO computation
    # on the change content — it simply reads pre-computed DiffCharRanges
    # from DiffNodes and assembles them into DiffLines.
    #
    # The DiffLineBuilder handles:
    # - Mapping DiffCharRanges to the correct DiffLines
    # - Filling in unchanged context lines between changes
    # - Detecting reflow (lines that moved between documents)
    # - Computing line correspondence without LCS
    class DiffLineBuilder
      # Build DiffLines from enriched DiffNodes.
      #
      # @param diff_nodes [Array<DiffNode>] Enriched DiffNodes with char_ranges
      # @param text1 [String] The first document (preprocessed)
      # @param text2 [String] The second document (preprocessed)
      # @return [Array<DiffLine>] The assembled diff lines
      def self.build(diff_nodes, text1, text2)
        return [] if diff_nodes.nil? || diff_nodes.empty?
        return [] if text1.nil? || text2.nil?

        new(diff_nodes, text1, text2).build
      end

      def initialize(diff_nodes, text1, text2)
        @diff_nodes = diff_nodes
        @text1 = text1
        @text2 = text2
        @lines1 = text1.split("\n")
        @lines2 = text2.split("\n")
      end

      # Maximum number of reflow lines before switching to summary mode.
      # When more lines than this are unmatched in a reflow gap, a summary
      # line is emitted instead of listing each individual line.
      REFLOW_SUMMARY_THRESHOLD = 2

      def build
        # Sort DiffNodes by their position in text1 (or text2 if no text1 range)
        sorted = @diff_nodes.select { |dn| dn.char_ranges && !dn.char_ranges.empty? }
          .sort_by { |dn| sort_key(dn) }

        result = []
        cursor1 = 0  # current position in text1 lines
        cursor2 = 0  # current position in text2 lines

        sorted.each do |diff_node|
          range1 = diff_node.line_range_before
          range2 = diff_node.line_range_after

          # Determine the start positions for this change
          node_start1 = range1 ? range1[0] : cursor1
          node_start2 = range2 ? range2[0] : cursor2

          # Skip if this node's range has already been passed by the cursor.
          # Handle cases where range1 or range2 is nil (nil means position is only
          # in the other text, so we only check the non-nil side).
          cursor1_passed = range1.nil? ? false : (cursor1 > node_start1)
          cursor2_passed = range2.nil? ? false : (cursor2 > node_start2)
          if cursor1_passed || cursor2_passed
            next
          end

          # Emit unchanged lines before this change
          emit_unchanged(result, cursor1, node_start1, cursor2, node_start2)

          # Detect and handle reflow before this change
          handle_reflow(result, cursor1, node_start1, cursor2, node_start2, diff_node)

          # Emit changed lines for this DiffNode
          emit_changed(result, diff_node)

          # Advance cursors past this change
          cursor1 = range1 ? range1[1] + 1 : node_start1 + 1
          cursor2 = range2 ? range2[1] + 1 : node_start2 + 1
        end

        # Emit remaining unchanged lines after last change
        emit_unchanged(result, cursor1, @lines1.length, cursor2, @lines2.length)

        result
      end

      private

      # Sort key for ordering DiffNodes by position in the document.
      def sort_key(diff_node)
        range = diff_node.line_range_before || diff_node.line_range_after
        range ? range[0] : Float::INFINITY
      end

      # Emit unchanged DiffLines between two cursor positions.
      #
      # @param result [Array<DiffLine>] output array
      # @param from1 [Integer] start line in text1
      # @param to1 [Integer] end line (exclusive) in text1
      # @param from2 [Integer] start line in text2
      # @param to2 [Integer] end line (exclusive) in text2
      def emit_unchanged(result, from1, to1, from2, to2)
        count1 = to1 - from1
        count2 = to2 - from2

        if count1 == count2 && count1 >= 0
          # Simple case: same number of lines
          count1.times do |i|
            line1_idx = from1 + i
            line2_idx = from2 + i
            next if line1_idx >= @lines1.length && line2_idx >= @lines2.length

            content = if line1_idx < @lines1.length
                        @lines1[line1_idx]
                      else
                        @lines2[line2_idx]
                      end

            result << DiffLine.new(
              line_number: line1_idx,
              new_position: line2_idx,
              content: content,
              type: :unchanged,
            )
          end
        elsif count1.positive? && count2.positive?
          # Different number of lines: use common prefix/suffix matching
          # to identify which lines correspond and which are reflow
          emit_unchanged_with_reflow(result, from1, to1, from2, to2)
        elsif count1.positive?
          # Lines only in text1: reflow gap (absorbed into adjacent lines)
          if count1 >= REFLOW_SUMMARY_THRESHOLD
            emit_reflow_summary(result, from1, to1, from2, to2)
          else
            count1.times do |i|
              line_idx = from1 + i
              next if line_idx >= @lines1.length

              result << DiffLine.new(
                line_number: line_idx,
                content: @lines1[line_idx],
                type: :removed,
                formatting: true,
              )
            end
          end
        elsif count2.positive?
          # Lines only in text2: reflow gap
          if count2 >= REFLOW_SUMMARY_THRESHOLD
            emit_reflow_summary(result, from1, to1, from2, to2)
          else
            count2.times do |i|
              line_idx = from2 + i
              next if line_idx >= @lines2.length

              result << DiffLine.new(
                line_number: line_idx,
                new_position: line_idx,
                content: @lines2[line_idx],
                type: :added,
                formatting: true,
              )
            end
          end
        end
      end

      # Emit unchanged lines when text1 and text2 have different line counts
      # in the unchanged region. Uses prefix/suffix matching at the structural level
      # to find which lines correspond, treating unmatched middle lines as reflow.
      #
      # This method handles unchanged regions between DiffNodes. Within those
      # regions, we use prefix/suffix matching to find structural correspondence.
      # The unmatched lines are marked as formatting-only (reflow).
      # When many lines are unmatched, a summary is emitted instead.
      def emit_unchanged_with_reflow(result, from1, to1, from2, to2)
        slice1 = @lines1[from1...to1]
        slice2 = @lines2[from2...to2]
        return if slice1.empty? && slice2.empty?

        # Fast path: if slices are identical, emit all as unchanged
        if slice1 == slice2
          emit_unchanged_range(result, from1, from2, slice1.length)
          return
        end

        # Find common prefix (lines that match between the two slices)
        prefix_len = 0
        max_prefix = [slice1.length, slice2.length].min
        while prefix_len < max_prefix &&
            strip_for_compare(slice1[prefix_len]) == strip_for_compare(slice2[prefix_len])
          prefix_len += 1
        end

        # Find common suffix
        suffix_len = 0
        max_suffix = [slice1.length - prefix_len, slice2.length - prefix_len].min
        while suffix_len < max_suffix &&
            strip_for_compare(slice1[slice1.length - 1 - suffix_len]) ==
                strip_for_compare(slice2[slice2.length - 1 - suffix_len])
          suffix_len += 1
        end

        # Emit common prefix as unchanged
        prefix_len.times do |i|
          result << DiffLine.new(
            line_number: from1 + i,
            new_position: from2 + i,
            content: slice1[i],
            type: :unchanged,
          )
        end

        # Emit middle (reflow) lines
        mid_start1 = from1 + prefix_len
        mid_end1 = to1 - suffix_len
        mid_start2 = from2 + prefix_len
        mid_end2 = to2 - suffix_len
        mid_count1 = mid_end1 - mid_start1
        mid_count2 = mid_end2 - mid_start2

        if mid_count1 + mid_count2 >= REFLOW_SUMMARY_THRESHOLD
          # Too many reflow lines — emit summary instead of listing each
          emit_reflow_summary(result, mid_start1, mid_end1, mid_start2, mid_end2)
        else
          # Few enough to show individually
          # Lines only in text1 (removed by reflow)
          (mid_start1...mid_end1).each do |line_idx|
            next if line_idx >= @lines1.length

            result << DiffLine.new(
              line_number: line_idx,
              content: @lines1[line_idx],
              type: :removed,
              formatting: true,
            )
          end

          # Lines only in text2 (added by reflow)
          (mid_start2...mid_end2).each do |line_idx|
            next if line_idx >= @lines2.length

            result << DiffLine.new(
              line_number: line_idx,
              new_position: line_idx,
              content: @lines2[line_idx],
              type: :added,
              formatting: true,
            )
          end
        end

        # Emit common suffix as unchanged
        suffix_len.times do |i|
          idx1 = to1 - suffix_len + i
          idx2 = to2 - suffix_len + i
          next if idx1 >= @lines1.length && idx2 >= @lines2.length

          content = if idx1 < @lines1.length
                      @lines1[idx1]
                    else
                      @lines2[idx2]
                    end

          result << DiffLine.new(
            line_number: idx1,
            new_position: idx2,
            content: content,
            type: :unchanged,
          )
        end
      end

      # Helper to emit a range of unchanged lines
      def emit_unchanged_range(result, from1, from2, count)
        count.times do |i|
          line1_idx = from1 + i
          line2_idx = from2 + i
          next if line1_idx >= @lines1.length && line2_idx >= @lines2.length

          content = if line1_idx < @lines1.length
                      @lines1[line1_idx]
                    else
                      @lines2[line2_idx]
                    end

          result << DiffLine.new(
            line_number: line1_idx,
            new_position: line2_idx,
            content: content,
            type: :unchanged,
          )
        end
      end

      # Emit a summary line for large reflow gaps instead of listing each line.
      # This prevents output explosion when documents have different formatting
      # that causes many lines to be unmatched in prefix/suffix matching.
      def emit_reflow_summary(result, mid_start1, mid_end1, mid_start2, mid_end2)
        mid_count1 = mid_end1 - mid_start1
        mid_count2 = mid_end2 - mid_start2

        # Show first removed/added line pair for context (if present)
        if mid_count1.positive? && mid_start1 < @lines1.length
          result << DiffLine.new(
            line_number: mid_start1,
            content: @lines1[mid_start1],
            type: :removed,
            formatting: true,
          )
        end

        if mid_count2.positive? && mid_start2 < @lines2.length
          result << DiffLine.new(
            line_number: mid_start2,
            new_position: mid_start2,
            content: @lines2[mid_start2],
            type: :added,
            formatting: true,
          )
        end

        # Summary line when there are more than the first-shown pair
        extra1 = [mid_count1 - 1, 0].max
        extra2 = [mid_count2 - 1, 0].max

        if extra1.positive? || extra2.positive?
          parts = []
          parts << "#{extra1} more removed" if extra1.positive?
          parts << "#{extra2} more added" if extra2.positive?

          result << DiffLine.new(
            line_number: mid_start1,
            new_position: mid_start2,
            content: "... #{parts.join(', ')} (formatting only) ...",
            type: :reflow_summary,
            formatting: true,
          )
        end
      end

      # Detect reflow: lines that exist in text1 but whose content is absorbed
      # into an adjacent changed line in text2 (or vice versa).
      def handle_reflow(result, cursor1, node_start1, _cursor2, _node_start2, diff_node)
        # Check if there are "extra" lines in text1 before the change
        # that are absorbed into the changed line in text2
        extra_lines1 = node_start1 - cursor1
        return if extra_lines1 <= 0

        # Check if the content of those extra lines appears in the
        # adjacent line in text2
        extra_content = @lines1[cursor1...node_start1].map(&:strip).join

        # Find the nearest changed line in text2
        next_new_line = find_changed_line_in_text2(diff_node)
        return unless next_new_line

        if next_new_line.include?(extra_content.strip)
          # The extra lines are reflow — mark as formatting-only
          # Remove any removed lines we already added for this range
          # (they were added by emit_unchanged)
          extra_lines1.times do |i|
            line_idx = cursor1 + i
            # Find and mark existing lines as formatting
            existing = result.find do |dl|
              dl.line_number == line_idx && dl.removed? && !dl.formatting?
            end
            existing&.formatting = true
          end
        end
      end

      # Find the content of the changed line in text2 for a DiffNode.
      def find_changed_line_in_text2(diff_node)
        new_ranges = diff_node.char_ranges&.select(&:new_side?)
        return nil unless new_ranges&.any?

        first_range = new_ranges.min_by(&:line_number)
        return nil unless first_range

        @lines2[first_range.line_number]
      end

      # Emit DiffLines for a single DiffNode's char_ranges.
      def emit_changed(result, diff_node)
        return unless diff_node.char_ranges && !diff_node.char_ranges.empty?

        ranges = diff_node.char_ranges

        # Group ranges by (line_number, side) to build DiffLines
        old_line_ranges = {}
        new_line_ranges = {}

        ranges.each do |cr|
          if cr.old_side?
            (old_line_ranges[cr.line_number] ||= []) << cr
          else
            (new_line_ranges[cr.line_number] ||= []) << cr
          end
        end

        # Determine what kind of change this is
        has_old = !old_line_ranges.empty?
        has_new = !new_line_ranges.empty?

        if has_old && has_new
          # Changed: exists in both texts
          emit_changed_lines(result, diff_node, old_line_ranges, new_line_ranges)
        elsif has_old
          # Removed: only in text1
          emit_removed_lines(result, diff_node, old_line_ranges)
        elsif has_new
          # Added: only in text2
          emit_added_lines(result, diff_node, new_line_ranges)
        end
      end

      # Emit DiffLines for a change that exists in both texts.
      def emit_changed_lines(result, diff_node, old_line_ranges, new_line_ranges)
        old_lines = old_line_ranges.keys.sort
        new_lines = new_line_ranges.keys.sort

        # For single-line changes, emit as a single :changed DiffLine
        if old_lines.length == 1 && new_lines.length == 1
          line1_idx = old_lines[0]
          line2_idx = new_lines[0]
          line1_content = @lines1[line1_idx]
          line2_content = @lines2[line2_idx]

          # For formatting detection, use the actual changed content from the DiffNode,
          # not the full line content. The full line includes surrounding XML tags
          # which would cause FormattingDetector to not detect whitespace-only changes.
          text1 = diff_node&.serialized_before || line1_content
          text2 = diff_node&.serialized_after || line2_content

          dl = DiffLine.new(
            line_number: line1_idx,
            new_position: line2_idx,
            content: line1_content,
            new_content: line2_content,
            type: :changed,
            diff_node: diff_node,
            formatting: formatting?(diff_node, text1, text2),
            char_ranges: sort_ranges(old_line_ranges[line1_idx]),
            new_char_ranges: sort_ranges(new_line_ranges[line2_idx]),
          )
          result << dl

          # If line_range indicates content spans more lines than char_ranges cover,
          # emit additional :added lines for the continuation lines.
          # This handles multi-line text nodes where TextDecomposer only creates
          # char_ranges on the starting line.
          range1 = diff_node.line_range_before
          range2 = diff_node.line_range_after
          if range2 && new_lines[0] < range2[1]
            # New version has continuation lines
            ((new_lines[0] + 1)..range2[1]).each do |cont_line_idx|
              next if cont_line_idx >= @lines2.length

              cont_content = @lines2[cont_line_idx]
              result << DiffLine.new(
                line_number: cont_line_idx,
                new_position: cont_line_idx,
                content: cont_content,
                type: :added,
                formatting: true, # Continuation lines are formatting-only
              )
            end
          end
          if range1 && old_lines[0] < range1[1]
            # Old version has continuation lines
            ((old_lines[0] + 1)..range1[1]).each do |cont_line_idx|
              next if cont_line_idx >= @lines1.length

              cont_content = @lines1[cont_line_idx]
              result << DiffLine.new(
                line_number: cont_line_idx,
                content: cont_content,
                type: :removed,
                formatting: true, # Continuation lines are formatting-only
              )
            end
          end
        else
          # Multi-line change: emit old lines as :removed, new lines as :added
          # But keep them associated with the same DiffNode

          # Emit old lines
          old_lines.each do |line_idx|
            line_content = @lines1[line_idx]
            result << DiffLine.new(
              line_number: line_idx,
              content: line_content,
              type: :removed,
              diff_node: diff_node,
              formatting: formatting?(diff_node, line_content, ""),
              char_ranges: sort_ranges(old_line_ranges[line_idx]),
            )
          end

          # Emit new lines
          new_lines.each do |line_idx|
            line_content = @lines2[line_idx]
            result << DiffLine.new(
              line_number: line_idx, # Required; same as new_position for added lines
              new_position: line_idx,
              content: line_content,
              type: :added,
              diff_node: diff_node,
              formatting: formatting?(diff_node, "", line_content),
              new_char_ranges: sort_ranges(new_line_ranges[line_idx]),
            )
          end
        end
      end

      # Emit DiffLines for a removal (only in text1).
      def emit_removed_lines(result, diff_node, old_line_ranges)
        old_line_ranges.keys.sort.each do |line_idx|
          line_content = @lines1[line_idx]
          result << DiffLine.new(
            line_number: line_idx,
            content: line_content,
            type: :removed,
            diff_node: diff_node,
            formatting: formatting?(diff_node, line_content, ""),
            char_ranges: sort_ranges(old_line_ranges[line_idx]),
          )
        end
      end

      # Emit DiffLines for an addition (only in text2).
      def emit_added_lines(result, diff_node, new_line_ranges)
        new_line_ranges.keys.sort.each do |line_idx|
          line_content = @lines2[line_idx]
          result << DiffLine.new(
            line_number: line_idx, # Required; same as new_position for added lines
            new_position: line_idx,
            content: line_content,
            type: :added,
            diff_node: diff_node,
            formatting: formatting?(diff_node, "", line_content),
            new_char_ranges: sort_ranges(new_line_ranges[line_idx]),
          )
        end
      end

      # Sort char ranges by start_col for consistent rendering.
      def sort_ranges(ranges)
        (ranges || []).sort_by(&:start_col)
      end

      # Strip a line for comparison purposes (handles whitespace-only differences).
      def strip_for_compare(line)
        line.strip
      end

      # Compute formatting flag for a DiffLine.
      #
      # The DiffNode's explicit formatting? flag takes precedence:
      # - If formatting? == true: return true (explicitly formatting-only)
      #
      # If node exists and is normative (formatting? is nil but norm is true):
      # - Check line-level formatting via FormattingDetector for whitespace-only changes
      # - But NOT via comment_only_line? heuristic because comment content is different
      #
      # If node exists and is informative (norm=false):
      # - Return false (informative diffs are always shown as informative)
      #
      # If NO node exists (diff_node is nil):
      # - Use heuristics: comment-only lines and FormattingDetector
      #
      # @param diff_node [DiffNode, nil] The associated DiffNode
      # @param line1 [String, nil] Old line content
      # @param line2 [String, nil] New line content
      # @return [Boolean] true if formatting-only
      def formatting?(diff_node, line1, line2)
        # If node explicitly has formatting? == true, it's formatting-only
        return true if diff_node&.formatting?

        if diff_node
          # Node exists - use node classification
          return false unless diff_node.normative?

          # For normative nodes, check line-level formatting
          # (but NOT comment_only_line? which would misclassify comment content changes)
        elsif comment_only_line?(line1) || comment_only_line?(line2)
          # No DiffNode: use heuristics
          return true

        end
        FormattingDetector.formatting_only?(line1, line2)
      end

      # Check if a line is entirely an XML comment (possibly with whitespace).
      # Used as heuristic: comment-only lines with no DiffNode are likely
      # filtered/ignored comments, not normative differences.
      #
      # @param line [String, nil] Line content
      # @return [Boolean] true if comment-only
      def comment_only_line?(line)
        return false if line.nil?

        stripped = line.strip
        stripped.start_with?("<!--") && stripped.end_with?("-->")
      end
    end
  end
end
