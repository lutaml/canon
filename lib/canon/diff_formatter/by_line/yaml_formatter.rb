# frozen_string_literal: true

require_relative "base_formatter"
require_relative "../legend"
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
          compute_line_num_width(doc1, doc2)
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
            output << colorize(
              "Warning: YAML parsing failed (#{e.message}), using simple diff", :yellow
            )
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
          non_ascii = Legend.detect_non_ascii(all_text, @visualization_map)

          # Add Unicode legend if any non-ASCII characters detected
          unless non_ascii.empty?
            output << Legend.build_legend(non_ascii, use_color: @use_color)
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
                                            change.old_element,
                                            theme_color(:removed, :content) || :red)
            when "+"
              # Addition
              output << format_unified_line(nil, new_line, "+",
                                            change.new_element,
                                            theme_color(:added, :content) || :green)
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
          fmt = "%#{@line_num_width}d"
          blank = " " * @line_num_width

          if @use_color
            ln_color = structure_color(:line_number) || :yellow
            pipe_color = structure_color(:pipe) || :yellow
            ln_old = colorize(fmt % old_line, ln_color)
            pipe1 = colorize("|", pipe_color)
            ln_new = colorize(fmt % new_line, ln_color)
            pipe2 = colorize("|", pipe_color)
            removed_color = theme_color(:removed, :content) || :red
            added_color = theme_color(:added, :content) || :green
            red_marker = colorize("-", removed_color)
            green_marker = colorize("+", added_color)

            output << "#{ln_old}#{pipe1}#{blank}#{red_marker} #{pipe2} #{old_highlighted}"
            output << "#{blank}#{pipe1}#{ln_new}#{green_marker} #{pipe2} #{new_highlighted}"
          else
            output << "#{fmt % old_line}|#{blank}- | #{old_highlighted}"
            output << "#{blank}|#{fmt % new_line}+ | #{new_highlighted}"
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
                parts << apply_visualization(token,
                                             theme_color(:removed, :content) || :red)
              end
            when "+"
              # Added token (only show on new side)
              if side == :new
                token = change.new_element
                parts << apply_visualization(token,
                                             theme_color(:added, :content) || :green)
              end
            when "!"
              # Changed token
              if side == :old
                token = change.old_element
                parts << apply_visualization(token,
                                             theme_color(:removed, :content) || :red)
              else
                token = change.new_element
                parts << apply_visualization(token,
                                             theme_color(:added, :content) || :green)
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
            require "rainbow"
            Rainbow(visual).send(color).bright.to_s
          else
            visual
          end
        end
      end
    end
  end
end
