# frozen_string_literal: true

require_relative "diff_char_range"
require_relative "text_decomposer"
require_relative "source_locator"

module Canon
  module Diff
    # Enriches DiffNodes with character position data (DiffCharRanges).
    #
    # This is Phase 1 of the two-phase diff pipeline. It runs after comparison
    # and before rendering. It CAN use string operations (including LCS) on
    # serialized content to determine character-level change positions.
    #
    # The output is DiffNodes enriched with:
    # - char_ranges: Array<DiffCharRange> mapping changes to specific line/columns
    # - line_range_before: [start_line, end_line] in text1
    # - line_range_after: [start_line, end_line] in text2
    #
    # Phase 2 (DiffLineBuilder) then assembles DiffLines from these enriched
    # DiffNodes without any further computation.
    class DiffNodeEnricher
      # Enrich DiffNodes with character position data.
      #
      # @param diff_nodes [Array<DiffNode>] The semantic differences
      # @param text1 [String] The first document (preprocessed)
      # @param text2 [String] The second document (preprocessed)
      # @return [Array<DiffNode>] The same DiffNodes, enriched in place
      def self.build(diff_nodes, text1, text2)
        return diff_nodes if diff_nodes.nil? || diff_nodes.empty?
        return diff_nodes if text1.nil? || text2.nil?

        new(diff_nodes, text1, text2).enrich
      end

      def initialize(diff_nodes, text1, text2)
        @diff_nodes = diff_nodes
        @text1 = text1
        @text2 = text2
        @line_map1 = SourceLocator.build_line_map(text1)
        @line_map2 = SourceLocator.build_line_map(text2)
        @lines1 = text1.split("\n")
        @lines2 = text2.split("\n")
        # Track occurrences for text_content dimension to find correct element instance
        @text_occurrence1 = Hash.new(0)
        @text_occurrence2 = Hash.new(0)
      end

      def enrich
        @diff_nodes.each do |diff_node|
          enrich_node(diff_node)
        end
        @diff_nodes
      end

      private

      # Enrich a single DiffNode with DiffCharRanges based on its dimension.
      def enrich_node(diff_node)
        case diff_node.dimension
        when :text_content
          enrich_text_content(diff_node)
        when :attribute_values
          enrich_attribute_values(diff_node)
        when :attribute_presence
          enrich_attribute_presence(diff_node)
        when :attribute_order
          enrich_attribute_order(diff_node)
        when :comments
          enrich_comments(diff_node)
        when :structural_whitespace
          enrich_structural_whitespace(diff_node)
        when :element_structure
          enrich_element_structure(diff_node)
        else
          enrich_generic(diff_node)
        end
      end

      # Text content change: decompose serialized_before/after into
      # before-text, changed-text, after-text and map to DiffCharRanges.
      def enrich_text_content(diff_node)
        before = diff_node.serialized_before
        after = diff_node.serialized_after

        if before.nil? && after.nil?
          return
        end

        # One side is nil = pure insertion/deletion
        if before.nil?
          loc = locate_at_element_index(after, @text2, @line_map2, diff_node.path)
          loc ||= locate_via_parent_element(diff_node.path, @text2, @line_map2)
          loc ||= locate_via_node_tree(diff_node.node2, after, @text2, @line_map2, :new)
          # Final fallback: when tree-based location in text2 fails because the
          # leaf element is self-closing (text moved OUTSIDE the element in text2),
          # search in text1 (original) using path-based location. The original
          # has the correct element structure with content intact.
          loc ||= locate_via_parent_element(diff_node.path, @text1, @line_map1)
          return unless loc

          cr = DiffCharRange.new(
            line_number: loc[:line_number],
            start_col: loc[:col],
            end_col: loc[:col] + after.length,
            side: :new,
            status: :added,
            role: :changed,
            diff_node: diff_node,
          )
          diff_node.char_ranges = [cr]
          diff_node.line_range_before = nil
          diff_node.line_range_after = [loc[:line_number], loc[:line_number]]
          return
        end

        if after.nil?
          loc = locate_at_element_index(before, @text1, @line_map1, diff_node.path)
          loc ||= locate_via_parent_element(diff_node.path, @text1, @line_map1)
          loc ||= locate_via_node_tree(diff_node.node1, before, @text1, @line_map1, :old)
          return unless loc

          cr = DiffCharRange.new(
            line_number: loc[:line_number],
            start_col: loc[:col],
            end_col: loc[:col] + before.length,
            side: :old,
            status: :removed,
            role: :changed,
            diff_node: diff_node,
          )
          diff_node.char_ranges = [cr]
          diff_node.line_range_before = [loc[:line_number], loc[:line_number]]
          diff_node.line_range_after = nil
          return
        end

        # Both sides exist: locate and decompose
        loc1 = locate_at_element_index(before, @text1, @line_map1, diff_node.path)
        loc2 = locate_at_element_index(after, @text2, @line_map2, diff_node.path)

        unless loc1 && loc2
          # Cannot locate - element_structure changes can't be located without exact match
          return
        end

        # Decompose into 3 parts
        parts = TextDecomposer.decompose(before, after)
        ranges = []

        # Before-text (unchanged prefix)
        unless parts[:common_prefix].empty?
          prefix_len = parts[:common_prefix].length

          ranges << DiffCharRange.new(
            line_number: loc1[:line_number],
            start_col: loc1[:col],
            end_col: loc1[:col] + prefix_len,
            side: :old,
            status: :unchanged,
            role: :before,
            diff_node: diff_node,
          )

          ranges << DiffCharRange.new(
            line_number: loc2[:line_number],
            start_col: loc2[:col],
            end_col: loc2[:col] + prefix_len,
            side: :new,
            status: :unchanged,
            role: :before,
            diff_node: diff_node,
          )
        end

        # Changed-text (the actual difference)
        unless parts[:changed_old].empty? && parts[:changed_new].empty?
          prefix_offset = parts[:common_prefix].length

          unless parts[:changed_old].empty?
            ranges << DiffCharRange.new(
              line_number: loc1[:line_number],
              start_col: loc1[:col] + prefix_offset,
              end_col: loc1[:col] + prefix_offset + parts[:changed_old].length,
              side: :old,
              status: :changed_old,
              role: :changed,
              diff_node: diff_node,
            )
          end

          unless parts[:changed_new].empty?
            ranges << DiffCharRange.new(
              line_number: loc2[:line_number],
              start_col: loc2[:col] + prefix_offset,
              end_col: loc2[:col] + prefix_offset + parts[:changed_new].length,
              side: :new,
              status: :changed_new,
              role: :changed,
              diff_node: diff_node,
            )
          end
        end

        # After-text (unchanged suffix)
        unless parts[:common_suffix].empty?
          suffix_offset_old = loc1[:col] + before.length - parts[:common_suffix].length
          suffix_offset_new = loc2[:col] + after.length - parts[:common_suffix].length
          suffix_len = parts[:common_suffix].length

          ranges << DiffCharRange.new(
            line_number: loc1[:line_number],
            start_col: suffix_offset_old,
            end_col: suffix_offset_old + suffix_len,
            side: :old,
            status: :unchanged,
            role: :after,
            diff_node: diff_node,
          )

          ranges << DiffCharRange.new(
            line_number: loc2[:line_number],
            start_col: suffix_offset_new,
            end_col: suffix_offset_new + suffix_len,
            side: :new,
            status: :unchanged,
            role: :after,
            diff_node: diff_node,
          )
        end

        diff_node.char_ranges = ranges
        # Compute actual line span for multi-line text content.
        # Content like "abc\ndef" spans 2 lines.
        newline_count_before = before.count("\n")
        newline_count_after = after.count("\n")
        end_line_before = loc1[:line_number] + newline_count_before
        end_line_after = loc2[:line_number] + newline_count_after
        diff_node.line_range_before = [loc1[:line_number], end_line_before]
        diff_node.line_range_after = [loc2[:line_number], end_line_after]
      end

      # Attribute value change: locate the specific attribute values in the text.
      def enrich_attribute_values(diff_node)
        attrs_before = diff_node.attributes_before
        attrs_after = diff_node.attributes_after
        return unless attrs_before && attrs_after

        # Find which attributes changed
        all_keys = (attrs_before.keys + attrs_after.keys).uniq
        changed_keys = all_keys.reject do |key|
          attrs_before[key] == attrs_after[key]
        end

        return if changed_keys.empty?

        ranges = []
        line1_num = nil
        line2_num = nil

        changed_keys.each do |key|
          old_val = attrs_before[key]
          new_val = attrs_after[key]

          # Find in text1: key="old_val"
          # Use element_name to scope the search and avoid matching
          # attributes in the XML declaration (e.g., version="1.0" in
          # <?xml version="1.0"?> vs <element version="1.0">)
          element_name = diff_node.node1&.name
          if old_val
            pattern = build_attr_pattern(key, old_val)
            start_from = xml_declaration_end_offset(@text1)
            loc = SourceLocator.locate(pattern, @text1, @line_map1,
                                       start_from: start_from)
            # If not found after XML decl, try with element-scoped pattern
            if loc.nil? && element_name
              scoped = "#{element_name} #{pattern}"
              loc = SourceLocator.locate(scoped, @text1, @line_map1)
              # Adjust col to point to the attribute, not the element name
              loc = loc.merge(col: loc[:col] + element_name.length + 1) if loc
            end
            if loc
              line1_num ||= loc[:line_number]
              ranges << DiffCharRange.new(
                line_number: loc[:line_number],
                start_col: loc[:col] + key.length + 2, # skip key="
                end_col: loc[:col] + pattern.length - 1, # skip closing "
                side: :old,
                status: :changed_old,
                role: :changed,
                diff_node: diff_node,
              )
            end
          end

          # Find in text2: key="new_val"
          element_name2 = diff_node.node2&.name
          if new_val
            pattern = build_attr_pattern(key, new_val)
            start_from = xml_declaration_end_offset(@text2)
            loc = SourceLocator.locate(pattern, @text2, @line_map2,
                                       start_from: start_from)
            if loc.nil? && element_name2
              scoped = "#{element_name2} #{pattern}"
              loc = SourceLocator.locate(scoped, @text2, @line_map2)
              loc = loc.merge(col: loc[:col] + element_name2.length + 1) if loc
            end
            if loc
              line2_num ||= loc[:line_number]
              ranges << DiffCharRange.new(
                line_number: loc[:line_number],
                start_col: loc[:col] + key.length + 2,
                end_col: loc[:col] + pattern.length - 1,
                side: :new,
                status: :changed_new,
                role: :changed,
                diff_node: diff_node,
              )
            end
          end
        end

        diff_node.char_ranges = ranges
        diff_node.line_range_before = line1_num ? [line1_num, line1_num] : nil
        diff_node.line_range_after = line2_num ? [line2_num, line2_num] : nil
      end

      # Attribute presence change: find added/removed attributes.
      def enrich_attribute_presence(diff_node)
        attrs_before = diff_node.attributes_before || {}
        attrs_after = diff_node.attributes_after || {}

        added_keys = attrs_after.keys - attrs_before.keys
        removed_keys = attrs_before.keys - attrs_after.keys

        return if added_keys.empty? && removed_keys.empty?

        ranges = []
        line1_num = nil
        line2_num = nil

        # Removed attributes (only in text1)
        removed_keys.each do |key|
          val = attrs_before[key]
          pattern = build_attr_pattern(key, val)
          start_from = xml_declaration_end_offset(@text1)
          loc = SourceLocator.locate(pattern, @text1, @line_map1,
                                     start_from: start_from)
          next unless loc

          line1_num ||= loc[:line_number]
          ranges << DiffCharRange.new(
            line_number: loc[:line_number],
            start_col: loc[:col],
            end_col: loc[:col] + pattern.length,
            side: :old,
            status: :removed,
            role: :changed,
            diff_node: diff_node,
          )
        end

        # Added attributes (only in text2)
        added_keys.each do |key|
          val = attrs_after[key]
          pattern = build_attr_pattern(key, val)
          start_from = xml_declaration_end_offset(@text2)
          loc = SourceLocator.locate(pattern, @text2, @line_map2,
                                     start_from: start_from)
          next unless loc

          line2_num ||= loc[:line_number]
          ranges << DiffCharRange.new(
            line_number: loc[:line_number],
            start_col: loc[:col],
            end_col: loc[:col] + pattern.length,
            side: :new,
            status: :added,
            role: :changed,
            diff_node: diff_node,
          )
        end

        diff_node.char_ranges = ranges
        diff_node.line_range_before = line1_num ? [line1_num, line1_num] : nil
        diff_node.line_range_after = line2_num ? [line2_num, line2_num] : nil
      end

      # Attribute order change: highlight entire attribute sections as formatting.
      def enrich_attribute_order(diff_node)
        before = diff_node.serialized_before
        after = diff_node.serialized_after

        loc1 = SourceLocator.locate(before, @text1, @line_map1) if before
        loc2 = SourceLocator.locate(after, @text2, @line_map2) if after

        ranges = []

        if loc1
          ranges << DiffCharRange.new(
            line_number: loc1[:line_number],
            start_col: loc1[:col],
            end_col: loc1[:col] + before.length,
            side: :old,
            status: :unchanged,
            role: :changed,
            diff_node: diff_node,
          )
        end

        if loc2
          ranges << DiffCharRange.new(
            line_number: loc2[:line_number],
            start_col: loc2[:col],
            end_col: loc2[:col] + after.length,
            side: :new,
            status: :unchanged,
            role: :changed,
            diff_node: diff_node,
          )
        end

        diff_node.char_ranges = ranges
        diff_node.line_range_before = loc1 ? [loc1[:line_number], loc1[:line_number]] : nil
        diff_node.line_range_after = loc2 ? [loc2[:line_number], loc2[:line_number]] : nil
      end

      # Comment change: locate and decompose comment content.
      def enrich_comments(diff_node)
        before = diff_node.serialized_before
        after = diff_node.serialized_after

        if before.nil? && after.nil?
          return
        end

        # Pure addition or removal
        if before.nil?
          loc = SourceLocator.locate(after, @text2, @line_map2)
          return unless loc

          diff_node.char_ranges = [
            DiffCharRange.new(
              line_number: loc[:line_number],
              start_col: loc[:col],
              end_col: loc[:col] + after.length,
              side: :new,
              status: :added,
              role: :changed,
              diff_node: diff_node,
            ),
          ]
          diff_node.line_range_after = [loc[:line_number], loc[:line_number]]
          return
        end

        if after.nil?
          loc = SourceLocator.locate(before, @text1, @line_map1)
          return unless loc

          diff_node.char_ranges = [
            DiffCharRange.new(
              line_number: loc[:line_number],
              start_col: loc[:col],
              end_col: loc[:col] + before.length,
              side: :old,
              status: :removed,
              role: :changed,
              diff_node: diff_node,
            ),
          ]
          diff_node.line_range_before = [loc[:line_number], loc[:line_number]]
          return
        end

        # Both exist: locate and decompose
        loc1 = SourceLocator.locate(before, @text1, @line_map1)
        loc2 = SourceLocator.locate(after, @text2, @line_map2)

        unless loc1 && loc2
          enrich_generic(diff_node)
          return
        end

        parts = TextDecomposer.decompose(before, after)
        ranges = []

        # Prefix (unchanged)
        unless parts[:common_prefix].empty?
          prefix_len = parts[:common_prefix].length
          ranges << DiffCharRange.new(
            line_number: loc1[:line_number], start_col: loc1[:col],
            end_col: loc1[:col] + prefix_len,
            side: :old, status: :unchanged, role: :before, diff_node: diff_node
          )
          ranges << DiffCharRange.new(
            line_number: loc2[:line_number], start_col: loc2[:col],
            end_col: loc2[:col] + prefix_len,
            side: :new, status: :unchanged, role: :before, diff_node: diff_node
          )
        end

        # Changed portion
        unless parts[:changed_old].empty? && parts[:changed_new].empty?
          prefix_offset = parts[:common_prefix].length

          unless parts[:changed_old].empty?
            ranges << DiffCharRange.new(
              line_number: loc1[:line_number],
              start_col: loc1[:col] + prefix_offset,
              end_col: loc1[:col] + prefix_offset + parts[:changed_old].length,
              side: :old, status: :changed_old, role: :changed, diff_node: diff_node
            )
          end

          unless parts[:changed_new].empty?
            ranges << DiffCharRange.new(
              line_number: loc2[:line_number],
              start_col: loc2[:col] + prefix_offset,
              end_col: loc2[:col] + prefix_offset + parts[:changed_new].length,
              side: :new, status: :changed_new, role: :changed, diff_node: diff_node
            )
          end
        end

        # Suffix (unchanged)
        unless parts[:common_suffix].empty?
          s_off_old = loc1[:col] + before.length - parts[:common_suffix].length
          s_off_new = loc2[:col] + after.length - parts[:common_suffix].length
          s_len = parts[:common_suffix].length
          ranges << DiffCharRange.new(
            line_number: loc1[:line_number], start_col: s_off_old,
            end_col: s_off_old + s_len,
            side: :old, status: :unchanged, role: :after, diff_node: diff_node
          )
          ranges << DiffCharRange.new(
            line_number: loc2[:line_number], start_col: s_off_new,
            end_col: s_off_new + s_len,
            side: :new, status: :unchanged, role: :after, diff_node: diff_node
          )
        end

        diff_node.char_ranges = ranges
        diff_node.line_range_before = [loc1[:line_number], loc1[:line_number]]
        diff_node.line_range_after = [loc2[:line_number], loc2[:line_number]]
      end

      # Structural whitespace: mark affected lines as formatting-only.
      def enrich_structural_whitespace(diff_node)
        before = diff_node.serialized_before
        after = diff_node.serialized_after

        loc1 = SourceLocator.locate(before, @text1, @line_map1) if before
        loc2 = SourceLocator.locate(after, @text2, @line_map2) if after

        ranges = []

        if loc1 && before
          ranges << DiffCharRange.new(
            line_number: loc1[:line_number],
            start_col: loc1[:col],
            end_col: loc1[:col] + before.length,
            side: :old,
            status: :unchanged,
            role: :changed,
            diff_node: diff_node,
          )
        end

        if loc2 && after
          ranges << DiffCharRange.new(
            line_number: loc2[:line_number],
            start_col: loc2[:col],
            end_col: loc2[:col] + after.length,
            side: :new,
            status: :unchanged,
            role: :changed,
            diff_node: diff_node,
          )
        end

        diff_node.char_ranges = ranges
        diff_node.line_range_before = loc1 ? [loc1[:line_number], loc1[:line_number]] : nil
        diff_node.line_range_after = loc2 ? [loc2[:line_number], loc2[:line_number]] : nil
      end

      # Element structure change: full element deletion/insertion.
      # Locate the entire element (opening tag through closing tag).
      def enrich_element_structure(diff_node)
        before = diff_node.serialized_before
        after = diff_node.serialized_after
        path = diff_node.path

        if before.nil? && after.nil?
          return
        end

        # Minimum reliable length for SourceLocator.locate to find the correct
        # occurrence. Shorter strings match too many places in the document.
        min_locate_length = 3

        # Element added (only in text2)
        if before.nil?
          loc = if after.length < min_locate_length && path
                  locate_via_parent_element(path, @text2, @line_map2)
                else
                  SourceLocator.locate(after, @text2, @line_map2)
                end

          if loc
            end_line = find_end_line(loc[:line_number], @line_map2, after)
            diff_node.char_ranges = [
              DiffCharRange.new(
                line_number: loc[:line_number],
                start_col: loc[:col],
                end_col: loc[:col] + after.length,
                side: :new,
                status: :added,
                role: :changed,
                diff_node: diff_node,
              ),
            ]
            diff_node.line_range_before = nil
            diff_node.line_range_after = [loc[:line_number], end_line]
          else
            # Fallback: can't locate exact content, mark entire text2 as affected
            fallback_element_structure_ranges(diff_node, nil, after, :new)
          end
          return
        end

        # Element removed (only in text1)
        if after.nil?
          loc = if before.length < min_locate_length && path
                  locate_via_parent_element(path, @text1, @line_map1)
                else
                  SourceLocator.locate(before, @text1, @line_map1)
                end

          if loc
            end_line = find_end_line(loc[:line_number], @line_map1, before)
            diff_node.char_ranges = [
              DiffCharRange.new(
                line_number: loc[:line_number],
                start_col: loc[:col],
                end_col: loc[:col] + before.length,
                side: :old,
                status: :changed_old,
                role: :changed,
                diff_node: diff_node,
              ),
            ]
            diff_node.line_range_before = [loc[:line_number], end_line]
            diff_node.line_range_after = nil
          else
            # Try using node1's parent element as anchor for text nodes
            loc = locate_textnode_parent(diff_node.node1, before, @text1, @line_map1)
            if loc
              end_line = find_end_line(loc[:line_number], @line_map1, before)
              diff_node.char_ranges = [
                DiffCharRange.new(
                  line_number: loc[:line_number],
                  start_col: loc[:col],
                  end_col: loc[:col] + before.length,
                  side: :old,
                  status: :changed_old,
                  role: :changed,
                  diff_node: diff_node,
                ),
              ]
              diff_node.line_range_before = [loc[:line_number], end_line]
              diff_node.line_range_after = nil
            else
              # Fallback: can't locate exact content, mark entire text1 as affected
              fallback_element_structure_ranges(diff_node, before, nil, :old)
            end
          end
          return
        end

        # Both exist: structural change (e.g., element renamed)
        loc1 = if before.length < min_locate_length && path
                 locate_via_parent_element(path, @text1, @line_map1)
               else
                 SourceLocator.locate(before, @text1, @line_map1)
               end
        loc2 = if after.length < min_locate_length && path
                 locate_via_parent_element(path, @text2, @line_map2)
               else
                 SourceLocator.locate(after, @text2, @line_map2)
               end

        ranges = []

        if loc1
          ranges << DiffCharRange.new(
            line_number: loc1[:line_number],
            start_col: loc1[:col],
            end_col: loc1[:col] + before.length,
            side: :old,
            status: :changed_old,
            role: :changed,
            diff_node: diff_node,
          )
        end

        if loc2
          ranges << DiffCharRange.new(
            line_number: loc2[:line_number],
            start_col: loc2[:col],
            end_col: loc2[:col] + after.length,
            side: :new,
            status: :changed_new,
            role: :changed,
            diff_node: diff_node,
          )
        end

        diff_node.char_ranges = ranges
        diff_node.line_range_before = loc1 ? [loc1[:line_number], loc1[:line_number]] : nil
        diff_node.line_range_after = loc2 ? [loc2[:line_number], loc2[:line_number]] : nil
      end

      # Fallback for element_structure when exact location fails.
      # Uses element name matching to find affected lines.
      def fallback_element_structure_ranges(diff_node, before, after, side)
        element_name = extract_element_name(before || after)
        return unless element_name

        ranges = []

        if %i[old both].include?(side)
          # Element removed from text1 (before exists, after nil)
          old_lines = find_lines_with_element(element_name, @lines1, @text1)
          old_lines.each do |line_idx|
            ranges << DiffCharRange.new(
              line_number: line_idx,
              start_col: 0,
              end_col: @lines1[line_idx].length,
              side: :old,
              status: :removed,
              role: :changed,
              diff_node: diff_node,
            )
          end
          diff_node.line_range_before = old_lines.any? ? old_lines.minmax : nil
        end

        if %i[new both].include?(side)
          # Element added to text2 (before nil, after exists)
          new_lines = find_lines_with_element(element_name, @lines2, @text2)
          new_lines.each do |line_idx|
            ranges << DiffCharRange.new(
              line_number: line_idx,
              start_col: 0,
              end_col: @lines2[line_idx].length,
              side: :new,
              status: :added,
              role: :changed,
              diff_node: diff_node,
            )
          end
          diff_node.line_range_after = new_lines.any? ? new_lines.minmax : nil
        end

        diff_node.char_ranges = ranges
      end

      def find_lines_with_element(element_name, lines, _text)
        result = []
        lines.each_with_index do |line, idx|
          # Check if line contains opening or closing tag for this element
          if line.include?("<#{element_name}") || line.include?("</#{element_name}>")
            result << idx
          end
        end
        result
      end

      def extract_element_name(content)
        return nil if content.nil?

        # Match opening or closing tag: <element or </element>
        match = content.match(/<\/?([a-zA-Z0-9_:-]+)/)
        match[1] if match
      end

      # Generic fallback: try to locate and decompose serialized content.
      # Does NOT call enrich_text_content to avoid infinite recursion.
      def enrich_generic(diff_node)
        before = diff_node.serialized_before
        after = diff_node.serialized_after

        if before && after
          # Both sides exist: locate the entire changed region
          loc1 = SourceLocator.locate(before, @text1, @line_map1)
          loc2 = SourceLocator.locate(after, @text2, @line_map2)

          ranges = []
          if loc1
            ranges << DiffCharRange.new(
              line_number: loc1[:line_number],
              start_col: loc1[:col],
              end_col: loc1[:col] + before.length,
              side: :old,
              status: :changed_old,
              role: :changed,
              diff_node: diff_node,
            )
          end
          if loc2
            ranges << DiffCharRange.new(
              line_number: loc2[:line_number],
              start_col: loc2[:col],
              end_col: loc2[:col] + after.length,
              side: :new,
              status: :changed_new,
              role: :changed,
              diff_node: diff_node,
            )
          end
          diff_node.char_ranges = ranges
          diff_node.line_range_before = loc1 ? [loc1[:line_number], loc1[:line_number]] : nil
          diff_node.line_range_after = loc2 ? [loc2[:line_number], loc2[:line_number]] : nil
        elsif before
          loc = SourceLocator.locate(before, @text1, @line_map1)
          return unless loc

          diff_node.char_ranges = [
            DiffCharRange.new(
              line_number: loc[:line_number],
              start_col: loc[:col],
              end_col: loc[:col] + before.length,
              side: :old,
              status: :removed,
              role: :changed,
              diff_node: diff_node,
            ),
          ]
          diff_node.line_range_before = [loc[:line_number], loc[:line_number]]
        elsif after
          loc = SourceLocator.locate(after, @text2, @line_map2)
          return unless loc

          diff_node.char_ranges = [
            DiffCharRange.new(
              line_number: loc[:line_number],
              start_col: loc[:col],
              end_col: loc[:col] + after.length,
              side: :new,
              status: :added,
              role: :changed,
              diff_node: diff_node,
            ),
          ]
          diff_node.line_range_after = [loc[:line_number], loc[:line_number]]
        end
      end

      # Build an attribute pattern string: key="value"
      def build_attr_pattern(key, value)
        "#{key}=\"#{value}\""
      end

      # Return the character offset just past the XML declaration `?>`,
      # or 0 if there is no XML declaration.
      #
      # The XML declaration can contain attributes like version, encoding
      # that may collide with element attributes. Skipping past it prevents
      # false matches when locating attribute patterns.
      #
      # @param text [String] the source text
      # @return [Integer] character offset past the XML declaration, or 0
      def xml_declaration_end_offset(text)
        if text.start_with?("<?xml")
          idx = text.index("?>")
          idx ? idx + 2 : 0
        else
          0
        end
      end

      # Find the last line that content starting at start_line spans.
      # Handles multi-line serialized content.
      #
      # @param start_line [Integer] 0-based line where content starts
      # @param line_map [Array<Hash>] line offset map
      # @param content [String] the serialized content
      # @return [Integer] the last line number
      def find_end_line(start_line, line_map, content)
        newline_count = content.count("\n")
        [start_line + newline_count, line_map.length - 1].min
      end

      # Find the occurrence of a value at a specific element index.
      # Used for text_content changes when the same text appears multiple times
      # in different elements (e.g., "original" in multiple item elements).
      #
      # @param value [String] the text to find
      # @param text [String] the source text
      # @param line_map [Array<Hash>] pre-built line offset map
      # @param path [String] the diff node path (e.g., "/root[0]/item[1]/unknown[0]")
      # @return [Hash, nil] location hash or nil if not found
      def locate_at_element_index(value, text, line_map, path)
        # Path like "/root[0]/item[1]/unknown[0]" has multiple segments.
        # For text_content changes, the last segment is the text node,
        # and the second-to-last is the element whose text changed.
        # We need to find "item[1]" not "unknown[0]".
        segments = path.split("/").reject(&:empty?)
        return SourceLocator.locate(value, text, line_map) if segments.length < 2

        # Start from segments[-2] (skip the last segment which is the text node)
        # and walk backwards to find a segment with a bracket index.
        # E.g., path "named-content[0]/named-content/text()[0]" — segments[-2]
        # is "named-content" (no bracket), so we skip to segments[-3]
        # "named-content[0]" which has the bracket.
        element_segment = nil
        (segments.length - 2).downto(1) do |i|
          seg = segments[i]
          if /\[/.match?(seg)
            element_segment = seg
            break
          end
        end
        return SourceLocator.locate(value, text, line_map) unless element_segment

        element_match = element_segment.match(/([a-zA-Z0-9_:-]+)\[(\d+)\]/)
        return SourceLocator.locate(value, text, line_map) unless element_match

        element_name = element_match[1]
        target_index = element_match[2].to_i

        # For short values (< 3 chars), enumerate_all is too expensive.
        # Use path-based hierarchy traversal instead.
        if value.length < 3
          return nil # Caller will fall back to locate_via_parent_element
        end

        # Find all occurrences and determine which element each belongs to
        occurrences = SourceLocator.locate_all(value, text, line_map)

        occurrences.each do |occ|
          element_index = count_elements_before_position(text, occ[:char_offset], element_name)
          return occ if element_index == target_index
        end

        # Fallback: return first occurrence
        SourceLocator.locate(value, text, line_map)
      end

      # Fallback location strategy for text_content when locate_at_element_index
      # fails (e.g., the text value is too short to locate reliably).
      # Walks the full element hierarchy from the path to locate the correct
      # parent element, then returns a position inside it.
      #
      # @param path [String] the diff node path (e.g., "/root[0]/item[1]/unknown[0]")
      # @param text [String] the source text
      # @param line_map [Array<Hash>] pre-built line offset map
      # @return [Hash, nil] location hash or nil if not found
      def locate_via_parent_element(path, text, line_map)
        segments = path.split("/").reject(&:empty?)
        return nil if segments.length < 2

        # Collect all element segments with bracket indices, walking backwards
        # from segments[-2] (skip the last segment which is the text node).
        # E.g., for ".../def-item[1]/term[0]/named-content[0]/unknown[0]"
        # we need to traverse: def-item[1] -> term[0] -> named-content[0]
        element_segments = []
        (segments.length - 2).downto(0) do |i|
          seg = segments[i]
          next if seg.start_with?("text()", "comment()", "unknown")

          if /\[/.match?(seg)
            element_segments.unshift(seg) # maintain top-down order
          end
        end
        return nil if element_segments.empty?

        # Walk the hierarchy: find each element within the search range of its parent
        search_start = 0
        search_end = text.length

        element_segments.each do |seg|
          match = seg.match(/([a-zA-Z0-9_:-]+)\[(\d+)\]/)
          return nil unless match

          element_name = match[1]
          target_index = match[2].to_i

          pos = find_nth_element_in_range(text, element_name, target_index,
                                          search_start, search_end)
          return nil unless pos

          # Narrow the search range to inside this element
          close_pos = text.index(">", pos)
          return nil unless close_pos

          search_start = close_pos + 1

          # Find the end of this element (closing tag or self-closing)
          close_tag = "</#{element_name}>"
          end_pos = text.index(close_tag, search_start)
          search_end = if end_pos
                         end_pos
                       else
                         # Self-closing: search range is empty for children
                         search_start
                       end
        end

        # search_start now points inside the innermost element
        line_idx = SourceLocator.send(:find_line_for_offset, search_start, line_map)
        return nil unless line_idx

        col = search_start - line_map[line_idx][:start_offset]
        { char_offset: search_start, line_number: line_idx, col: col }
      end

      # Find the Nth sibling occurrence of an element within a text range,
      # counting only elements at the same depth (direct children).
      #
      # The path indices (e.g., sec[3]) count siblings at the same level.
      # Simply counting all <sec> tags would incorrectly count descendant
      # elements (e.g., a <sec> nested inside another <sec>).
      #
      # This method tracks XML depth: it skips <element> tags inside child
      # elements (depth > 1) and only counts at depth == 1.
      def find_nth_element_in_range(text, element_name, target_index, range_start, range_end)
        offset = range_start
        current_index = 0
        depth = 0
        open_pattern = /<#{Regexp.escape(element_name)}[\s>]/
        close_pattern = /<\/#{Regexp.escape(element_name)}\s*>/

        loop do
          # Find next opening tag at any depth
          open_pos = text.index(open_pattern, offset)
          open_pos = nil if open_pos && open_pos >= range_end

          # Find next closing tag at any depth
          close_pos = text.index(close_pattern, offset)
          close_pos = nil if close_pos && close_pos >= range_end

          # Both exhausted or past range end
          break if open_pos.nil? && close_pos.nil?

          if open_pos && (close_pos.nil? || open_pos <= close_pos)
            tag_end = text.index(">", open_pos)
            break unless tag_end

            if depth == 0
              return open_pos if current_index == target_index

              current_index += 1
            end

            # Check if self-closing
            tag_text = text[open_pos..tag_end]
            unless tag_text.include?("/>")
              depth += 1
            end
            offset = tag_end + 1
          else
            # Closing tag
            close_tag_end = close_pos + 2 # "</x>".length = 2 min chars for ">"
            # Find actual > of closing tag
            actual_close = text.index(">", close_pos)
            close_tag_end = actual_close + 1 if actual_close
            depth -= 1 if depth > 0
            offset = close_tag_end
          end
        end

        nil
      end

      # Locate text using the parsed node tree when path-based lookup fails.
      #
      # This is the most robust fallback: it walks up the node's ancestor chain
      # looking for an element with a unique "id" attribute, then searches for
      # that element in the text. Once found, it locates the target text within
      # the element's content area.
      #
      # @param node [Canon::Xml::Node] the parsed node (TextNode or ElementNode)
      # @param value [String] the text value to locate (e.g., "a")
      # @param text [String] the full source text
      # @param line_map [Array<Hash>] pre-built line offset map
      # @param side [Symbol] :old or :new (which text to search)
      # @return [Hash, nil] location hash {char_offset, line_number, col} or nil
      def locate_via_node_tree(node, value, text, line_map, _side)
        return nil unless node

        # Walk up ancestors to find one with an "id" attribute
        ancestors = []
        current = node
        while current && current.respond_to?(:parent)
          ancestors << current if current.respond_to?(:name)
          current = current.parent
        end

        # Find the nearest ancestor with an "id" attribute
        anchor = nil
        anchor_name = nil
        anchor_id = nil
        ancestors.each do |anc|
          next unless anc.respond_to?(:attribute_nodes) && anc.attribute_nodes

          anc.attribute_nodes.each do |attr|
            next unless attr.respond_to?(:name) && attr.name == "id"

            anchor = anc
            anchor_name = anc.name
            anchor_id = attr.respond_to?(:value) ? attr.value : nil
            break
          end
          break if anchor
        end

        return nil unless anchor && anchor_id

        # Find the anchor element in the text: <anchor_name ... id="anchor_id" ...>
        anchor_pattern = /<#{Regexp.escape(anchor_name)}\b[^>]*\bid="#{Regexp.escape(anchor_id)}"/
        anchor_pos = text.index(anchor_pattern)
        return nil unless anchor_pos

        # Find the end of the opening tag
        anchor_tag_end = text.index(">", anchor_pos)
        return nil unless anchor_tag_end

        # Find the closing tag for the anchor
        close_tag = "</#{anchor_name}>"
        anchor_close = text.index(close_tag, anchor_tag_end + 1)
        return nil unless anchor_close

        # Search for the value within the anchor's content
        # But first, walk down from anchor to find the specific leaf element
        # Build a regex for each ancestor level between anchor and node
        leaf_element = ancestors.first # closest ancestor with a name (the parent of the text node)

        # Find the leaf element's opening tag within the anchor's content
        if leaf_element && leaf_element != anchor
          leaf_name = leaf_element.name
          leaf_attrs = element_attribute_signature(leaf_element)

          # Search for the leaf element within anchor range
          leaf_pattern = /<#{Regexp.escape(leaf_name)}\b/
          leaf_pos = nil
          offset = anchor_tag_end + 1
          while (pos = text.index(leaf_pattern, offset))
            break if pos >= anchor_close

            # Check if this element matches the attribute signature
            tag_end_pos = text.index(">", pos)
            break unless tag_end_pos && tag_end_pos < anchor_close

            tag_text = text[pos..tag_end_pos]
            if leaf_attrs.empty? || leaf_attrs.all? { |k, v| tag_text.include?("#{k}=\"#{v}\"") }
              leaf_pos = pos
              break
            end
            offset = pos + 1
          end

          if leaf_pos
            # Found the leaf element - find the value within it
            leaf_tag_end = text.index(">", leaf_pos)
            leaf_close = text.index("</#{leaf_name}>", leaf_tag_end + 1)

            # Check if leaf is self-closing: if so, the value cannot be inside it
            # in this document (it was moved or removed). Return nil so the caller
            # can fall back to searching in the other document.
            if text[leaf_pos..leaf_tag_end].include?("/>")
              return nil # Self-closing element - value not present in this doc
            end

            if leaf_close && leaf_close < anchor_close
              # Search for value inside leaf element
              value_pos = text.index(value, leaf_tag_end + 1)
              if value_pos && value_pos < leaf_close
                line_idx = SourceLocator.send(:find_line_for_offset, value_pos, line_map)
                return nil unless line_idx

                col = value_pos - line_map[line_idx][:start_offset]
                return { char_offset: value_pos, line_number: line_idx, col: col }
              end
            end
          end
        end

        # Direct search: value might be directly in the anchor's content
        value_pos = text.index(value, anchor_tag_end + 1)
        if value_pos && value_pos < anchor_close
          line_idx = SourceLocator.send(:find_line_for_offset, value_pos, line_map)
          return nil unless line_idx

          col = value_pos - line_map[line_idx][:start_offset]
          return { char_offset: value_pos, line_number: line_idx, col: col }
        end

        nil
      end

      # Locate text using a TextNode's parent element as anchor.
      # Uses the parent element's tag name and attributes to find a unique anchor,
      # then searches within that element for the text value.
      #
      # @param textnode [Canon::Xml::Nodes::TextNode] the TextNode whose parent to use
      # @param value [String] the text value to find
      # @param text [String] the source text to search in
      # @param line_map [Array<Hash>] pre-built line offset map
      # @return [Hash, nil] location hash with :char_offset, :line_number, :col or nil
      def locate_textnode_parent(textnode, value, text, line_map)
        return nil unless textnode.respond_to?(:parent) && textnode.parent

        parent = textnode.parent
        return nil unless parent.respond_to?(:name) && parent.name

        parent_name = parent.name
        parent_attrs = element_attribute_signature(parent)

        # Find all occurrences of the parent element
        anchor_pattern = /<#{Regexp.escape(parent_name)}\b/
        offset = 0

        while (anchor_pos = text.index(anchor_pattern, offset))
          tag_end = text.index(">", anchor_pos)
          break unless tag_end

          # Check if attributes match
          tag_text = text[anchor_pos..tag_end]
          attrs_match = parent_attrs.empty? || parent_attrs.all? do |k, v|
            tag_text.include?("#{k}=\"#{v}\"")
          end

          if attrs_match
            # Found matching parent element - search for value inside it
            anchor_tag_end = tag_end
            anchor_close = text.index("</#{parent_name}>", anchor_tag_end + 1)
            return nil unless anchor_close

            # Search for value within this element
            value_pos = text.index(value, anchor_tag_end + 1)
            if value_pos && value_pos < anchor_close
              line_idx = SourceLocator.send(:find_line_for_offset, value_pos, line_map)
              return nil unless line_idx

              col = value_pos - line_map[line_idx][:start_offset]
              return { char_offset: value_pos, line_number: line_idx, col: col }
            end
          end

          offset = anchor_pos + 1
        end

        nil
      end

      # Locate the same element (parent of a TextNode) in text2, even if empty.
      # Uses the parent element's tag name and attributes to find a matching element.
      # Returns the element's position (for creating zero-length new_ranges).
      #
      # @param textnode [Canon::Xml::Nodes::TextNode] the TextNode whose parent to find
      # @param text [String] the source text (should be text2)
      # @param line_map [Array<Hash>] pre-built line offset map
      # @return [Hash, nil] location hash with :char_offset, :line_number, :col or nil
      def locate_element_in_text2(textnode, text, line_map)
        return nil unless textnode.respond_to?(:parent) && textnode.parent

        parent = textnode.parent
        return nil unless parent.respond_to?(:name) && parent.name

        parent_name = parent.name
        parent_attrs = element_attribute_signature(parent)

        # Find all occurrences of the parent element
        anchor_pattern = /<#{Regexp.escape(parent_name)}\b/
        offset = 0

        while (anchor_pos = text.index(anchor_pattern, offset))
          tag_end = text.index(">", anchor_pos)
          break unless tag_end

          # Check if attributes match
          tag_text = text[anchor_pos..tag_end]
          attrs_match = parent_attrs.empty? || parent_attrs.all? do |k, v|
            tag_text.include?("#{k}=\"#{v}\"")
          end

          if attrs_match
            # Found matching element - return its START position
            # For self-closing elements, return the position of <
            # For regular elements, return the position of >
            is_self_closing = tag_text.include?("/>")

            if is_self_closing
              # Self-closing element - return position of <
              line_idx = SourceLocator.send(:find_line_for_offset, anchor_pos, line_map)
              return nil unless line_idx

              col = anchor_pos - line_map[line_idx][:start_offset]
              return { char_offset: anchor_pos, line_number: line_idx, col: col }
            else
              # Regular element - return position of >
              line_idx = SourceLocator.send(:find_line_for_offset, tag_end_pos, line_map)
              return nil unless line_idx

              col = tag_end_pos - line_map[line_idx][:start_offset]
              return { char_offset: tag_end_pos, line_number: line_idx, col: col }
            end
          end

          offset = anchor_pos + 1
        end

        nil
      end

      # Build a string representation of an element's attributes for matching.
      def element_attribute_signature(element)
        sig = {}
        if element.respond_to?(:attribute_nodes) && element.attribute_nodes
          element.attribute_nodes.each do |attr|
            next unless attr.respond_to?(:name) && attr.respond_to?(:value)

            sig[attr.name] = attr.value
          end
        end
        sig
      end

      # Fallback for short text location when tree-based methods fail.
      # Searches in the original text (text1) for the value and returns the first
      # occurrence. For `before.nil?` cases where the content exists in text1
      # but not at the tree-indicated position in text2.
      #
      # @param value [String] the text to find
      # @param path [String] the diff node path for element context
      # @param text [String] the source text (should be text1/original)
      # @param line_map [Array<Hash>] pre-built line offset map
      # @return [Hash, nil] location hash or nil
      def locate_short_text_in_original(value, _path, text, line_map)
        return nil unless value && !value.empty?

        # For very short strings, just use SourceLocator.locate which finds
        # the first occurrence. This is a best-effort approach.
        loc = SourceLocator.locate(value, text, line_map)
        return loc if loc

        nil
      end

      # Count how many elements of a given name appear before a character position,
      # minus one (since the count includes the element we are inside).
      # Used to determine which element instance an occurrence belongs to.
      #
      # @param text [String] the source text
      # @param char_offset [Integer] character offset to check before
      # @param element_name [String] name of element to count
      # @return [Integer] element index (0-based) of the element containing the position
      def count_elements_before_position(text, char_offset, element_name)
        prefix = text[0...char_offset]
        count = prefix.scan(/<#{element_name}[>\s]/).length
        # Subtract 1 because the count includes the element we are inside
        [count - 1, 0].max
      end
    end
  end
end
