# frozen_string_literal: true

require_relative "base_formatter"
require_relative "../legend"
require "set"

module Canon
  class DiffFormatter
    module ByLine
      # HTML formatter with DOM-guided diffing
      # Uses DOM parsing and element matching for intelligent HTML diffs
      class HtmlFormatter < BaseFormatter
        attr_reader :html_version

        def initialize(use_color: true, context_lines: 3,
                       diff_grouping_lines: nil, visualization_map: nil,
                       html_version: :html4, show_diffs: :all, differences: [])
          super(use_color: use_color, context_lines: context_lines,
                diff_grouping_lines: diff_grouping_lines,
                visualization_map: visualization_map,
                show_diffs: show_diffs, differences: differences)
          @html_version = html_version
        end

        # Format DOM-guided HTML diff
        #
        # @param doc1 [String] First HTML document
        # @param doc2 [String] Second HTML document
        # @return [String] Formatted diff
        def format(doc1, doc2)
          # If we have DiffNodes from comparison, use the new pipeline
          if @differences&.any?(Canon::Diff::DiffNode)
            # Check if we should skip based on show_diffs setting
            if should_skip_diff_display?
              return ""
            end

            # Use new pipeline when DiffNodes available
            return format_with_pipeline(doc1, doc2)
          end

          # LEGACY: Fall back to old DOM-based behavior
          # Check if we should show any diffs based on differences array
          if should_skip_diff_display?
            return ""
          end

          require_relative "../../html/data_model"
          require_relative "../../xml/element_matcher"
          require_relative "../../xml/line_range_mapper"
          require_relative "../../pretty_printer/html"

          output = []

          begin
            # Parse to DOM using HTML parser
            root1 = Canon::Html::DataModel.from_html(doc1,
                                                     version: @html_version)
            root2 = Canon::Html::DataModel.from_html(doc2,
                                                     version: @html_version)

            # Match elements semantically
            matcher = Canon::Xml::ElementMatcher.new
            matches = matcher.match_trees(root1, root2)

            # Pretty-print HTML for line mapping
            pretty_printer = Canon::PrettyPrinter::Html.new(indent: 2)
            pretty1 = pretty_printer.format(doc1)
            pretty2 = pretty_printer.format(doc2)

            # Build line range maps using pretty-printed documents
            mapper1 = Canon::Xml::LineRangeMapper.new(indent: 2)
            mapper2 = Canon::Xml::LineRangeMapper.new(indent: 2)
            map1 = mapper1.build_map(root1, pretty1)
            map2 = mapper2.build_map(root2, pretty2)

            # Use pretty-printed document lines for display
            lines1 = pretty1.split("\n")
            lines2 = pretty2.split("\n")

            # DEBUG
            warn "DEBUG: HTML Formatter - lines1.length=#{lines1.length}, lines2.length=#{lines2.length}"
            warn "DEBUG: HTML Formatter - matches.length=#{matches.length}"
            warn "DEBUG: HTML Formatter - map1.size=#{map1.size}, map2.size=#{map2.size}"
            warn "DEBUG: Mapped elements in map1: #{map1.keys.map(&:name).join(', ')}"
            warn "DEBUG: Match types: matched=#{matches.count do |m|
              m.status == :matched
            end}, deleted=#{matches.count do |m|
              m.status == :deleted
            end}, inserted=#{matches.count do |m|
                             m.status == :inserted
                           end}"

            # Display diffs based on element matches
            result = format_element_matches(matches, map1, map2, lines1, lines2)
            warn "DEBUG: HTML Formatter - result.length=#{result.length}"
            output << result
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

        # Format using new DiffReportBuilder pipeline
        def format_with_pipeline(doc1, doc2)
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

        private

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

          # DEBUG
          warn "DEBUG: format_element_matches - diff_sections.length=#{diff_sections.length}"
          warn "DEBUG: format_element_matches - elements_to_skip.size=#{elements_to_skip.size}"
          warn "DEBUG: format_element_matches - children_of_matched_parents.size=#{children_of_matched_parents.size}"

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
                              diff_sections.map do |s|
                                s[:formatted]
                              end.compact.join("\n\n")
                            end

          warn "DEBUG: format_element_matches - formatted_diffs.length=#{formatted_diffs.length}"
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

        # Collect diff sections with metadata
        def collect_diff_sections(matches, map1, map2, lines1, lines2,
                                   elements_to_skip, _children_of_matched_parents)
          diff_sections = []
          no_range_count = 0
          no_diff_count = 0

          # If there are NO semantic diffs, don't show any matched elements
          # (all text diffs were normalized away)
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

              range1 = map1[match.elem1]
              range2 = map2[match.elem2]
              if !range1 || !range2
                no_range_count += 1
                warn "DEBUG: No range for #{match.elem1.name} (path: #{match.path.join('/')})" if no_range_count <= 5
              end

              section = format_matched_element_with_metadata(match, map1,
                                                             map2, lines1,
                                                             lines2)
              if range1 && range2 && !section
                no_diff_count += 1
                warn "DEBUG: No diff for #{match.elem1.name} (path: #{match.path.join('/')})" if no_diff_count <= 5
              end
              diff_sections << section if section
            when :deleted
              # Don't skip deleted elements - they should always be shown
              section = format_deleted_element_with_metadata(match, map1,
                                                             lines1)
              diff_sections << section if section
            when :inserted
              # Don't skip inserted elements - they should always be shown
              section = format_inserted_element_with_metadata(match, map2,
                                                              lines2)
              diff_sections << section if section
            end
          end

          warn "DEBUG: collect_diff_sections - no_range_count=#{no_range_count}, no_diff_count=#{no_diff_count}"
          diff_sections
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
      end
    end
  end
end
