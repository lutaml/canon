# frozen_string_literal: true

require "set"

module Canon
  class DiffFormatter
    module ByLine
      # HTML formatter with DOM-guided diffing
      # Uses DOM parsing and element matching for intelligent HTML diffs
      class HtmlFormatter < BaseFormatter
        attr_reader :html_version

        # rubocop:disable-next Metrics/ParameterLists
        def initialize(use_color: true, context_lines: 3,
                       diff_grouping_lines: nil, visualization_map: nil,
                       html_version: :html4, show_diffs: :all, differences: [],
                       diff_mode: :separate, legacy_terminal: false,
                       equivalent: nil, character_visualization: true)
          super(use_color: use_color, context_lines: context_lines,
                diff_grouping_lines: diff_grouping_lines,
                visualization_map: visualization_map,
                show_diffs: show_diffs, differences: differences,
                diff_mode: diff_mode, legacy_terminal: legacy_terminal,
                equivalent: equivalent,
                character_visualization: character_visualization)
          @html_version = html_version
        end

        # Format DOM-guided HTML diff
        #
        # @param doc1 [String] First HTML document
        # @param doc2 [String] Second HTML document
        # @return [String] Formatted diff
        def format(doc1, doc2)
          compute_line_num_width(doc1, doc2)
          return "" if should_skip_diff_display?

          # The DiffNode pipeline is the only renderer: without
          # DiffNodes there is nothing to report (#84).
          format_with_pipeline(doc1, doc2)
        end

        # Format using new DiffReportBuilder pipeline
        def format_with_pipeline(doc1, doc2)
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
                          # Formatting-only removal: [ marker
                          format_unified_line(line_num, nil, "[",
                                              diff_line.content,
                                              theme_color(:formatting,
                                                          :marker) || :black,
                                              formatting: true)
                        elsif informative
                          # Informative removal: < marker
                          format_unified_line(line_num, nil, "<",
                                              diff_line.content,
                                              theme_color(:informative,
                                                          :marker) || :blue,
                                              informative: true)
                        else
                          # Normative removal: - marker
                          format_unified_line(line_num, nil, "-",
                                              diff_line.content,
                                              theme_color(:removed,
                                                          :marker) || :red)
                        end
            when :added
              line_num = diff_line.line_number + 1
              formatting = diff_line.formatting?
              informative = diff_line.informative?

              output << if formatting
                          # Formatting-only addition: ] marker
                          format_unified_line(nil, line_num, "]",
                                              diff_line.content,
                                              theme_color(:formatting,
                                                          :marker) || :white,
                                              formatting: true)
                        elsif informative
                          # Informative addition: > marker
                          format_unified_line(nil, line_num, ">",
                                              diff_line.content,
                                              theme_color(:informative,
                                                          :marker) || :cyan,
                                              informative: true)
                        else
                          # Normative addition: + marker
                          format_unified_line(nil, line_num, "+",
                                              diff_line.content,
                                              theme_color(:added,
                                                          :marker) || :green)
                        end
            when :changed
              line_num = diff_line.line_number + 1
              formatting = diff_line.formatting?
              informative = diff_line.informative?
              old_content = lines1[diff_line.line_number]
              new_content = diff_line.content

              if formatting
                fmt_color = theme_color(:formatting, :marker) || :black
                output << format_unified_line(line_num, nil, "[",
                                              old_content,
                                              fmt_color,
                                              formatting: true)
                output << format_unified_line(nil, line_num, "]",
                                              new_content,
                                              fmt_color,
                                              formatting: true)
              elsif informative
                inf_color = theme_color(:informative, :marker) || :blue
                output << format_unified_line(line_num, nil, "<",
                                              old_content,
                                              inf_color,
                                              informative: true)
                output << format_unified_line(nil, line_num, ">",
                                              new_content,
                                              inf_color,
                                              informative: true)
              else
                output << format_unified_line(line_num, nil, "-",
                                              old_content,
                                              theme_color(:removed,
                                                          :marker) || :red)
                output << format_unified_line(nil, line_num, "+",
                                              new_content,
                                              theme_color(:added,
                                                          :marker) || :green)
              end
            end
          end

          output.join("\n")
        end
      end
    end
  end
end
