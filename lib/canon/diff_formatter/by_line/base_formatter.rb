# frozen_string_literal: true

require "diff/lcs"
require "diff/lcs/hunk"
require_relative "../debug_output"

module Canon
  class DiffFormatter
    module ByLine
      # Base formatter for line-by-line diffs
      # Provides common LCS diff logic and hunk building
      class BaseFormatter
        attr_reader :use_color, :context_lines, :diff_grouping_lines,
                    :visualization_map, :show_diffs

        # Create a format-specific by-line formatter
        #
        # @param format [Symbol] Format type (:xml, :html, :html4, :html5, :json, :yaml, :simple)
        # @param options [Hash] Formatting options
        # @return [BaseFormatter] Format-specific formatter instance
        def self.for_format(format, **options)
          case format
          when :xml
            require_relative "xml_formatter"
            XmlFormatter.new(**options)
          when :html, :html4, :html5
            require_relative "html_formatter"
            # Determine HTML version from format
            version = case format
                      when :html5 then :html5
                      when :html4 then :html4
                      else :html4 # default to html4
                      end
            HtmlFormatter.new(html_version: version, **options)
          when :json
            require_relative "json_formatter"
            JsonFormatter.new(**options)
          when :yaml
            require_relative "yaml_formatter"
            YamlFormatter.new(**options)
          else
            require_relative "simple_formatter"
            SimpleFormatter.new(**options)
          end
        end

        def initialize(use_color: true, context_lines: 3,
                       diff_grouping_lines: nil, visualization_map: nil,
                       show_diffs: :all, differences: [])
          @use_color = use_color
          @context_lines = context_lines
          @diff_grouping_lines = diff_grouping_lines
          @visualization_map = visualization_map
          @show_diffs = show_diffs
          @differences = differences
        end

        # Format line-by-line diff
        # Subclasses must implement this method
        #
        # @param doc1 [String] First document
        # @param doc2 [String] Second document
        # @return [String] Formatted diff
        def format(doc1, doc2)
          raise NotImplementedError,
                "Subclasses must implement the format method"
        end

        protected

        # Build hunks from diff with context lines
        #
        # @param diffs [Array] LCS diff array
        # @param lines1 [Array<String>] Lines from first document
        # @param lines2 [Array<String>] Lines from second document
        # @param context_lines [Integer] Number of context lines
        # @return [Array<Array>] Array of hunks
        def build_hunks(diffs, _lines1, _lines2, context_lines: 3)
          hunks = []
          current_hunk = []
          last_change_index = -context_lines - 1

          diffs.each_with_index do |change, index|
            # Check if we should start a new hunk
            if !current_hunk.empty? && index - last_change_index > context_lines * 2
              # Trim trailing context lines before finalizing hunk
              trim_trailing_context!(current_hunk, last_change_index,
                                     context_lines)
              hunks << current_hunk
              current_hunk = []
            end

            # Add context before first change or after gap
            if current_hunk.empty? && change.action != "="
              start_context = [index - context_lines, 0].max
              (start_context...index).each do |i|
                current_hunk << diffs[i] if i < diffs.length
              end
            end

            current_hunk << change

            # Track last change for hunk grouping
            last_change_index = index if change.action != "="
          end

          # Trim trailing context lines and add final hunk if any
          unless current_hunk.empty?
            trim_trailing_context!(current_hunk, last_change_index,
                                   context_lines)
            hunks << current_hunk
          end

          hunks
        end

        # Trim trailing context lines from a hunk
        # Removes context lines beyond context_lines after the last change
        #
        # @param hunk [Array] The hunk to trim
        # @param last_change_index [Integer] Index of last change in original diffs
        # @param context_lines [Integer] Number of context lines to keep
        def trim_trailing_context!(hunk, _last_change_index, context_lines)
          # Find the position of the last change in this hunk
          last_change_pos = nil
          hunk.each_with_index do |change, i|
            last_change_pos = i if change.action != "="
          end

          return if last_change_pos.nil?

          # Keep only context_lines after the last change
          keep_until = [last_change_pos + context_lines, hunk.length - 1].min
          hunk.slice!(keep_until + 1..-1) if keep_until < hunk.length - 1
        end

        # Colorize text if color is enabled
        # RSpec-aware: resets any existing ANSI codes before applying new colors
        #
        # @param text [String] Text to colorize
        # @param colors [Array<Symbol>] Paint color arguments
        # @return [String] Colorized or plain text
        def colorize(text, *colors)
          return text unless @use_color

          require "paint"
          # Reset ANSI codes first to prevent RSpec's initial red from interfering
          "\e[0m#{Paint[text, *colors]}"
        end

        # Identify contiguous diff blocks
        #
        # @param diffs [Array] LCS diff array
        # @return [Array<Canon::Diff::DiffBlock>] Array of diff blocks
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

          # Filter blocks based on show_diffs setting
          filter_diff_blocks(blocks)
        end

        # Group diff blocks into contexts
        #
        # @param blocks [Array<Canon::Diff::DiffBlock>] Array of diff blocks
        # @param grouping_lines [Integer] Maximum gap between blocks to group
        # @return [Array<Array<Canon::Diff::DiffBlock>>] Array of block groups
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
        #
        # @param contexts [Array<Array<Canon::Diff::DiffBlock>>] Block groups
        # @param context_lines [Integer] Number of context lines to add
        # @param total_lines [Integer] Total number of lines in diff
        # @return [Array<Canon::Diff::DiffContext>] Array of diff contexts
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
        #
        # @param context [Canon::Diff::DiffContext] The context to format
        # @param diffs [Array] LCS diff array
        # @param base_line1 [Integer] Base line number for old file
        # @param base_line2 [Integer] Base line number for new file
        # @return [String] Formatted context
        def format_context(context, diffs, base_line1, base_line2)
          output = []
          max_lines = get_max_diff_lines

          (context.start_idx..context.end_idx).each do |idx|
            change = diffs[idx]

            line1 = change.old_position ? base_line1 + change.old_position + 1 : nil
            line2 = change.new_position ? base_line2 + change.new_position + 1 : nil

            case change.action
            when "="
              output << format_unified_line(line1, line2, " ",
                                            change.old_element)
            when "-"
              output << format_unified_line(line1, nil, "-",
                                            change.old_element, :red)
            when "+"
              output << format_unified_line(nil, line2, "+",
                                            change.new_element, :green)
            when "!"
              # Format changed line
              output << format_changed_line(line1, line2,
                                            change.old_element,
                                            change.new_element)
            end

            # Check if we've exceeded the line limit
            if max_lines&.positive? && output.size >= max_lines
              output << ""
              output << colorize(
                "... Output truncated at #{max_lines} lines ...", :yellow, :bold
              )
              output << colorize(
                "Increase limit via CANON_MAX_DIFF_LINES or config.diff.max_diff_lines", :yellow
              )
              break
            end
          end

          output.join("\n")
        end

        # Filter diff blocks based on show_diffs setting
        #
        # @param blocks [Array<Canon::Diff::DiffBlock>] Array of diff blocks
        # @return [Array<Canon::Diff::DiffBlock>] Filtered array
        def filter_diff_blocks(blocks)
          case @show_diffs
          when :normative
            blocks.select(&:normative?)
          when :informative
            blocks.select(&:informative?)
          else # :all or nil
            blocks
          end
        end

        # Format a unified diff line
        #
        # @param old_num [Integer, nil] Line number in old file
        # @param new_num [Integer, nil] Line number in new file
        # @param marker [String] Diff marker (' ', '-', '+', '~')
        # @param content [String] Line content
        # @param color [Symbol, nil] Color for diff lines
        # @param informative [Boolean] Whether this is an informative diff
        # @return [String] Formatted line
        def format_unified_line(old_num, new_num, marker, content, color = nil,
                                informative: false)
          old_str = old_num ? "%4d" % old_num : "    "
          new_str = new_num ? "%4d" % new_num : "    "

          # For informative diffs, use ~ marker and cyan color
          if informative
            marker = "~"
            effective_color = :cyan
          else
            effective_color = color
          end

          marker_part = "#{marker} "

          visualized_content = if effective_color
                                 apply_visualization(content, effective_color)
                               else
                                 content
                               end

          if @use_color
            yellow_old = colorize(old_str, :yellow)
            yellow_pipe1 = colorize("|", :yellow)
            yellow_new = colorize(new_str, :yellow)
            yellow_pipe2 = colorize("|", :yellow)

            if effective_color
              colored_marker = colorize(marker, effective_color)
              "#{yellow_old}#{yellow_pipe1}#{yellow_new}#{colored_marker} #{yellow_pipe2} #{visualized_content}"
            else
              "#{yellow_old}#{yellow_pipe1}#{yellow_new}#{marker} #{yellow_pipe2} #{visualized_content}"
            end
          else
            "#{old_str}|#{new_str}#{marker_part}| #{visualized_content}"
          end
        end

        # Format changed lines (default implementation without token-level diff)
        #
        # @param old_line [Integer] Line number in old file
        # @param new_line [Integer] Line number in new file
        # @param old_text [String] Old line text
        # @param new_text [String] New line text
        # @param informative [Boolean] Whether this is an informative diff
        # @return [String] Formatted change
        def format_changed_line(old_line, new_line, old_text, new_text,
                                informative: false)
          output = []

          # For informative diffs, use cyan color and ~ marker
          if informative
            old_marker = "~"
            new_marker = "~"
            old_color = :cyan
            new_color = :cyan
          else
            old_marker = "-"
            new_marker = "+"
            old_color = :red
            new_color = :green
          end

          old_visualized = apply_visualization(old_text, old_color)
          new_visualized = apply_visualization(new_text, new_color)

          if @use_color
            yellow_old = colorize("%4d" % old_line, :yellow)
            yellow_pipe1 = colorize("|", :yellow)
            yellow_new = colorize("%4d" % new_line, :yellow)
            yellow_pipe2 = colorize("|", :yellow)
            old_marker_colored = colorize(old_marker, old_color)
            new_marker_colored = colorize(new_marker, new_color)

            output << "#{yellow_old}#{yellow_pipe1}    #{old_marker_colored} #{yellow_pipe2} #{old_visualized}"
            output << "    #{yellow_pipe1}#{yellow_new}#{new_marker_colored} #{yellow_pipe2} #{new_visualized}"
          else
            output << "#{'%4d' % old_line}|    #{old_marker} | #{old_visualized}"
            output << "    |#{'%4d' % new_line}#{new_marker} | #{new_visualized}"
          end

          output.join("\n")
        end

        # Apply character visualization
        #
        # @param token [String] The token to apply visualization to
        # @param color [Symbol, nil] Optional color to apply
        # @return [String] Visualized and optionally colored token
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

        # Get max diff lines limit
        #
        # @return [Integer, nil] Max diff output lines
        def get_max_diff_lines
          # Try to get from config if available
          config = Canon::Config.instance
          # Default to 10,000 if config not available
          config&.xml&.diff&.max_diff_lines || 10_000
        end
      end
    end
  end
end
