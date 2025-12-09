# frozen_string_literal: true

require_relative "base_formatter"
require_relative "../legend"
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
          # This happens when @differences is nil (no comparison result provided)
          format_legacy(doc1, doc2)
        end

        # Format using new DiffReportBuilder pipeline
        def format_with_pipeline(doc1, doc2)
          # Check if we should show any diffs
          if should_skip_diff_display?
            return ""
          end

          require_relative "../../diff/diff_node_mapper"
          require_relative "../../diff/diff_report_builder"

          # Layer 2: Map DiffNodes to DiffLines
          diff_lines = Canon::Diff::DiffNodeMapper.map(@differences, doc1, doc2)

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
              line_num = diff_line.line_number + 1
              output << format_unified_line(line_num, line_num, " ",
                                            diff_line.content)
            when :removed
              line_num = diff_line.line_number + 1
              formatting = diff_line.formatting?
              informative = diff_line.informative?

              output << if formatting
                          # Formatting-only removal: [ marker in dark gray
                          format_unified_line(line_num, nil, "[",
                                              diff_line.content,
                                              :black,
                                              formatting: true)
                        elsif informative
                          # Informative removal: < marker in blue
                          format_unified_line(line_num, nil, "<",
                                              diff_line.content,
                                              :blue,
                                              informative: true)
                        else
                          # Normative removal: - marker in red
                          format_unified_line(line_num, nil, "-",
                                              diff_line.content,
                                              :red)
                        end
            when :added
              line_num = diff_line.line_number + 1
              formatting = diff_line.formatting?
              informative = diff_line.informative?

              output << if formatting
                          # Formatting-only addition: ] marker in light gray
                          format_unified_line(nil, line_num, "]",
                                              diff_line.content,
                                              :white,
                                              formatting: true)
                        elsif informative
                          # Informative addition: > marker in cyan
                          format_unified_line(nil, line_num, ">",
                                              diff_line.content,
                                              :cyan,
                                              informative: true)
                        else
                          # Normative addition: + marker in green
                          format_unified_line(nil, line_num, "+",
                                              diff_line.content,
                                              :green)
                        end
            when :changed
              line_num = diff_line.line_number + 1
              formatting = diff_line.formatting?
              informative = diff_line.informative?
              # For changed lines, we need both old and new content
              # For now, show as removed + added
              old_content = lines1[diff_line.line_number]
              new_content = diff_line.content

              if formatting
                output << format_unified_line(line_num, nil, "[",
                                              old_content,
                                              :black,
                                              formatting: true)
                output << format_unified_line(nil, line_num, "]",
                                              new_content,
                                              :white,
                                              formatting: true)
              elsif informative
                output << format_unified_line(line_num, nil, "<",
                                              old_content,
                                              :blue,
                                              informative: true)
                output << format_unified_line(nil, line_num, ">",
                                              new_content,
                                              :cyan,
                                              informative: true)
              else
                output << format_unified_line(line_num, nil, "-",
                                              old_content,
                                              :red)
                output << format_unified_line(nil, line_num, "+",
                                              new_content,
                                              :green)
              end
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

        # Check if diff display should be skipped
        # Returns true when:
        # 1. show_diffs is :normative AND there are no normative differences
        # 2. show_diffs is :informative AND there are no informative differences
        def should_skip_diff_display?
          return false if @differences.nil? || @differences.empty?

          case @show_diffs
          when :normative
            # Skip if no normative diffs
            @differences.none? do |diff|
              diff.is_a?(Canon::Diff::DiffNode) && diff.normative?
            end
          when :informative
            # Skip if no informative diffs
            @differences.none? do |diff|
              diff.is_a?(Canon::Diff::DiffNode) && diff.informative?
            end
          else
            # :all or other - never skip
            false
          end
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
                              format_diff_groups(groups, lines1, lines2)
                            else
                              diff_sections.map do |s|
                                s[:formatted]
                              end.compact.join("\n\n")
                            end

          output << formatted_diffs
          output.join("\n")
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

        # Check if an element or its children have semantic diffs
        def has_semantic_diff_in_subtree?(element, elements_with_semantic_diffs)
          # Check the element itself
          return true if elements_with_semantic_diffs.include?(element)

          # Check all descendants
          if element.respond_to?(:children)
            element.children.any? do |child|
              has_semantic_diff_in_subtree?(child, elements_with_semantic_diffs)
            end
          else
            false
          end
        end

        # Build set of individual elements (not pairs) that have semantic diffs
        def build_elements_with_semantic_diffs_set
          elements = Set.new

          return elements if @differences.nil? || @differences.empty?

          @differences.each do |diff|
            next unless diff.is_a?(Canon::Diff::DiffNode)

            # Add both nodes if they exist
            elements.add(diff.node1) if diff.node1
            elements.add(diff.node2) if diff.node2
          end

          elements
        end

        # Build set of children of matched parents
        def build_children_set(matches)
          children = Set.new

          matches.each do |match|
            next unless match.status == :matched

            [match.elem1, match.elem2].compact.each do |elem|
              next unless elem.respond_to?(:children)

              elem.children.each do |child|
                children.add(child) if child.respond_to?(:name)
              end
            end
          end

          children
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
              if !@differences.nil? && !@differences.empty? && @differences.any?(Canon::Diff::DiffNode)
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

        # Format matched element with metadata
        def format_matched_element_with_metadata(match, map1, map2, lines1,
                                                  lines2)
          range1 = map1[match.elem1]
          range2 = map2[match.elem2]
          return nil unless range1 && range2

          formatted = format_matched_element(match, map1, map2, lines1,
                                             lines2)
          return nil unless formatted

          {
            formatted: formatted,
            start_line1: range1.start_line,
            end_line1: range1.end_line,
            start_line2: range2.start_line,
            end_line2: range2.end_line,
            path: match.path.join("/"),
          }
        end

        # Format deleted element with metadata
        def format_deleted_element_with_metadata(match, map1, lines1)
          range1 = map1[match.elem1]
          return nil unless range1

          formatted = format_deleted_element(match, map1, lines1)
          return nil unless formatted

          {
            formatted: formatted,
            start_line1: range1.start_line,
            end_line1: range1.end_line,
            start_line2: nil,
            end_line2: nil,
            path: match.path.join("/"),
          }
        end

        # Format inserted element with metadata
        def format_inserted_element_with_metadata(match, map2, lines2)
          range2 = map2[match.elem2]
          return nil unless range2

          formatted = format_inserted_element(match, map2, lines2)
          return nil unless formatted

          {
            formatted: formatted,
            start_line1: nil,
            end_line1: nil,
            start_line2: range2.start_line,
            end_line2: range2.end_line,
            path: match.path.join("/"),
          }
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
          output << colorize("Element: #{path_str} [DELETED]", :red, :bold)

          # Show all lines as deleted
          (range1.start_line..range1.end_line).each do |i|
            output << format_unified_line(i + 1, nil, "-", lines1[i], :red)
          end

          output.join("\n")
        end

        # Format an inserted element
        def format_inserted_element(match, map2, lines2)
          range2 = map2[match.elem2]
          return nil unless range2

          output = []
          path_str = match.path.join("/")
          output << colorize("Element: #{path_str} [INSERTED]", :green, :bold)

          # Show all lines as inserted
          (range2.start_line..range2.end_line).each do |i|
            output << format_unified_line(nil, i + 1, "+", lines2[i], :green)
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

          output = []

          (context.start_idx..context.end_idx).each do |idx|
            change = diffs[idx]

            line1 = change.old_position ? base_line1 + change.old_position + 1 : nil
            line2 = change.new_position ? base_line2 + change.new_position + 1 : nil

            case change.action
            when "="
              output << format_unified_line(line1, line2, " ",
                                            change.old_element)
            when "-"
              # Check if removal is formatting-only
              output << if Canon::Diff::FormattingDetector.formatting_only?(
                change.old_element, ""
              )
                          format_unified_line(line1, nil, "[",
                                              change.old_element, :black,
                                              formatting: true)
                        else
                          format_unified_line(line1, nil, "-",
                                              change.old_element, :red)
                        end
            when "+"
              # Check if addition is formatting-only
              output << if Canon::Diff::FormattingDetector.formatting_only?("",
                                                                            change.new_element)
                          format_unified_line(nil, line2, "]",
                                              change.new_element, :white,
                                              formatting: true)
                        else
                          format_unified_line(nil, line2, "+",
                                              change.new_element, :green)
                        end
            when "!"
              # Check if change is formatting-only
              if Canon::Diff::FormattingDetector.formatting_only?(
                change.old_element, change.new_element
              )
                output << format_unified_line(line1, nil, "[",
                                              change.old_element, :black,
                                              formatting: true)
                output << format_unified_line(nil, line2, "]",
                                              change.new_element, :white,
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

        # Group diff sections by proximity
        def group_diff_sections(sections, grouping_lines)
          return [] if sections.empty?

          groups = []
          current_group = [sections[0]]

          sections[1..].each do |section|
            last_section = current_group.last

            # Calculate gap
            gap1 = if last_section[:end_line1] && section[:start_line1]
                     section[:start_line1] - last_section[:end_line1] - 1
                   else
                     Float::INFINITY
                   end

            gap2 = if last_section[:end_line2] && section[:start_line2]
                     section[:start_line2] - last_section[:end_line2] - 1
                   else
                     Float::INFINITY
                   end

            max_gap = [gap1, gap2].max

            if max_gap <= grouping_lines
              current_group << section
            else
              groups << current_group
              current_group = [section]
            end
          end

          groups << current_group unless current_group.empty?
          groups
        end

        # Format groups of diffs
        def format_diff_groups(groups, _lines1, _lines2)
          output = []

          groups.each_with_index do |group, group_idx|
            output << "" if group_idx.positive?

            if group.length > 1
              output << colorize("Context block has #{group.length} diffs",
                                 :yellow, :bold)
              output << ""
              group.each do |section|
                output << section[:formatted] if section[:formatted]
              end
            elsif group[0][:formatted]
              output << group[0][:formatted]
            end
          end

          output.join("\n")
        end

        # Format a unified diff line
        def format_unified_line(old_num, new_num, marker, content, color = nil,
informative: false, formatting: false)
          old_str = old_num ? "%4d" % old_num : "    "
          new_str = new_num ? "%4d" % new_num : "    "
          marker_part = "#{marker} "

          visualized_content = if color
                                 apply_visualization(content,
                                                     color)
                               else
                                 content
                               end

          if @use_color
            yellow_old = colorize(old_str, :yellow)
            yellow_pipe1 = colorize("|", :yellow)
            yellow_new = colorize(new_str, :yellow)
            yellow_pipe2 = colorize("|", :yellow)

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

        # Format token diff lines
        def format_token_diff_line(old_line, new_line, old_highlighted,
                                    new_highlighted)
          output = []

          if @use_color
            yellow_old = colorize("%4d" % old_line, :yellow)
            yellow_pipe1 = colorize("|", :yellow)
            yellow_new = colorize("%4d" % new_line, :yellow)
            yellow_pipe2 = colorize("|", :yellow)
            red_marker = colorize("-", :red)
            green_marker = colorize("+", :green)

            output << "#{yellow_old}#{yellow_pipe1}    #{red_marker} #{yellow_pipe2} #{old_highlighted}"
            output << "    #{yellow_pipe1}#{yellow_new}#{green_marker} #{yellow_pipe2} #{new_highlighted}"
          else
            output << "#{'%4d' % old_line}|    - | #{old_highlighted}"
            output << "    |#{'%4d' % new_line}+ | #{new_highlighted}"
          end

          output.join("\n")
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
                parts << apply_visualization(change.old_element, :red)
              end
            when "+"
              if side == :new
                parts << apply_visualization(change.new_element, :green)
              end
            when "!"
              parts << if side == :old
                         apply_visualization(change.old_element, :red)
                       else
                         apply_visualization(change.new_element, :green)
                       end
            end
          end

          parts.join
        end

        # Apply character visualization
        def apply_visualization(token, color = nil)
          return "" if token.nil?

          visual = token.to_s.chars.map do |char|
            @visualization_map.fetch(char, char)
          end.join

          if color && @use_color
            require "paint"
            Paint[visual, color, :bold]
          else
            visual
          end
        end
      end
    end
  end
end
