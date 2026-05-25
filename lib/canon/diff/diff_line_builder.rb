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
        # Build reverse indices for efficient content lookup in gap handling.
        # Maps content string to array of line indices where that content appears.
        @line_to_indices1 = build_line_index(@lines1)
        @line_to_indices2 = build_line_index(@lines2)
      end

      # Maximum number of reflow lines before switching to summary mode.
      # When more lines than this are unmatched in a reflow gap, a summary
      # line is emitted instead of listing each individual line.
      REFLOW_SUMMARY_THRESHOLD = 2

      def build
        # Sort DiffNodes by their position in text1 (or text2 if no text1 range)
        sorted = @diff_nodes.select do |dn|
          dn.char_ranges && !dn.char_ranges.empty?
        end
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
          handle_reflow(result, cursor1, node_start1, cursor2, node_start2,
                        diff_node)

          # Emit changed lines for this DiffNode
          emit_changed(result, diff_node)

          # Advance cursors past this change.
          # cursor1 advances based on text1 content consumed.
          # cursor2 advances based on text2 content consumed.
          # For pure insertions (range1 nil), cursor1 advances by count2 to
          # account for text2 gap lines that were emitted as mapping to text1.
          # For pure deletions (range2 nil), cursor2 advances by count1.
          old_cursor1 = cursor1
          old_cursor2 = cursor2
          cursor1 = if range1
                      range1[1] + 1
                    elsif range2
                      old_cursor1 + (node_start2 - old_cursor2)
                    else
                      node_start1 + 1
                    end
          cursor2 = if range2
                      range2[1] + 1
                    elsif range1
                      old_cursor2 + (node_start1 - old_cursor1)
                    else
                      node_start2 + 1
                    end
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
          # Different number of lines: check if content actually exists in other text.
          # If middle content is truly orphaned (doesn't exist in other text),
          # use emit_gap_lines instead to avoid emitting lines without diff_nodes.
          slice1 = @lines1[from1...to1]
          slice2 = @lines2[from2...to2]
          middle_orphaned = slice_middle_orphaned?(slice1, slice2)
          if middle_orphaned
            # Content only exists in one text - use gap handling
            emit_gap_lines(result, from1, to1, from2, to2, count1, count2)
          else
            # Content exists in both texts but at different positions - use reflow
            emit_unchanged_with_reflow(result, from1, to1, from2, to2)
          end
        elsif count1.positive? || count2.positive?
          # Handle gap lines (orphaned or reflow)
          emit_gap_lines(result, from1, to1, from2, to2, count1, count2)
        end
      end

      # Check if the middle content (after removing common prefix/suffix) is truly
      # orphaned - meaning it exists in only one text, not both.
      # Returns true if content exists in only one text (not reflow).
      def slice_middle_orphaned?(slice1, slice2)
        return false if slice1.empty? || slice2.empty?

        # Check if slice1 content exists anywhere in text2
        slice1_all_in_text2 = slice1.all? do |line|
          @line_to_indices2.key?(line)
        end
        # Check if slice2 content exists anywhere in text1
        slice2_all_in_text1 = slice2.all? do |line|
          @line_to_indices1.key?(line)
        end

        # If either slice has no presence in the other text, it's orphaned
        !slice1_all_in_text2 || !slice2_all_in_text1
      end

      # Handle gap lines when one text has more lines than the other.
      # Determines whether lines are orphaned (exist in both texts at different
      # positions) or reflow (formatting-only).
      #
      # IMPORTANT: We never emit DiffLines without diff_nodes for gap content.
      # If content exists in one text but not the other, the comparison should
      # have reported it as a diff_node. We only emit :unchanged for orphaned
      # content when we can find it in the other text at a different position.
      def emit_gap_lines(result, from1, to1, from2, to2, count1, count2)
        if count1.positive?
          # Lines only in text1: check if they exist in text2 at different positions
          if count1 >= REFLOW_SUMMARY_THRESHOLD
            all_exist_in_text2 = (0...count1).all? do |i|
              line_idx = from1 + i
              line_idx < @lines1.length &&
                @line_to_indices2.key?(@lines1[line_idx])
            end
            if all_exist_in_text2
              emit_orphaned_unchanged(result, from1, to1, from2,
                                      @line_to_indices2, true)
              # Also emit extra lines from text2 as :added (text2 has more lines)
              emit_extra_added_lines(result, from1, to1, from2, count1, count2)
            else
              # Can't emit individual lines without diff_nodes — use summary
              emit_reflow_summary(result, from1, to1, from2, to2)
            end
          else
            # Small gap: check each line individually
            # Only emit :unchanged if we can find content in text2.
            # DON'T emit :removed formatting lines without diff_nodes.
            count1.times do |i|
              line_idx = from1 + i
              next if line_idx >= @lines1.length

              content = @lines1[line_idx]
              if @line_to_indices2.key?(content)
                # Found in text2: emit as :unchanged with correct position
                new_pos = @line_to_indices2[content].min_by do |idx|
                  (idx - from2).abs
                end
                result << DiffLine.new(
                  line_number: line_idx,
                  new_position: new_pos,
                  content: content,
                  type: :unchanged,
                )
              end
              # If not found in text2: don't emit anything.
              # The comparison should have reported this as a diff_node.
            end
          end
        elsif count2.positive?
          # Lines only in text2: check if they exist in text1 at different positions
          # When count1=0, don't emit unchanged lines here - they'll be emitted
          # from the text1 gap when cursor1 catches up.
          if count1.zero?
            # Pure insertion: text1 has no gap. The text2 gap lines are unchanged
            # and correspond to text1 positions. Emit them from text1's perspective
            # to avoid duplicates when cursor1 catches up.
            count2.times do |i|
              line_idx = from2 + i
              next if line_idx >= @lines2.length

              content = @lines2[line_idx]
              if @line_to_indices1.key?(content)
                # Found in text1: emit as :unchanged with TEXT1 line number
                text1_pos = @line_to_indices1[content].min_by do |idx|
                  (idx - from1).abs
                end
                result << DiffLine.new(
                  line_number: text1_pos, # Use text1 position as primary
                  new_position: line_idx, # Use text2 position as secondary
                  content: content,
                  type: :unchanged,
                )
              end
              # If not found in text1: don't emit anything
            end
          elsif count2 >= REFLOW_SUMMARY_THRESHOLD
            all_exist_in_text1 = (0...count2).all? do |i|
              line_idx = from2 + i
              line_idx < @lines2.length &&
                @line_to_indices1.key?(@lines2[line_idx])
            end
            if all_exist_in_text1
              # All content exists in text1 but at different positions: treat as reflow
              # Emit orphaned content with position mapping
              emit_orphaned_unchanged(result, from2, to2, from1, from1, true)
            else
              emit_reflow_summary(result, from1, to1, from2, to2)
            end
          else
            count2.times do |i|
              line_idx = from2 + i
              next if line_idx >= @lines2.length

              content = @lines2[line_idx]
              if @line_to_indices1.key?(content)
                new_pos = @line_to_indices1[content].min_by do |idx|
                  (idx - from1).abs
                end
                result << DiffLine.new(
                  line_number: line_idx,
                  new_position: new_pos,
                  content: content,
                  type: :unchanged,
                )
              end
              # If not found in text1: don't emit anything
            end
          end
        end
      end

      # Emit extra lines from text2 as :added when text2 has more lines than text1
      # in a gap where all of text1's content exists in text2 (reflow case).
      def emit_extra_added_lines(result, from1, to1, from2, count1, count2)
        return unless count2 > count1

        extra_count = count2 - count1
        extra_lines_in_text2 = @lines2[from2...(from2 + count2)]
        text1_set = @lines1[from1...to1].to_set
        extra_lines_in_text2.each do |content|
          next if text1_set.include?(content)

          extra_count -= 1
          next if extra_count.negative?

          line_idx = @line_to_indices2[content].min_by do |idx|
            (idx - from2).abs
          end
          result << DiffLine.new(
            line_number: line_idx,
            new_position: line_idx,
            content: content,
            type: :added,
            formatting: true,
          )
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
        max_suffix = [slice1.length - prefix_len,
                      slice2.length - prefix_len].min
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
          emit_reflow_summary(result, mid_start1, mid_end1, mid_start2,
                              mid_end2)
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
      #
      # IMPORTANT: We only emit representative removed/added lines if they
      # actually exist in the other text. Lines that are truly orphaned
      # (don't exist in the other text) are NOT emitted as individual lines
      # since that would be "inventing" diffs without diff_nodes.
      def emit_reflow_summary(result, mid_start1, mid_end1, mid_start2,
mid_end2)
        mid_count1 = mid_end1 - mid_start1
        mid_count2 = mid_end2 - mid_start2

        # Only emit representative lines if they exist in the other text.
        # This avoids "inventing" diffs for content that truly doesn't exist.
        first_removed_content = mid_count1.positive? && mid_start1 < @lines1.length ? @lines1[mid_start1] : nil
        first_added_content = mid_count2.positive? && mid_start2 < @lines2.length ? @lines2[mid_start2] : nil

        # Check if first lines exist in the other text (not truly orphaned)
        show_first_removed = first_removed_content && @line_to_indices2.key?(first_removed_content)
        show_first_added = first_added_content && @line_to_indices1.key?(first_added_content)

        if show_first_removed
          result << DiffLine.new(
            line_number: mid_start1,
            content: first_removed_content,
            type: :removed,
            formatting: true,
          )
        end

        if show_first_added
          result << DiffLine.new(
            line_number: mid_start2,
            new_position: mid_start2,
            content: first_added_content,
            type: :added,
            formatting: true,
          )
        end

        # Summary line when there are more than the first-shown pair
        extra1 = show_first_removed ? [mid_count1 - 1, 0].max : mid_count1
        extra2 = show_first_added ? [mid_count2 - 1, 0].max : mid_count2

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

      # Emit orphaned lines that exist in both texts but at different positions.
      # This handles the case where structural changes cause content to be
      # repositioned rather than added/removed.
      #
      # @param result [Array<DiffLine>] output array
      # @param from1 [Integer] start line in text1
      # @param to1 [Integer] end line (exclusive) in text1
      # @param from2 [Integer] start line in text2
      # @param to2 [Integer] end line (exclusive) in text2
      # @param text1_orphaned [Boolean] true if text1 has the orphaned lines
      def emit_orphaned_unchanged(result, from1, to1, from2, to2,
text1_orphaned)
        if text1_orphaned
          count = to1 - from1
          count.times do |i|
            line_idx = from1 + i
            next if line_idx >= @lines1.length

            content = @lines1[line_idx]
            next unless content

            if @line_to_indices2.key?(content)
              new_pos = @line_to_indices2[content].min_by do |idx|
                (idx - from2).abs
              end
              result << DiffLine.new(
                line_number: line_idx,
                new_position: new_pos,
                content: content,
                type: :unchanged,
              )
            end
          end
        else
          count = to2 - from2
          count.times do |i|
            line_idx = from2 + i
            next if line_idx >= @lines2.length

            content = @lines2[line_idx]
            next unless content

            if @line_to_indices1.key?(content)
              new_pos = @line_to_indices1[content].min_by do |idx|
                (idx - from1).abs
              end
              result << DiffLine.new(
                line_number: line_idx,
                new_position: new_pos,
                content: content,
                type: :unchanged,
              )
            end
          end
        end
      end

      # Detect reflow: lines that exist in text1 but whose content is absorbed
      # into an adjacent changed line in text2 (or vice versa).
      def handle_reflow(result, cursor1, node_start1, _cursor2, _node_start2,
diff_node)
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
          emit_changed_lines(result, diff_node, old_line_ranges,
                             new_line_ranges)
        elsif has_old
          # Removed: only in text1
          emit_removed_lines(result, diff_node, old_line_ranges)
        elsif has_new
          # Added: only in text2
          emit_added_lines(result, diff_node, new_line_ranges)
        end
      end

      # Emit DiffLines for a change that exists in both texts.
      def emit_changed_lines(result, diff_node, old_line_ranges,
new_line_ranges)
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
        old_lines = old_line_ranges.keys.sort

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

        # Emit continuation lines when line_range_before extends beyond the lines
        # that have char_ranges. This handles multi-line elements where
        # TextDecomposer only creates char_ranges on the starting line.
        range1 = diff_node.line_range_before
        if range1 && old_lines.any? && old_lines.last < range1[1]
          ((old_lines.last + 1)..range1[1]).each do |cont_line_idx|
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
      end

      # Emit DiffLines for an addition (only in text2).
      def emit_added_lines(result, diff_node, new_line_ranges)
        new_lines = new_line_ranges.keys.sort

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

        # Emit continuation lines when line_range_after extends beyond the lines
        # that have char_ranges. This handles multi-line elements where
        # TextDecomposer only creates char_ranges on the starting line.
        range2 = diff_node.line_range_after
        if range2 && new_lines.any? && new_lines.last < range2[1]
          ((new_lines.last + 1)..range2[1]).each do |cont_line_idx|
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
      end

      # Build a reverse index mapping line content to array of line indices.
      # Used for efficient lookup when handling orphaned lines in gaps.
      #
      # @param lines [Array<String>] Array of lines
      # @return [Hash{String => Array<Integer>}] Map from content to indices
      def build_line_index(lines)
        index = Hash.new { |h, k| h[k] = [] }
        lines.each_with_index { |line, idx| index[line] << idx }
        index
      end

      public :build_line_index

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
      # If node exists and is normative:
      # - Return false — normative DiffNodes are NEVER formatting-only.
      #   Even if the serialized content looks whitespace-equivalent,
      #   the comparison classified it as a normative change and it MUST
      #   be visible in by_line output (especially with show_diffs: :normative).
      #
      # If node exists and is informative (norm=false):
      # - Return false (informative diffs are shown as informative)
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
          # Normative nodes are never formatting-only
          return false if diff_node.normative?

          # Informative nodes: check line-level formatting
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
