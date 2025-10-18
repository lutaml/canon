# frozen_string_literal: true

require_relative "base_formatter"
require "strscan"

module Canon
  class DiffFormatter
    module ByLine
      # YAML formatter with semantic token-level highlighting
      # Pretty-prints YAML before diffing for better structure awareness
      class YamlFormatter < BaseFormatter
        # Format semantic YAML diff with token-level highlighting
        #
        # @param doc1 [String] First YAML document
        # @param doc2 [String] Second YAML document
        # @return [String] Formatted diff
        def format(doc1, doc2)
          output = []

          begin
            # Pretty print both YAML files (canonicalized)
            require "canon"
            pretty1 = Canon.format(doc1, :yaml)
            pretty2 = Canon.format(doc2, :yaml)

            lines1 = pretty1.split("\n")
            lines2 = pretty2.split("\n")

            # Get LCS diff
            diffs = ::Diff::LCS.sdiff(lines1, lines2)

            # Format with semantic token highlighting
            output << format_semantic_diff(diffs, lines1, lines2)
          rescue StandardError => e
            output << colorize("Warning: YAML parsing failed (#{e.message}), using simple diff", :yellow)
            require_relative "simple_formatter"
            simple = SimpleFormatter.new(
              use_color: @use_color,
              context_lines: @context_lines,
              diff_grouping_lines: @diff_grouping_lines,
              visualization_map: @visualization_map
            )
            output << simple.format(doc1, doc2)
          end

          output.join("\n")
        end

        private

        # Format semantic diff with token-level highlighting
        #
        # @param diffs [Array] LCS diff array
        # @param lines1 [Array<String>] Lines from first document
        # @param lines2 [Array<String>] Lines from second document
        # @return [String] Formatted diff
        def format_semantic_diff(diffs, lines1, lines2)
          output = []

          # Detect non-ASCII characters in the diff
          all_text = (lines1 + lines2).join
          non_ascii = detect_non_ascii(all_text)

          # Add non-ASCII warning if any detected
          unless non_ascii.empty?
            warning = "(WARNING: non-ASCII characters detected in diff: [#{non_ascii.join(', ')}])"
            output << colorize(warning, :yellow)
            output << ""
          end

          diffs.each do |change|
            old_line = change.old_position ? change.old_position + 1 : nil
            new_line = change.new_position ? change.new_position + 1 : nil

            case change.action
            when "="
              # Unchanged line
              output << format_unified_line(old_line, new_line, " ",
                                            change.old_element)
            when "-"
              # Deletion
              output << format_unified_line(old_line, nil, "-",
                                            change.old_element, :red)
            when "+"
              # Addition
              output << format_unified_line(nil, new_line, "+",
                                            change.new_element, :green)
            when "!"
              # Change - show with semantic token highlighting
              old_text = change.old_element
              new_text = change.new_element

              # Tokenize YAML
              old_tokens = tokenize_yaml(old_text)
              new_tokens = tokenize_yaml(new_text)

              # Get token-level diff
              token_diffs = ::Diff::LCS.sdiff(old_tokens, new_tokens)

              # Build highlighted versions
              old_highlighted = build_token_highlighted_text(token_diffs, :old)
              new_highlighted = build_token_highlighted_text(token_diffs, :new)

              # Format both lines
              output << format_token_diff_line(old_line, new_line,
                                               old_highlighted,
                                               new_highlighted)
            end
          end

          output.join("\n")
        end

        # Format a unified diff line
        #
        # @param old_num [Integer, nil] Line number in old file
        # @param new_num [Integer, nil] Line number in new file
        # @param marker [String] Diff marker
        # @param content [String] Line content
        # @param color [Symbol, nil] Color for diff lines
        # @return [String] Formatted line
        def format_unified_line(old_num, new_num, marker, content, color = nil)
          old_str = old_num ? "%4d" % old_num : "    "
          new_str = new_num ? "%4d" % new_num : "    "
          marker_part = "#{marker} "

          visualized_content = color ? apply_visualization(content, color) : content

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
        #
        # @param old_line [Integer] Old line number
        # @param new_line [Integer] New line number
        # @param old_highlighted [String] Highlighted old text
        # @param new_highlighted [String] Highlighted new text
        # @return [String] Formatted lines
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

        # Tokenize YAML line into meaningful tokens
        #
        # @param line [String] YAML line to tokenize
        # @return [Array<String>] Tokens
        def tokenize_yaml(line)
          tokens = []
          scanner = StringScanner.new(line)

          until scanner.eos?
            tokens << if scanner.scan(/\s+/)
                        # Whitespace (preserve for indentation)
                        scanner.matched
                      elsif scanner.scan(/[\w-]+:/)
                        # YAML key with colon
                        scanner.matched
                      elsif scanner.scan(/"(?:[^"\\]|\\.)*"/)
                        # Quoted strings
                        scanner.matched
                      elsif scanner.scan(/'(?:[^'\\]|\\.)*'/)
                        # Single-quoted strings
                        scanner.matched
                      elsif scanner.scan(/-?\d+\.?\d*/)
                        # Numbers
                        scanner.matched
                      elsif scanner.scan(/\b(?:true|false|yes|no)\b/)
                        # Booleans
                        scanner.matched
                      elsif scanner.scan(/-\s/)
                        # List markers
                        scanner.matched
                      elsif scanner.scan(/[^\s:]+/)
                        # Bare words (unquoted values)
                        scanner.matched
                      else
                        # Any other character
                        scanner.getch
                      end
          end

          tokens
        end

        # Build highlighted text from token diff
        #
        # @param token_diffs [Array] Token-level diff
        # @param side [Symbol] Which side (:old or :new)
        # @return [String] Highlighted text
        def build_token_highlighted_text(token_diffs, side)
          parts = []

          token_diffs.each do |change|
            case change.action
            when "="
              # Unchanged token - apply visualization with explicit reset
              visual = change.old_element.chars.map do |char|
                @visualization_map.fetch(char, char)
              end.join

              parts << if @use_color
                         colorize(visual, :default)
                       else
                         visual
                       end
            when "-"
              # Deleted token (only show on old side)
              if side == :old
                token = change.old_element
                parts << apply_visualization(token, :red)
              end
            when "+"
              # Added token (only show on new side)
              if side == :new
                token = change.new_element
                parts << apply_visualization(token, :green)
              end
            when "!"
              # Changed token
              if side == :old
                token = change.old_element
                parts << apply_visualization(token, :red)
              else
                token = change.new_element
                parts << apply_visualization(token, :green)
              end
            end
          end

          parts.join
        end

        # Apply character visualization
        #
        # @param token [String] Token to visualize
        # @param color [Symbol, nil] Optional color
        # @return [String] Visualized token
        def apply_visualization(token, color = nil)
          visual = token.chars.map do |char|
            @visualization_map.fetch(char, char)
          end.join

          if color && @use_color
            require "paint"
            Paint[visual, color, :bold]
          else
            visual
          end
        end

        # Detect non-ASCII characters in text
        #
        # @param text [String] Text to check
        # @return [Array<String>] Non-ASCII character descriptions
        def detect_non_ascii(text)
          non_ascii_chars = []
          text.each_char do |char|
            if char.ord > 127
              codepoint = "U+%04X" % char.ord
              visualization = @visualization_map.fetch(char, char)
              non_ascii_chars << if visualization == char
                                   "'#{char}' (#{codepoint})"
                                 else
                                   "'#{char}' (#{codepoint}, shown as: '#{visualization}')"
                                 end
            end
          end
          non_ascii_chars.uniq
        end
      end
    end
  end
end
