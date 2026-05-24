# frozen_string_literal: true

require_relative "base_formatter"
require_relative "../legend"
require_relative "../../tree_diff/core/xml_entity_decoder"
require "set"
require "strscan"

module Canon
  class DiffFormatter
    module ByLine
      # XML formatter with DOM-guided diffing
      # Uses DOM parsing and element matching for intelligent XML diffs
      class XmlFormatter < BaseFormatter
        # Format DOM-guided XML diff
        #
        # @param doc1 [String] First XML document
        # @param doc2 [String] Second XML document
        # @return [String] Formatted diff
        def format(doc1, doc2)
          compute_line_num_width(doc1, doc2)

          # If we have DiffNodes from comparison, check if there are normative diffs
          # based on show_diffs setting
          if @differences&.any?(Canon::Diff::DiffNode)
            # Check if we should skip based on show_diffs setting
            if should_skip_diff_display?
              return ""
            end

            # Use new pipeline when DiffNodes available
            return format_with_pipeline(doc1, doc2)
          end

          # LEGACY: Fall back to old behavior for backward compatibility
          # This handles formatting-only differences (0 DiffNodes) and legacy Hash entries
          format_legacy(doc1, doc2)
        end

        # Format using new DiffReportBuilder pipeline
        def format_with_pipeline(doc1, doc2)
          # Check if we should show any diffs
          if should_skip_diff_display?
            return ""
          end

          require_relative "../../diff/diff_node_enricher"
          require_relative "../../diff/diff_line_builder"
          require_relative "../../diff/diff_report_builder"

          # Compute line number width BEFORE formatting
          compute_line_num_width(doc1, doc2)

          # Phase 1: Enrich DiffNodes with character positions
          Canon::Diff::DiffNodeEnricher.build(@differences, doc1, doc2)

          # Phase 2: Assemble DiffLines from enriched DiffNodes
          diff_lines = Canon::Diff::DiffLineBuilder.build(@differences, doc1,
                                                          doc2)

          # Layers 3-5: Build report through pipeline
          report = Canon::Diff::DiffReportBuilder.build(
            diff_lines,
            show_diffs: @show_diffs,
            context_lines: @context_lines,
            grouping_lines: @diff_grouping_lines,
          )

          # Layer 6: Format the report
          format_report(report, doc1, doc2)
        end

        # Format a DiffReport for display
        def format_report(report, doc1, doc2)
          return "" if report.contexts.empty?

          lines1 = doc1.split("\n")
          lines2 = doc2.split("\n")

          output = []

          # Detect non-ASCII characters
          all_text = (lines1 + lines2).join
          non_ascii = Legend.detect_non_ascii(all_text, @visualization_map)

          # Add Unicode legend if needed
          unless non_ascii.empty?
            output << Legend.build_legend(non_ascii, use_color: @use_color)
            output << ""
          end

          # Format each context
          report.contexts.each_with_index do |context, idx|
            output << "" if idx.positive?
            output << format_context_from_lines(context, lines1, lines2)
          end

          output.join("\n")
        end

        # Format a context using its DiffLines
        def format_context_from_lines(context, lines1, _lines2)
          output = []

          context.lines.each do |diff_line|
            case diff_line.type
            when :unchanged
              old_num = diff_line.line_number + 1
              new_num = (diff_line.new_position || diff_line.line_number) + 1
              output << format_unified_line(old_num, new_num, " ",
                                            diff_line.content)
            when :removed
              line_num = diff_line.line_number + 1
              formatting = diff_line.formatting?
              informative = diff_line.informative?

              output << if formatting
                          # Formatting-only removal: use theme formatting style
                          format_unified_line(line_num, nil, "[",
                                              diff_line.content,
                                              theme_color(:formatting, :content),
                                              formatting: true)
                        elsif informative
                          # Informative removal: use theme informative style
                          format_unified_line(line_num, nil, "<",
                                              diff_line.content,
                                              theme_color(:informative, :content),
                                              informative: true)
                        elsif diff_line.has_char_ranges?
                          # Use character-level highlighting when char_ranges available.
                          highlighted = render_line_from_char_ranges(
                            diff_line.content, diff_line.char_ranges, :old
                          )
                          old_str = "%#{@line_num_width}d" % line_num
                          blank = " " * @line_num_width
                          if @use_color
                            yellow_old = colorize(old_str,
                                                  structure_color(:line_number) || :yellow)
                            yellow_pipe1 = colorize("|",
                                                    structure_color(:pipe) || :yellow)
                            yellow_pipe2 = colorize("|",
                                                    structure_color(:pipe) || :yellow)
                            red_marker = styled_marker("-", :removed)
                            "#{yellow_old}#{yellow_pipe1}#{blank}#{red_marker} #{yellow_pipe2} #{highlighted}"
                          else
                            "#{old_str}|#{blank}- | #{highlighted}"
                          end
                        else
                          # Normative removal: use theme removed style
                          format_unified_line(line_num, nil, "-",
                                              diff_line.content,
                                              theme_color(:removed, :content))
                        end
            when :added
              line_num = (diff_line.new_position || diff_line.line_number) + 1
              formatting = diff_line.formatting?
              informative = diff_line.informative?

              output << if formatting
                          # Formatting-only addition: use theme formatting style
                          format_unified_line(nil, line_num, "]",
                                              diff_line.content,
                                              theme_color(:formatting, :content),
                                              formatting: true)
                        elsif informative
                          # Informative addition: use theme informative style
                          format_unified_line(nil, line_num, ">",
                                              diff_line.content,
                                              theme_color(:informative, :content),
                                              informative: true)
                        else
                          # Normative addition: use theme added style
                          format_unified_line(nil, line_num, "+",
                                              diff_line.content,
                                              theme_color(:added, :content))
                        end
            when :changed
              output << format_changed_line(diff_line, lines1)
            when :reflow_summary
              # Reflow summary: show collapsed formatting-only reflow
              output << format_reflow_summary(diff_line)
            end
          end

          output.join("\n")
        end

        # Legacy format method (for backward compatibility)
        def format_legacy(doc1, doc2)
          # Check if we should show any diffs based on differences array
          if should_skip_diff_display?
            return ""
          end

          # If documents are equivalent (no normative diffs), do NOT run legacy formatter.
          # The legacy formatter shows ALL differences it finds via LCS on lines,
          # which can be misleading when the comparison found no normative differences.
          # Only run legacy formatter when we have actual DiffNode data to display.
          if @equivalent == true && (@differences.nil? || @differences.empty? ||
             @differences.none?(Canon::Diff::DiffNode))
            return ""
          end

          require_relative "../../xml/data_model"
          require_relative "../../xml/element_matcher"
          require_relative "../../xml/line_range_mapper"

          output = []

          begin
            # Parse to DOM
            root1 = Canon::Xml::DataModel.from_xml(doc1)
            root2 = Canon::Xml::DataModel.from_xml(doc2)

            # Match elements semantically
            matcher = Canon::Xml::ElementMatcher.new
            matches = matcher.match_trees(root1, root2)

            # Build line range maps using ORIGINAL documents
            mapper1 = Canon::Xml::LineRangeMapper.new(indent: 2)
            mapper2 = Canon::Xml::LineRangeMapper.new(indent: 2)
            map1 = mapper1.build_map(root1, doc1)
            map2 = mapper2.build_map(root2, doc2)

            # Use ORIGINAL document lines for display
            lines1 = doc1.split("\n")
            lines2 = doc2.split("\n")

            # Display diffs based on element matches
            output << format_element_matches(matches, map1, map2, lines1,
                                             lines2)
          rescue StandardError => e
            # Fall back to simple diff on error
            output << colorize("Warning: DOM parsing failed, using simple diff",
                               :yellow)
            output << colorize("Error: #{e.class}: #{e.message}", :red)

            # Include relevant backtrace lines
            relevant_trace = e.backtrace.select do |line|
              line.include?("canon")
            end.take(3)
            unless relevant_trace.empty?
              output << colorize("Backtrace:", :yellow)
              relevant_trace.each do |line|
                output << colorize("  #{line}", :yellow)
              end
            end

            output << ""
            require_relative "simple_formatter"
            simple = SimpleFormatter.new(
              use_color: @use_color,
              context_lines: @context_lines,
              diff_grouping_lines: @diff_grouping_lines,
              visualization_map: @visualization_map,
            )
            output << simple.format(doc1, doc2)
          end

          output.join("\n")
        end

        private

        # Format a changed diff line using DiffCharRanges for character-level highlighting.
        # Reads pre-computed char ranges from the DiffLine — NO tokenization, NO LCS.
        def format_changed_line(diff_line, _lines1)
          old_line_num = diff_line.line_number + 1
          new_line_num = (diff_line.new_position || diff_line.line_number) + 1
          formatting = diff_line.formatting?
          informative = diff_line.informative?
          old_content = diff_line.old_content || diff_line.content
          new_content = diff_line.new_content || diff_line.content

          if formatting
            # For formatting-only changes, marker goes on NEW side:
            # - If new_content has MORE whitespace than old_content: formatting ADDED → ]
            # - If new_content has LESS whitespace than old_content: formatting REMOVED → [
            marker = new_content.length > old_content.length ? "]" : "["
            [
              # OLD line: no marker (formatting was on NEW side)
              # Apply visualization so spaces show as ░
              format_unified_line(old_line_num, nil, " ",
                                  apply_visualization(old_content)),
              # NEW line: marker on NEW side indicating what changed
              format_unified_line(nil, new_line_num, marker, new_content,
                                  theme_color(:formatting, :content), formatting: true),
            ].join("\n")
          elsif informative
            [
              format_unified_line(old_line_num, nil, "<", old_content,
                                  theme_color(:informative, :content_old), informative: true),
              format_unified_line(nil, new_line_num, ">", new_content,
                                  theme_color(:informative, :content_new), informative: true),
            ].join("\n")
          elsif diff_line.has_char_ranges?
            # Check if this is a mixed change (both old and new have changed content
            # AND both have multiple ranges indicating partial deletion/insertion)
            old_ranges = diff_line.char_ranges
            new_ranges = diff_line.new_char_ranges
            has_old_change = old_ranges.any? { |cr| cr.status == :changed_old }
            has_new_change = new_ranges.any? { |cr| cr.status == :changed_new }

            # Mixed change: both sides have changed content AND there are
            # MULTIPLE separate changed regions (not just prefix+change+suffix).
            # Count contiguous changed regions — a simple word replacement has
            # ONE changed region even though it produces 3 ranges (prefix+change+suffix).
            old_changed_regions = count_changed_regions(old_ranges,
                                                        :changed_old)
            new_changed_regions = count_changed_regions(new_ranges,
                                                        :changed_new)
            is_mixed = has_old_change && has_new_change &&
              (old_changed_regions > 1 || new_changed_regions > 1)

            # Always compute highlighted versions when we have char_ranges
            old_highlighted = render_line_from_char_ranges(
              old_content, diff_line.char_ranges, :old
            )
            new_highlighted = render_line_from_char_ranges(
              new_content, diff_line.new_char_ranges, :new
            )

            if is_mixed
              # Mixed change: use * marker
              format_mixed_changed_line(old_line_num, new_line_num,
                                        diff_line.char_ranges, diff_line.new_char_ranges,
                                        old_content, new_content)
            elsif @diff_mode == :inline
              # Inline mode for token changes: show OLD → NEW on same line
              format_token_diff_line_inline(old_line_num, new_line_num,
                                            old_highlighted, new_highlighted)
            else
              # Separate mode: show OLD and NEW on different lines
              format_token_diff_line(old_line_num, new_line_num, old_highlighted,
                                     new_highlighted)
            end
          elsif @diff_mode == :inline
            # Inline mode: show OLD → NEW on same line
            separator = " → "
            marker = if @use_color
                       colorize("*",
                                theme_color(:changed, :marker))
                     else
                       "*"
                     end
            [
              format_unified_line(old_line_num, new_line_num, marker,
                                  "#{old_content}#{separator}#{new_content}",
                                  theme_color(:changed, :content)),
            ].join("\n")
          else
            # Fallback: whole-line highlighting (no char ranges available)
            [
              format_unified_line(old_line_num, nil, "-", old_content,
                                  theme_color(:removed, :content)),
              format_unified_line(nil, new_line_num, "+", new_content,
                                  theme_color(:added, :content)),
            ].join("\n")
          end
        end

        # Render a line from its DiffCharRanges — walks each range and applies
        # the appropriate color. This is the Phase 2 renderer: NO computation,
        # just reads pre-computed ranges and applies visualization + color.
        #
        # @param line_text [String] the full line text
        # @param ranges [Array<DiffCharRange>] character ranges for this line
        # @param side [Symbol] :old or :new
        # @return [String] rendered text with colors/visualization applied
        def render_line_from_char_ranges(line_text, ranges, side)
          return apply_visualization(line_text) if ranges.nil? || ranges.empty?

          parts = []
          cursor = 0

          ranges.each do |cr|
            # Fill in any gap before this range as unchanged text
            if cursor < cr.start_col
              gap = line_text[cursor...cr.start_col]
              decoded_gap = Canon::TreeDiff::Core::XmlEntityDecoder.decode_xml_entities(gap)
              parts << apply_visualization(decoded_gap)
            end

            segment = cr.extract_from(line_text)
            next if segment.nil? || segment.empty?

            # Decode XML entities so visualization can handle actual characters
            # (e.g., &#xA0; -> NBSP -> visualized as ␣)
            decoded_segment = Canon::TreeDiff::Core::XmlEntityDecoder.decode_xml_entities(segment)

            parts << if cr.diff_node&.informative?
                       # Informative change: use theme informative colors
                       informative_old = theme_color(:informative, :content_old)
                       informative_new = theme_color(:informative, :content_new)
                       case cr.status
                       when :unchanged
                         apply_visualization(decoded_segment)
                       when :changed_old
                         (if side == :old
                            apply_visualization(decoded_segment,
                                                informative_old)
                          else
                            apply_visualization(decoded_segment)
                          end)
                       when :changed_new
                         (if side == :new
                            apply_visualization(decoded_segment,
                                                informative_new)
                          else
                            apply_visualization(decoded_segment)
                          end)
                       when :removed
                         apply_visualization(decoded_segment, informative_old)
                       when :added
                         apply_visualization(decoded_segment, informative_new)
                       else
                         apply_visualization(decoded_segment)
                       end
                     else
                       # Normative change: use theme removed/added colors
                       removed_color = theme_color(:removed, :content)
                       added_color = theme_color(:added, :content)
                       case cr.status
                       when :unchanged
                         apply_visualization(decoded_segment)
                       when :changed_old
                         (if side == :old
                            apply_visualization(decoded_segment,
                                                removed_color)
                          else
                            apply_visualization(decoded_segment)
                          end)
                       when :changed_new
                         (if side == :new
                            apply_visualization(decoded_segment,
                                                added_color)
                          else
                            apply_visualization(decoded_segment)
                          end)
                       when :removed
                         apply_visualization(decoded_segment, removed_color)
                       when :added
                         apply_visualization(decoded_segment, added_color)
                       else
                         apply_visualization(decoded_segment)
                       end
                     end

            cursor = cr.end_col
          end

          # Fill in any remaining text after the last range
          if cursor < line_text.length
            tail = line_text[cursor..]
            decoded_tail = Canon::TreeDiff::Core::XmlEntityDecoder.decode_xml_entities(tail)
            parts << apply_visualization(decoded_tail)
          end

          parts.join
        end

        # Format token diff where old content spans multiple lines.
        # Each old line is shown separately with its own line number,
        # and the new (single-line) content is shown once.
        def format_multi_line_token_diff(old_start_num, new_num, old_highlighted,
                                          new_highlighted)
          output = []
          fmt = "%#{@line_num_width}d"
          blank = " " * @line_num_width
          line_num_color = structure_color(:line_number) || :yellow
          pipe_color = structure_color(:pipe) || :yellow
          removed_marker_color = theme_color(:removed, :marker)
          added_marker_color = theme_color(:added, :marker)

          # Split old highlighted content by newlines and show each line
          old_lines = old_highlighted.split("\n")
          old_lines.each_with_index do |line, idx|
            line_num = old_start_num + idx
            if @use_color
              yellow_old = colorize(fmt % line_num, line_num_color)
              yellow_pipe1 = colorize("|", pipe_color)
              red_marker = colorize("-", removed_marker_color)
              yellow_pipe2 = colorize("|", pipe_color)
              output << "#{yellow_old}#{yellow_pipe1}#{blank}#{red_marker} #{yellow_pipe2} #{line}"
            else
              output << "#{fmt % line_num}|#{blank}- | #{line}"
            end
          end

          # Show new content once
          if @use_color
            yellow_pipe1 = colorize("|", pipe_color)
            yellow_new = colorize(fmt % new_num, line_num_color)
            green_marker = colorize("+", added_marker_color)
            yellow_pipe2 = colorize("|", pipe_color)
            output << "#{blank}#{yellow_pipe1}#{yellow_new}#{green_marker} #{yellow_pipe2} #{new_highlighted}"
          else
            output << "#{blank}|#{fmt % new_num}+ | #{new_highlighted}"
          end

          output.join("\n")
        end

        # Format element matches for display
        def format_element_matches(matches, map1, map2, lines1, lines2)
          output = []

          # Detect non-ASCII characters in the diff
          all_text = (lines1 + lines2).join
          non_ascii = Legend.detect_non_ascii(all_text, @visualization_map)

          # Add Unicode legend if any non-ASCII characters detected
          unless non_ascii.empty?
            output << Legend.build_legend(non_ascii, use_color: @use_color)
            output << ""
          end

          # Build a set of elements to skip (children of parents showing diffs)
          elements_to_skip = build_skip_set(matches, map1, map2, lines1,
                                            lines2)

          # Build a set of children of matched parents
          children_of_matched_parents = build_children_set(matches)

          # Collect diff sections with metadata
          diff_sections = collect_diff_sections(matches, map1, map2, lines1,
                                                lines2, elements_to_skip,
                                                children_of_matched_parents)

          # Sort by line number
          diff_sections.sort_by! do |section|
            section[:start_line1] || section[:start_line2] || 0
          end

          # Group diffs by proximity if diff_grouping_lines is set
          formatted_diffs = if @diff_grouping_lines
                              groups = group_diff_sections(diff_sections,
                                                           @diff_grouping_lines)
                              format_diff_groups(groups)
                            else
                              diff_sections.filter_map do |s|
                                s[:formatted]
                              end.join("\n\n")
                            end

          output << formatted_diffs
          output.join("\n")
        end

        # Collect diff sections with metadata
        def collect_diff_sections(matches, map1, map2, lines1, lines2,
                                   elements_to_skip, children_of_matched_parents)
          diff_sections = []

          # If there are NO semantic diffs, don't show any matched elements
          elements_with_semantic_diffs = build_elements_with_semantic_diffs_set

          matches.each do |match|
            case match.status
            when :matched
              next if elements_to_skip.include?(match.elem1)

              # Only apply semantic filtering if we have DiffNode objects
              # (when called standalone or without DiffNodes, show all diffs)
              if @differences.any?(Canon::Diff::DiffNode)
                # Skip if no semantic diffs exist (all diffs were normalized)
                next if elements_with_semantic_diffs.empty?

                # Skip if this element has no semantic diffs in its subtree
                next unless has_semantic_diff_in_subtree?(match.elem1,
                                                          elements_with_semantic_diffs)
              end

              section = format_matched_element_with_metadata(match, map1,
                                                             map2, lines1,
                                                             lines2)
              diff_sections << section if section
            when :deleted
              next if children_of_matched_parents.include?(match.elem1)

              section = format_deleted_element_with_metadata(match, map1,
                                                             lines1)
              diff_sections << section if section
            when :inserted
              next if children_of_matched_parents.include?(match.elem2)

              section = format_inserted_element_with_metadata(match, map2,
                                                              lines2)
              diff_sections << section if section
            end
          end

          diff_sections
        end

        # Build set of elements to skip (children with parents showing diffs)
        def build_skip_set(matches, map1, map2, lines1, lines2)
          elements_to_skip = Set.new
          elements_with_diffs = Set.new

          # Build set of element pairs that have semantic diffs
          build_elements_with_semantic_diffs_set

          # First pass: identify elements with line differences
          # (semantic filtering happens in collect_diff_sections)
          matches.each do |match|
            next unless match.status == :matched

            range1 = map1[match.elem1]
            range2 = map2[match.elem2]
            next unless range1 && range2

            elem_lines1 = lines1[range1.start_line..range1.end_line]
            elem_lines2 = lines2[range2.start_line..range2.end_line]

            # Add if there are line diffs
            # Semantic filtering is done in collect_diff_sections
            if elem_lines1 != elem_lines2
              elements_with_diffs.add(match.elem1)
            end
          end

          # Second pass: skip children of elements with diffs
          elements_with_diffs.each do |elem|
            if elem.respond_to?(:parent)
              current = elem.parent
              while current
                if current.respond_to?(:name) && elements_with_diffs.include?(current)
                  elements_to_skip.add(elem)
                  break
                end
                current = current.respond_to?(:parent) ? current.parent : nil
              end
            end
          end

          elements_to_skip
        end

        # Format a matched element showing differences
        def format_matched_element(match, map1, map2, lines1, lines2)
          range1 = map1[match.elem1]
          range2 = map2[match.elem2]
          return nil unless range1 && range2

          # Extract line ranges
          elem_lines1 = lines1[range1.start_line..range1.end_line]
          elem_lines2 = lines2[range2.start_line..range2.end_line]

          # Skip if identical
          return nil if elem_lines1 == elem_lines2

          # Run line diff
          diffs = ::Diff::LCS.sdiff(elem_lines1, elem_lines2)

          # Identify diff blocks
          diff_blocks = identify_diff_blocks(diffs)
          return nil if diff_blocks.empty?

          # Group into contexts
          contexts = group_diff_blocks_into_contexts(diff_blocks,
                                                     @diff_grouping_lines || 0)

          # Expand with context lines
          expanded_contexts = expand_contexts_with_context_lines(contexts,
                                                                 @context_lines,
                                                                 diffs.length)

          # Format contexts
          output = []
          expanded_contexts.each_with_index do |context, idx|
            output << "" if idx.positive?
            output << format_context(context, diffs, range1.start_line,
                                     range2.start_line)
          end

          output.join("\n")
        end

        # Format a deleted element
        def format_deleted_element(match, map1, lines1)
          range1 = map1[match.elem1]
          return nil unless range1

          output = []
          path_str = match.path.join("/")
          removed_marker_color = theme_color(:removed, :marker)
          removed_content_color = theme_color(:removed, :content)
          output << colorize("Element: #{path_str} [DELETED]",
                             removed_marker_color, :bold)

          # Show all lines as deleted
          (range1.start_line..range1.end_line).each do |i|
            output << format_unified_line(i + 1, nil, "-", lines1[i],
                                          removed_content_color)
          end

          output.join("\n")
        end

        # Format an inserted element
        def format_inserted_element(match, map2, lines2)
          range2 = map2[match.elem2]
          return nil unless range2

          output = []
          path_str = match.path.join("/")
          added_marker_color = theme_color(:added, :marker)
          added_content_color = theme_color(:added, :content)
          output << colorize("Element: #{path_str} [INSERTED]",
                             added_marker_color, :bold)

          # Show all lines as inserted
          (range2.start_line..range2.end_line).each do |i|
            output << format_unified_line(nil, i + 1, "+", lines2[i],
                                          added_content_color)
          end

          output.join("\n")
        end

        # Identify contiguous diff blocks
        def identify_diff_blocks(diffs)
          require_relative "../../diff/diff_block"

          blocks = []
          current_start = nil
          current_types = []

          diffs.each_with_index do |change, idx|
            if change.action != "="
              if current_start.nil?
                current_start = idx
                current_types = [change.action]
              else
                current_types << change.action unless current_types.include?(change.action)
              end
            elsif current_start
              blocks << Canon::Diff::DiffBlock.new(
                start_idx: current_start,
                end_idx: idx - 1,
                types: current_types,
              )
              current_start = nil
              current_types = []
            end
          end

          # Don't forget the last block
          if current_start
            blocks << Canon::Diff::DiffBlock.new(
              start_idx: current_start,
              end_idx: diffs.length - 1,
              types: current_types,
            )
          end

          blocks
        end

        # Group diff blocks into contexts
        def group_diff_blocks_into_contexts(blocks, grouping_lines)
          return [] if blocks.empty?

          contexts = []
          current_context = [blocks[0]]

          blocks[1..].each do |block|
            last_block = current_context.last
            gap = block.start_idx - last_block.end_idx - 1

            if gap <= grouping_lines
              current_context << block
            else
              contexts << current_context
              current_context = [block]
            end
          end

          contexts << current_context unless current_context.empty?
          contexts
        end

        # Expand contexts with context lines
        def expand_contexts_with_context_lines(contexts, context_lines,
                                                total_lines)
          require_relative "../../diff/diff_context"

          contexts.map do |context|
            first_block = context.first
            last_block = context.last

            start_idx = [first_block.start_idx - context_lines, 0].max
            end_idx = [last_block.end_idx + context_lines, total_lines - 1].min

            Canon::Diff::DiffContext.new(
              start_idx: start_idx,
              end_idx: end_idx,
              blocks: context,
            )
          end
        end

        # Format a context
        def format_context(context, diffs, base_line1, base_line2)
          require_relative "../../diff/formatting_detector"

          # Pre-compute block-level formatting for multi-line changes
          formatting_indices = detect_block_formatting(context, diffs)

          output = []

          (context.start_idx..context.end_idx).each do |idx|
            change = diffs[idx]

            line1 = change.old_position ? base_line1 + change.old_position + 1 : nil
            line2 = change.new_position ? base_line2 + change.new_position + 1 : nil

            is_formatting = formatting_indices.include?(idx)

            case change.action
            when "="
              output << format_unified_line(line1, line2, " ",
                                            change.old_element)
            when "-"
              output << if is_formatting
                          format_unified_line(line1, nil, "[",
                                              change.old_element,
                                              theme_color(:formatting, :content),
                                              formatting: true)
                        else
                          format_unified_line(line1, nil, "-",
                                              change.old_element,
                                              theme_color(:removed, :content))
                        end
            when "+"
              output << if is_formatting
                          format_unified_line(nil, line2, "]",
                                              change.new_element,
                                              theme_color(:formatting, :content),
                                              formatting: true)
                        else
                          format_unified_line(nil, line2, "+",
                                              change.new_element,
                                              theme_color(:added, :content))
                        end
            when "!"
              if is_formatting
                output << format_unified_line(line1, nil, "[",
                                              change.old_element,
                                              theme_color(:formatting, :content),
                                              formatting: true)
                output << format_unified_line(nil, line2, "]",
                                              change.new_element,
                                              theme_color(:formatting, :content),
                                              formatting: true)
              else
                # Token-level highlighting
                old_tokens = tokenize_xml(change.old_element)
                new_tokens = tokenize_xml(change.new_element)
                token_diffs = ::Diff::LCS.sdiff(old_tokens, new_tokens)

                old_highlighted = build_token_highlighted_text(token_diffs,
                                                               :old)
                new_highlighted = build_token_highlighted_text(token_diffs,
                                                               :new)

                output << format_token_diff_line(line1, line2, old_highlighted,
                                                 new_highlighted)
              end
            end
          end

          output.join("\n")
        end

        # Format a unified diff line
        # Format a reflow summary line (collapsed formatting-only reflow)
        def format_reflow_summary(diff_line)
          old_str = " " * @line_num_width
          new_str = " " * @line_num_width
          content = diff_line.content

          if @use_color
            "#{old_str}|#{new_str} | #{colorize(content, :yellow)}"
          else
            "#{old_str}|#{new_str} | #{content}"
          end
        end

        def format_unified_line(old_num, new_num, marker, content, color = nil,
informative: false, formatting: false)
          old_str = old_num ? "%#{@line_num_width}d" % old_num : " " * @line_num_width
          new_str = new_num ? "%#{@line_num_width}d" % new_num : " " * @line_num_width
          marker_part = "#{marker} "

          visualized_content = if color
                                 apply_visualization(content,
                                                     color)
                               else
                                 content
                               end

          if @use_color
            line_num_color = structure_color(:line_number) || :yellow
            pipe_color = structure_color(:pipe) || :yellow
            yellow_old = colorize(old_str, line_num_color)
            yellow_pipe1 = colorize("|", pipe_color)
            yellow_new = colorize(new_str, line_num_color)
            yellow_pipe2 = colorize("|", pipe_color)

            if color
              colored_marker = colorize(marker, color)
              "#{yellow_old}#{yellow_pipe1}#{yellow_new}#{colored_marker} #{yellow_pipe2} #{visualized_content}"
            else
              "#{yellow_old}#{yellow_pipe1}#{yellow_new}#{marker} #{yellow_pipe2} #{visualized_content}"
            end
          else
            "#{old_str}|#{new_str}#{marker_part}| #{visualized_content}"
          end
        end

        # Format mixed changed line where both old and new have changed content.
        # Uses * marker on BOTH lines to indicate mixed deletion/insertion.
        # Supports :inline mode (both on same line) and :separate mode (two lines).
        def format_mixed_changed_line(old_line_num, new_line_num,
                                     char_ranges, new_char_ranges,
                                     old_content, new_content)
          fmt = "%#{@line_num_width}d"
          blank = " " * @line_num_width

          if @diff_mode == :inline
            format_mixed_changed_line_inline(old_line_num, new_line_num,
                                             char_ranges, new_char_ranges,
                                             old_content, new_content, fmt, blank)
          else
            format_mixed_changed_line_separate(old_line_num, new_line_num,
                                               char_ranges, new_char_ranges,
                                               old_content, new_content, fmt, blank)
          end
        end

        # Separate-line format for mixed changes: * on BOTH OLD and NEW lines
        def format_mixed_changed_line_separate(old_line_num, new_line_num,
                                               char_ranges, new_char_ranges,
                                               old_content, new_content, fmt, blank)
          output = []
          old_highlighted = render_line_from_char_ranges(old_content,
                                                         char_ranges, :old)
          new_highlighted = render_line_from_char_ranges(new_content,
                                                         new_char_ranges, :new)
          line_num_color = structure_color(:line_number) || :yellow
          pipe_color = structure_color(:pipe) || :yellow
          changed_marker_color = theme_color(:changed, :marker)

          if @use_color
            yellow_old = colorize(fmt % old_line_num, line_num_color)
            yellow_pipe1 = colorize("|", pipe_color)
            yellow_new = colorize(fmt % new_line_num, line_num_color)
            yellow_pipe2 = colorize("|", pipe_color)
            mixed_marker = colorize("*", changed_marker_color)

            # OLD line: show line number with * marker
            output << "#{yellow_old}#{yellow_pipe1}#{blank}#{mixed_marker} #{yellow_pipe2} #{old_highlighted}"
            # NEW line: show line number with * marker
            output << "#{blank}#{yellow_pipe1}#{yellow_new}#{mixed_marker} #{yellow_pipe2} #{new_highlighted}"
          else
            # OLD line: show line number with * marker
            output << "#{fmt % old_line_num}|#{blank}* | #{old_highlighted}"
            # NEW line: show line number with * marker
            output << "#{blank}|#{fmt % new_line_num}* | #{new_highlighted}"
          end

          output.join("\n")
        end

        # Inline format for mixed changes: OLD and NEW on same line
        # Shows: OLD line with removed parts in red/strikethrough, NEW line with added parts in green/underline
        def format_mixed_changed_line_inline(old_line_num, new_line_num,
                                             char_ranges, new_char_ranges,
                                             old_content, new_content, fmt, _blank)
          old_highlighted = render_line_for_inline(old_content, char_ranges,
                                                   :old)
          new_highlighted = render_line_for_inline(new_content,
                                                   new_char_ranges, :new)

          line_num_color = structure_color(:line_number) || :yellow
          pipe_color = structure_color(:pipe) || :yellow
          changed_marker_color = theme_color(:changed, :marker)
          separator_color = theme_color(:informative, :content) || :cyan

          # Separator between OLD and NEW content in inline mode
          separator = @use_color ? colorize(" → ", separator_color) : " → "

          if @use_color
            yellow_old = colorize(fmt % old_line_num, line_num_color)
            yellow_pipe1 = colorize("|", pipe_color)
            yellow_new = colorize(fmt % new_line_num, line_num_color)
            yellow_pipe2 = colorize("|", pipe_color)
            mixed_marker = colorize("*", changed_marker_color)

            "#{yellow_old}#{yellow_pipe1}#{yellow_new}#{mixed_marker} #{yellow_pipe2} #{old_highlighted}#{separator}#{new_highlighted}"
          else
            "#{fmt % old_line_num}|#{fmt % new_line_num}*| #{old_highlighted}#{separator}#{new_highlighted}"
          end
        end

        # Render a line segment for inline mode with proper styling
        # Uses red for removed (changed_old), green for added (changed_new)
        # Falls back to strikethrough/underline when color is off
        def render_line_for_inline(line_text, ranges, _side)
          return apply_visualization(line_text) if ranges.nil? || ranges.empty?

          parts = []
          cursor = 0
          removed_color = theme_color(:removed, :content)
          added_color = theme_color(:added, :content)

          ranges.each do |cr|
            # Fill in any gap before this range as unchanged text
            if cursor < cr.start_col
              gap = line_text[cursor...cr.start_col]
              decoded_gap = Canon::TreeDiff::Core::XmlEntityDecoder.decode_xml_entities(gap)
              parts << apply_visualization(decoded_gap)
            end

            segment = cr.extract_from(line_text)
            next if segment.nil? || segment.empty?

            decoded_segment = Canon::TreeDiff::Core::XmlEntityDecoder.decode_xml_entities(segment)

            parts << case cr.status
                     when :unchanged
                       apply_visualization(decoded_segment)
                     when :changed_old
                       apply_effect(decoded_segment, :strikethrough,
                                    removed_color)
                     when :changed_new
                       apply_effect(decoded_segment, :underline, added_color)
                     when :removed
                       apply_effect(decoded_segment, :strikethrough,
                                    removed_color)
                     when :added
                       apply_effect(decoded_segment, :underline, added_color)
                     else
                       apply_visualization(decoded_segment)
                     end

            cursor = cr.end_col
          end

          # Fill in any remaining text after the last range
          if cursor < line_text.length
            tail = line_text[cursor..]
            decoded_tail = Canon::TreeDiff::Core::XmlEntityDecoder.decode_xml_entities(tail)
            parts << apply_visualization(decoded_tail)
          end

          parts.join
        end

        # Format token diff lines
        def format_token_diff_line(old_line, new_line, old_highlighted,
                                    new_highlighted)
          output = []
          fmt = "%#{@line_num_width}d"
          blank = " " * @line_num_width
          line_num_color = structure_color(:line_number) || :yellow
          pipe_color = structure_color(:pipe) || :yellow
          removed_marker_color = theme_color(:removed, :marker)
          added_marker_color = theme_color(:added, :marker)

          if @use_color
            yellow_old = colorize(fmt % old_line, line_num_color)
            yellow_pipe1 = colorize("|", pipe_color)
            yellow_new = colorize(fmt % new_line, line_num_color)
            yellow_pipe2 = colorize("|", pipe_color)
            red_marker = colorize("-", removed_marker_color)
            green_marker = colorize("+", added_marker_color)

            output << "#{yellow_old}#{yellow_pipe1}#{blank}#{red_marker} #{yellow_pipe2} #{old_highlighted}"
            output << "#{blank}#{yellow_pipe1}#{yellow_new}#{green_marker} #{yellow_pipe2} #{new_highlighted}"
          else
            output << "#{fmt % old_line}|#{blank}- | #{old_highlighted}"
            output << "#{blank}|#{fmt % new_line}+ | #{new_highlighted}"
          end

          output.join("\n")
        end

        # Inline format for token diff lines: OLD → NEW on same line
        def format_token_diff_line_inline(old_line, new_line, old_highlighted,
                                         new_highlighted)
          fmt = "%#{@line_num_width}d"
          line_num_color = structure_color(:line_number) || :yellow
          pipe_color = structure_color(:pipe) || :yellow
          changed_marker_color = theme_color(:changed, :marker)
          separator_color = theme_color(:informative, :content) || :cyan

          separator = @use_color ? colorize(" → ", separator_color) : " → "

          if @use_color
            yellow_old = colorize(fmt % old_line, line_num_color)
            yellow_pipe = colorize("|", pipe_color)
            yellow_new = colorize(fmt % new_line, line_num_color)
            mixed_marker = colorize("*", changed_marker_color)

            "#{yellow_old}#{yellow_pipe}#{yellow_new}#{mixed_marker} #{yellow_pipe} #{old_highlighted}#{separator}#{new_highlighted}"
          else
            "#{fmt % old_line}|#{fmt % new_line}*| #{old_highlighted}#{separator}#{new_highlighted}"
          end
        end

        # Tokenize XML line
        def tokenize_xml(line)
          tokens = []
          scanner = StringScanner.new(line)

          until scanner.eos?
            tokens << if scanner.scan(/\s+/)
                        scanner.matched
                      elsif scanner.scan(/<\/?[\w:-]+/)
                        scanner.matched
                      elsif scanner.scan(/[\w:-]+="[^"]*"/)
                        scanner.matched
                      elsif scanner.scan(/[\w:-]+='[^']*'/)
                        scanner.matched
                      elsif scanner.scan(/[\w:-]+=/)
                        scanner.matched
                      elsif scanner.scan(/\/?>/)
                        scanner.matched
                      elsif scanner.scan(/[^<>\s]+/)
                        scanner.matched
                      else
                        scanner.getch
                      end
          end

          tokens
        end

        # Build highlighted text from token diff
        def build_token_highlighted_text(token_diffs, side)
          parts = []
          removed_color = theme_color(:removed, :content)
          added_color = theme_color(:added, :content)

          token_diffs.each do |change|
            case change.action
            when "="
              element = change.old_element || ""
              visual = element.to_s.chars.map do |char|
                @visualization_map.fetch(char, char)
              end.join

              parts << if @use_color
                         colorize(visual, :default)
                       else
                         visual
                       end
            when "-"
              if side == :old
                parts << apply_visualization(change.old_element, removed_color)
              end
            when "+"
              if side == :new
                parts << apply_visualization(change.new_element, added_color)
              end
            when "!"
              parts << if side == :old
                         apply_visualization(change.old_element, removed_color)
                       else
                         apply_visualization(change.new_element, added_color)
                       end
            end
          end

          parts.join
        end

        # Apply character visualization with optional effect (strikethrough/underline)
        #
        # @param token [String] The token to apply visualization to
        # @param effect [Symbol, nil] Effect to apply (:strikethrough or :underline)
        # @param color [Symbol, nil] Color to apply (:red, :green, :white, etc.)
        # @return [String] Visualized and optionally colored/effect text
        def apply_effect(token, effect = nil, color = nil)
          return "" if token.nil?

          visual = token.to_s.chars.map do |char|
            @visualization_map.fetch(char, char)
          end.join

          # In legacy mode, no effects at all
          if @legacy_terminal
            return visual
          end

          if @use_color
            require "rainbow"
            rainbow = Rainbow.new
            rainbow.enabled = true
            presenter = rainbow.wrap(visual)

            # Apply effect if specified (map :strikethrough to :cross_out for Rainbow)
            if effect
              rainbow_effect = effect == :strikethrough ? :cross_out : effect
              presenter = presenter.public_send(rainbow_effect)
            end

            # Apply color if specified
            presenter = presenter.public_send(color) if color

            presenter.to_s
          else
            visual
          end
        end

        def detect_block_formatting(context, diffs)
          formatting_indices = Set.new
          blocks = []
          current_block = nil

          (context.start_idx..context.end_idx).each do |idx|
            change = diffs[idx]
            if change.action == "="
              if current_block
                blocks << current_block
                current_block = nil
              end
              next
            end

            current_block ||=
              { indices: [], old_parts: [], new_parts: [] }
            current_block[:indices] << idx

            case change.action
            when "-", "!"
              current_block[:old_parts] << change.old_element
            end
            case change.action
            when "+", "!"
              current_block[:new_parts] << change.new_element
            end
          end
          blocks << current_block if current_block

          fd = Canon::Diff::FormattingDetector

          blocks.each do |block|
            next if block[:old_parts].empty? || block[:new_parts].empty?

            if fd.formatting_block?(block[:old_parts], block[:new_parts])
              block[:indices].each { |i| formatting_indices.add(i) }
              next
            end

            match = fd.formatting_prefix(block[:old_parts], block[:new_parts])
            next unless match

            # Mark the prefix entries
            old_marked = 0
            new_marked = 0
            block[:indices].each do |i|
              action = diffs[i].action
              case action
              when "-"
                if old_marked < match[:old_end]
                  formatting_indices.add(i)
                  old_marked += 1
                end
              when "+"
                if new_marked < match[:new_end]
                  formatting_indices.add(i)
                  new_marked += 1
                end
              when "!"
                if old_marked < match[:old_end]
                  formatting_indices.add(i)
                  old_marked += 1
                end
                if new_marked < match[:new_end]
                  formatting_indices.add(i)
                  new_marked += 1
                end
              end
            end
          end

          formatting_indices
        end

        # Count the number of separate contiguous changed regions in a range list.
        # A simple word replacement like "John Doe" → "Jane Doe" produces
        # 3 ranges (unchanged prefix + changed + unchanged suffix) but only
        # ONE changed region. Only multiple separate changed regions count as mixed.
        #
        # @param ranges [Array<DiffCharRange>]
        # @param changed_status [Symbol] :changed_old or :changed_new
        # @return [Integer] number of separate changed regions
        def count_changed_regions(ranges, changed_status)
          count = 0
          in_changed = false
          ranges.each do |cr|
            if cr.status == changed_status
              count += 1 unless in_changed
              in_changed = true
            else
              in_changed = false
            end
          end
          count
        end
      end
    end
  end
end
