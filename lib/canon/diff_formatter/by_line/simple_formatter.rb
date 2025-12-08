# frozen_string_literal: true

require_relative "base_formatter"
require_relative "../legend"

module Canon
  class DiffFormatter
    module ByLine
      # Simple line-based formatter (fallback)
      # Uses basic LCS diff without format-specific intelligence
      class SimpleFormatter < BaseFormatter
        # Format simple line-by-line diff
        #
        # @param doc1 [String] First document
        # @param doc2 [String] Second document
        # @return [String] Formatted diff
        def format(doc1, doc2)
          output = []
          # Use split with -1 to preserve trailing empty strings (from trailing \n)
          lines1 = doc1.split("\n", -1)
          lines2 = doc2.split("\n", -1)

          # Detect non-ASCII characters in the diff
          all_text = (lines1 + lines2).join
          non_ascii = Legend.detect_non_ascii(all_text, @visualization_map)

          # Add Unicode legend if any non-ASCII characters detected
          unless non_ascii.empty?
            output << Legend.build_legend(non_ascii, use_color: @use_color)
            output << ""
          end

          # Get LCS diff
          diffs = ::Diff::LCS.sdiff(lines1, lines2)

          # Group into hunks with context
          hunks = build_hunks(diffs, lines1, lines2,
                              context_lines: @context_lines)

          # Format each hunk
          hunks.each do |hunk|
            output << format_hunk(hunk)
          end

          output.join("\n")
        end

        private

        # Format a hunk of changes
        #
        # @param hunk [Array] Hunk of diff changes
        # @return [String] Formatted hunk
        def format_hunk(hunk)
          output = []
          old_line = hunk.first.old_position + 1
          new_line = hunk.first.new_position + 1

          hunk.each do |change|
            case change.action
            when "="
              # Unchanged line (context)
              output << format_unified_line(old_line, new_line, " ",
                                            change.old_element)
              old_line += 1
              new_line += 1
            when "-"
              # Deletion
              output << format_unified_line(old_line, nil, "-",
                                            change.old_element, :red)
              old_line += 1
            when "+"
              # Addition
              output << format_unified_line(nil, new_line, "+",
                                            change.new_element, :green)
              new_line += 1
            when "!"
              # Change - show both with inline diff highlighting
              old_text = change.old_element
              new_text = change.new_element

              # Format with inline highlighting
              output << format_changed_line(old_line, old_text, new_text)
              old_line += 1
              new_line += 1
            end
          end

          output.join("\n")
        end

        # Format changed lines with basic character-level diff
        #
        # @param line_num [Integer] Line number
        # @param old_text [String] Old line text
        # @param new_text [String] New line text
        # @return [String] Formatted change
        def format_changed_line(line_num, old_text, new_text)
          output = []

          # Apply visualization
          old_visualized = apply_visualization(old_text, :red)
          new_visualized = apply_visualization(new_text, :green)

          # Format both lines with yellow line numbers and pipes
          if @use_color
            yellow_old = colorize("%4d" % line_num, :yellow)
            yellow_pipe1 = colorize("|", :yellow)
            yellow_new = colorize("%4d" % line_num, :yellow)
            yellow_pipe2 = colorize("|", :yellow)
            red_marker = colorize("-", :red)
            green_marker = colorize("+", :green)

            output << "#{yellow_old}#{yellow_pipe1}    #{red_marker} #{yellow_pipe2} #{old_visualized}"
            output << "    #{yellow_pipe1}#{yellow_new}#{green_marker} #{yellow_pipe2} #{new_visualized}"
          else
            old_str = "%4d" % line_num
            new_str = "%4d" % line_num
            output << "#{old_str}|    - | #{old_visualized}"
            output << "    |#{new_str}+ | #{new_visualized}"
          end

          output.join("\n")
        end

        # Apply character visualization using configurable visualization map
        #
        # @param token [String] The token to apply visualization to
        # @param color [Symbol, nil] Optional color to apply
        # @return [String] Visualized and optionally colored token
        def apply_visualization(token, color = nil)
          # Replace each character with its visualization from the map
          visual = token.chars.map do |char|
            @visualization_map.fetch(char, char)
          end.join

          # Apply color if provided and color is enabled
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
