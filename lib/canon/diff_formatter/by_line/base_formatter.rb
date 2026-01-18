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

        # Filter differences for display based on show_diffs setting
        #
        # @param differences [Array<Canon::Diff::DiffNode>] Array of differences
        # @return [Array<Canon::Diff::DiffNode>] Filtered differences
        def filter_differences_for_display(differences)
          return differences if @show_diffs.nil? || @show_diffs == :all

          differences.select do |diff|
            # Handle both DiffNode objects and legacy Hash format
            is_normative = if diff.respond_to?(:normative?)
                             diff.normative?
                           elsif diff.is_a?(Hash) && diff.key?(:normative)
                             diff[:normative]
                           else
                             # Default to normative if unknown
                             true
                           end

            case @show_diffs
            when :normative
              is_normative
            when :informative
              !is_normative
            else
              true # Unknown value, show all
            end
          end
        end

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
        # @param marker [String] Diff marker (' ', '-', '+', '<', '>', '[', ']')
        # @param content [String] Line content
        # @param color [Symbol, nil] Color for diff lines
        # @param informative [Boolean] Whether this is an informative diff
        # @param formatting [Boolean] Whether this is a formatting-only diff
        # @return [String] Formatted line
        def format_unified_line(old_num, new_num, marker, content, color = nil,
                                informative: false, formatting: false)
          old_str = old_num ? "%4d" % old_num : "    "
          new_str = new_num ? "%4d" % new_num : "    "

          # Formatting and informative diffs use directional colors already passed in
          # No need to override since callers set the correct color
          effective_color = color

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

        # Build set of children of matched parents
        #
        # @param matches [Array<Match>] Element matches
        # @return [Set] Set of child elements
        def build_children_set(matches)
          require "set"

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

        # Build set of individual elements that have semantic diffs
        #
        # @return [Set] Set of elements with semantic diffs
        def build_elements_with_semantic_diffs_set
          require "set"

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

        # Check if an element or its children have semantic diffs
        #
        # @param element [Object] Element to check
        # @param elements_with_semantic_diffs [Set] Set of elements with diffs
        # @return [Boolean] True if element or descendants have semantic diffs
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

        # Check if diff display should be skipped
        # Returns true when:
        # 1. show_diffs is :normative AND there are no normative differences
        # 2. show_diffs is :informative AND there are no informative differences
        #
        # @return [Boolean] True if diff display should be skipped
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

        # Group diff sections by proximity
        #
        # @param sections [Array<Hash>] Diff sections
        # @param grouping_lines [Integer] Maximum gap to group
        # @return [Array<Array>] Grouped sections
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
        #
        # @param groups [Array<Array>] Grouped diff sections
        # @return [String] Formatted groups
        def format_diff_groups(groups)
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

        # Format matched element with metadata
        # Subclasses may override to customize behavior
        #
        # @param match [Match] Element match
        # @param map1 [Hash] Line range map for doc1
        # @param map2 [Hash] Line range map for doc2
        # @param lines1 [Array<String>] Lines from doc1
        # @param lines2 [Array<String>] Lines from doc2
        # @return [Hash, nil] Metadata hash or nil
        def format_matched_element_with_metadata(match, map1, map2, lines1, lines2)
          range1 = map1[match.elem1]
          range2 = map2[match.elem2]
          return nil unless range1 && range2

          # Subclasses must implement format_matched_element
          formatted = format_matched_element(match, map1, map2, lines1, lines2)
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
        # Subclasses may override to customize behavior
        #
        # @param match [Match] Element match
        # @param map1 [Hash] Line range map for doc1
        # @param lines1 [Array<String>] Lines from doc1
        # @return [Hash, nil] Metadata hash or nil
        def format_deleted_element_with_metadata(match, map1, lines1)
          range1 = map1[match.elem1]
          return nil unless range1

          # Subclasses must implement format_deleted_element
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
        # Subclasses may override to customize behavior
        #
        # @param match [Match] Element match
        # @param map2 [Hash] Line range map for doc2
        # @param lines2 [Array<String>] Lines from doc2
        # @return [Hash, nil] Metadata hash or nil
        def format_inserted_element_with_metadata(match, map2, lines2)
          range2 = map2[match.elem2]
          return nil unless range2

          # Subclasses must implement format_inserted_element
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

        # Subclasses must implement these element formatting methods
        def format_matched_element(_match, _map1, _map2, _lines1, _lines2)
          raise NotImplementedError,
                "Subclasses must implement format_matched_element"
        end

        def format_deleted_element(_match, _map1, _lines1)
          raise NotImplementedError,
                "Subclasses must implement format_deleted_element"
        end

        def format_inserted_element(_match, _map2, _lines2)
          raise NotImplementedError,
                "Subclasses must implement format_inserted_element"
        end
      end
    end
  end
end
