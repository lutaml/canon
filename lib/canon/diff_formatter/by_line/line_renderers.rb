# frozen_string_literal: true

require "rainbow"

module Canon
  class DiffFormatter
    module ByLine
      # Base class for rendering a single DiffLine to a formatted string.
      #
      # Each line type has a dedicated renderer that knows how to format
      # that specific line type using the theme's colors and styles.
      #
      # @example Render a reflow summary line
      #   renderer = ReflowSummaryLineRenderer.new(
      #     theme: theme,
      #     use_color: true,
      #     line_num_width: 4
      #   )
      #   output = renderer.render(diff_line)
      #
      # @abstract
      class LineRenderer
        # @param theme [Hash] The resolved theme hash
        # @param use_color [Boolean] Whether to apply ANSI colors
        # @param line_num_width [Integer] Width for line number padding
        def initialize(theme:, use_color:, line_num_width:)
          @theme = theme
          @use_color = use_color
          @line_num_width = line_num_width
        end

        # Render the diff line to a formatted string
        # @param diff_line [DiffLine] The line to render
        # @return [String] Formatted line
        def render(diff_line)
          raise NotImplementedError, "#{self.class} must implement #render"
        end

        protected

        attr_reader :theme, :use_color, :line_num_width

        # Get a color from the theme
        # @param section [Symbol] e.g., :diff, :xml, :structure
        # @param diff_type [Symbol] e.g., :removed, :added, :formatting
        # @param element [Symbol] e.g., :marker, :content
        # @return [Symbol, nil] Color value
        def theme_color(section, diff_type, element)
          theme.dig(section, diff_type, element, :color)
        end

        # Get a style hash from the theme
        # @param section [Symbol] e.g., :diff
        # @param diff_type [Symbol] e.g., :removed
        # @param element [Symbol] e.g., :content
        # @return [Hash] Style properties
        def theme_style(section, diff_type, element)
          theme.dig(section, diff_type, element) || {}
        end

        # Get structure element color from theme
        # @param element [Symbol] e.g., :line_number, :pipe
        # @return [Symbol, nil] Color value
        def structure_color(element)
          theme.dig(:structure, element, :color)
        end

        # Apply ANSI color to text using Rainbow
        # Handles color normalization (bright_blue -> blue.bright, etc.)
        # @param text [String] Text to colorize
        # @param color [Symbol, nil] Color to apply (e.g., :red, :bright_blue)
        # @return [String] Colorized text
        def colorize(text, color)
          return text unless use_color && color

          rainbow = Rainbow.new
          rainbow.enabled = true
          presenter = rainbow.wrap(text)

          # Normalize color (e.g., :bright_blue -> [:blue, :bright])
          normalized = normalize_color_for_rainbow(color)
          normalized.each { |c| presenter = presenter.send(c) }
          presenter.to_s
        end

        # Normalize a color symbol for Rainbow presenter.
        # Rainbow doesn't support :bright_blue directly - instead it uses
        # chained methods like .blue.bright or .bright.blue.
        # @param color [Symbol] Color like :bright_blue, :light_red, etc.
        # @return [Array<Symbol>] Method chain for Rainbow
        def normalize_color_for_rainbow(color)
          return [] if color.nil?

          case color.to_s
          when /^bright_(.+)$/
            base = $1.to_sym
            [base, :bright]
          when /^light_(.+)$/
            [:white]
          when "default", "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"
            [color]
          else
            [color]
          end
        end

        # Create line number string with padding
        # @param num [Integer, nil] Line number (nil for blank)
        # @return [String] Padded line number string
        def format_line_num(num)
          num ? "%#{line_num_width}d" % num : " " * line_num_width
        end

        # Create blank line number string
        # @return [String] Blank string of line_num_width
        def blank_line_num
          " " * line_num_width
        end

        # Apply style (color) to text without background or effects.
        # Used for formatting-only changes where only color is needed.
        # @param text [String] Text to style
        # @param style [Hash] Style hash with :color key
        # @return [String] Styled text
        def apply_style_only(text, style)
          return text unless style[:color]

          if use_color
            color = style[:color]
            rainbow = Rainbow.new
            rainbow.enabled = true
            presenter = rainbow.wrap(text)
            normalized = normalize_color_for_rainbow(color)
            normalized.each { |c| presenter = presenter.send(c) }
            presenter.to_s
          else
            text
          end
        end

        # Apply selective visualization: only special whitespace (NBSP) is visualized,
        # regular spaces are kept as-is.
        # @param text [String] Text to apply selective visualization to
        # @return [String] Text with selective visualization applied
        def apply_selective_visualization(text)
          # In LineRenderer context, we just return text as-is
          # The colorize method handles basic ANSI coloring
          text
        end
      end

      # Renders a reflow summary line (e.g., "... 23 more removed (formatting only) ...")
      #
      # This line appears when there are multiple lines of formatting-only changes
      # that have been collapsed into a summary line.
      # Uses theme structure colors for pipes and line number areas.
      class ReflowSummaryLineRenderer < LineRenderer
        # @param diff_line [DiffLine] Must have type :reflow_summary
        # @return [String] Formatted reflow summary line
        def render(diff_line)
          content = diff_line.content

          # Reflow summary represents a range; show starting line of the range
          old_num = diff_line.line_number + 1
          new_num = (diff_line.new_position || diff_line.line_number) + 1

          if use_color
            line_color = structure_color(:line_number) || :white
            pipe_color = structure_color(:pipe) || :white
            formatting_color = theme_color(:diff, :formatting,
                                           :content) || :bright_blue

            old_str = colorize(format_line_num(old_num), line_color)
            new_str = colorize(format_line_num(new_num), line_color)
            pipe1 = colorize("|", pipe_color)
            pipe2 = colorize("|", pipe_color)
            colored_content = colorize(content, formatting_color)

            "#{old_str}#{pipe1}#{new_str}#{pipe2} #{colored_content}"
          else
            "#{format_line_num(old_num)}|#{format_line_num(new_num)}| #{content}"
          end
        end
      end

      # Renders an unchanged line (context line)
      class UnchangedLineRenderer < LineRenderer
        # @param diff_line [DiffLine] Must have type :unchanged
        # @return [String] Formatted unchanged line
        def render(diff_line)
          old_num = diff_line.line_number + 1
          new_num = (diff_line.new_position || diff_line.line_number) + 1

          old_str = format_line_num(old_num)
          new_str = format_line_num(new_num)

          if use_color
            line_color = structure_color(:line_number) || :yellow
            pipe_color = structure_color(:pipe) || :yellow
            colored_old = colorize(old_str, line_color)
            colored_new = colorize(new_str, line_color)
            colored_pipe1 = colorize("|", pipe_color)
            colored_pipe2 = colorize("|", pipe_color)
            "#{colored_old}#{colored_pipe1}#{colored_new}#{colored_pipe2} #{diff_line.content}"
          else
            "#{old_str}|#{new_str} | #{diff_line.content}"
          end
        end
      end

      # Renders a removed line
      class RemovedLineRenderer < LineRenderer
        # @param diff_line [DiffLine] Must have type :removed
        # @return [String] Formatted removed line
        def render(diff_line)
          line_num = diff_line.line_number + 1

          if diff_line.has_char_ranges?
            render_with_char_ranges(diff_line, line_num)
          elsif diff_line.formatting?
            render_formatting_removed(diff_line, line_num)
          elsif diff_line.informative?
            render_informative_removed(diff_line, line_num)
          else
            render_normative_removed(diff_line, line_num)
          end
        end

        private

        def render_formatting_removed(diff_line, line_num)
          marker = "["
          content = diff_line.content
          formatting_color = theme_color(:diff, :formatting,
                                         :content) || :bright_blue

          old_str = format_line_num(line_num)
          new_str = blank_line_num

          if use_color
            line_color = structure_color(:line_number) || :yellow
            pipe_color = structure_color(:pipe) || :yellow
            colored_old = colorize(old_str, line_color)
            colored_new = colorize(new_str, line_color)
            colored_pipe1 = colorize("|", pipe_color)
            colored_pipe2 = colorize("|", pipe_color)
            colored_marker = colorize(marker, formatting_color)
            "#{colored_old}#{colored_pipe1}#{colored_new}#{colored_marker} #{colored_pipe2} #{content}"
          else
            "#{old_str}|#{new_str} #{marker} | #{content}"
          end
        end

        def render_informative_removed(diff_line, line_num)
          marker = "<"
          content = diff_line.content
          content_color = theme_color(:diff, :informative, :content) || :cyan

          old_str = format_line_num(line_num)
          new_str = blank_line_num

          if use_color
            line_color = structure_color(:line_number) || :yellow
            pipe_color = structure_color(:pipe) || :yellow
            colored_old = colorize(old_str, line_color)
            colored_new = colorize(new_str, line_color)
            colored_pipe1 = colorize("|", pipe_color)
            colored_pipe2 = colorize("|", pipe_color)
            colored_marker = colorize(marker, content_color)
            "#{colored_old}#{colored_pipe1}#{colored_new}#{colored_marker} #{colored_pipe2} #{content}"
          else
            "#{old_str}|#{new_str} #{marker} | #{content}"
          end
        end

        def render_normative_removed(diff_line, line_num)
          marker = "-"
          content = diff_line.content
          content_color = theme_color(:diff, :removed, :content) || :red

          old_str = format_line_num(line_num)
          new_str = blank_line_num

          if use_color
            line_color = structure_color(:line_number) || :yellow
            pipe_color = structure_color(:pipe) || :yellow
            colored_old = colorize(old_str, line_color)
            colored_new = colorize(new_str, line_color)
            colored_pipe1 = colorize("|", pipe_color)
            colored_pipe2 = colorize("|", pipe_color)
            colored_marker = colorize(marker, content_color)
            "#{colored_old}#{colored_pipe1}#{colored_new}#{colored_marker} #{colored_pipe2} #{content}"
          else
            "#{old_str}|#{new_str} #{marker} | #{content}"
          end
        end

        def render_with_char_ranges(diff_line, line_num)
          # Get ranges for the old side (removed lines use text1 ranges)
          ranges = diff_line.char_ranges.select(&:old_side?)
          return render_normative_removed(diff_line, line_num) if ranges.empty?

          line_text = diff_line.content
          formatting = diff_line.formatting?
          informative = diff_line.informative?

          # Build highlighted content from ranges
          parts = []
          cursor = 0

          formatting_style = theme_style(:diff, :formatting,
                                         :content) || { color: :bright_blue }
          removed_style = theme_style(:diff, :removed, :content) || {}
          informative_style = theme_style(:diff, :informative, :content) || {}

          # Sort ranges by start_col for consistent rendering
          sorted_ranges = ranges.sort_by(&:start_col)

          sorted_ranges.each do |cr|
            # Fill in any gap before this range as unchanged text
            if cursor < cr.start_col
              gap = line_text[cursor...cr.start_col]
              parts << apply_selective_visualization(gap)
            end

            segment = cr.extract_from(line_text)
            next if segment.nil? || segment.empty?

            parts << if formatting
                       # Formatting-only change: only highlight CHANGED segments.
                       case cr.status
                       when :changed_old
                         apply_style_only(segment, formatting_style)
                       else
                         apply_selective_visualization(segment)
                       end
                     elsif informative
                       # Informative change
                       case cr.status
                       when :changed_old
                         apply_style_only(segment, informative_style)
                       else
                         apply_selective_visualization(segment)
                       end
                     else
                       # Normative change: use theme removed colors
                       case cr.status
                       when :changed_old
                         apply_style_only(segment, removed_style)
                       else
                         apply_selective_visualization(segment)
                       end
                     end

            cursor = cr.end_col
          end

          # Fill in any remaining text after the last range
          if cursor < line_text.length
            tail = line_text[cursor..]
            parts << apply_selective_visualization(tail)
          end

          highlighted_content = parts.join

          # Build the full line
          old_str = format_line_num(line_num)
          new_str = blank_line_num

          marker = if formatting
                     "["
                   elsif informative
                     "<"
                   else
                     "-"
                   end

          if use_color
            line_color = structure_color(:line_number) || :yellow
            pipe_color = structure_color(:pipe) || :yellow
            marker_color = if formatting
                             theme_color(:diff, :formatting,
                                         :marker) || :bright_blue
                           elsif informative
                             theme_color(:diff, :informative, :marker) || :cyan
                           else
                             theme_color(:diff, :removed, :marker) || :red
                           end

            colored_old = colorize(old_str, line_color)
            colored_new = colorize(new_str, line_color)
            colored_pipe1 = colorize("|", pipe_color)
            colored_pipe2 = colorize("|", pipe_color)
            colored_marker = colorize(marker, marker_color)
            "#{colored_old}#{colored_pipe1}#{colored_new}#{colored_marker} #{colored_pipe2} #{highlighted_content}"
          else
            "#{old_str}|#{new_str} #{marker} | #{highlighted_content}"
          end
        end
      end

      # Renders an added line
      class AddedLineRenderer < LineRenderer
        # @param diff_line [DiffLine] Must have type :added
        # @return [String] Formatted added line
        def render(diff_line)
          line_num = (diff_line.new_position || diff_line.line_number) + 1

          if diff_line.has_char_ranges?
            render_with_char_ranges(diff_line, line_num)
          elsif diff_line.formatting?
            render_formatting_added(diff_line, line_num)
          elsif diff_line.informative?
            render_informative_added(diff_line, line_num)
          else
            render_normative_added(diff_line, line_num)
          end
        end

        private

        def render_formatting_added(diff_line, line_num)
          marker = "]"
          content = diff_line.content
          formatting_color = theme_color(:diff, :formatting,
                                         :content) || :bright_blue

          old_str = blank_line_num
          new_str = format_line_num(line_num)

          if use_color
            line_color = structure_color(:line_number) || :yellow
            pipe_color = structure_color(:pipe) || :yellow
            colored_old = colorize(old_str, line_color)
            colored_new = colorize(new_str, line_color)
            colored_pipe1 = colorize("|", pipe_color)
            colored_pipe2 = colorize("|", pipe_color)
            colored_marker = colorize(marker, formatting_color)
            "#{colored_old}#{colored_pipe1}#{colored_new}#{colored_marker} #{colored_pipe2} #{content}"
          else
            "#{old_str}|#{new_str} #{marker} | #{content}"
          end
        end

        def render_informative_added(diff_line, line_num)
          marker = ">"
          content = diff_line.content
          content_color = theme_color(:diff, :informative, :content) || :cyan

          old_str = blank_line_num
          new_str = format_line_num(line_num)

          if use_color
            line_color = structure_color(:line_number) || :yellow
            pipe_color = structure_color(:pipe) || :yellow
            colored_old = colorize(old_str, line_color)
            colored_new = colorize(new_str, line_color)
            colored_pipe1 = colorize("|", pipe_color)
            colored_pipe2 = colorize("|", pipe_color)
            colored_marker = colorize(marker, content_color)
            "#{colored_old}#{colored_pipe1}#{colored_new}#{colored_marker} #{colored_pipe2} #{content}"
          else
            "#{old_str}|#{new_str} #{marker} | #{content}"
          end
        end

        def render_normative_added(diff_line, line_num)
          marker = "+"
          content = diff_line.content
          content_color = theme_color(:diff, :added, :content) || :green

          old_str = blank_line_num
          new_str = format_line_num(line_num)

          if use_color
            line_color = structure_color(:line_number) || :yellow
            pipe_color = structure_color(:pipe) || :yellow
            colored_old = colorize(old_str, line_color)
            colored_new = colorize(new_str, line_color)
            colored_pipe1 = colorize("|", pipe_color)
            colored_pipe2 = colorize("|", pipe_color)
            colored_marker = colorize(marker, content_color)
            "#{colored_old}#{colored_pipe1}#{colored_new}#{colored_marker} #{colored_pipe2} #{content}"
          else
            "#{old_str}|#{new_str} #{marker} | #{content}"
          end
        end

        # Render with character-level highlighting for added lines (new side)
        def render_with_char_ranges(diff_line, line_num)
          # Get ranges for the new side (added lines use text2 ranges)
          ranges = diff_line.new_char_ranges.select(&:new_side?)
          return render_normative_added(diff_line, line_num) if ranges.empty?

          line_text = diff_line.content
          formatting = diff_line.formatting?
          informative = diff_line.informative?

          # Build highlighted content from ranges
          parts = []
          cursor = 0

          formatting_style = theme_style(:diff, :formatting,
                                         :content) || { color: :bright_blue }
          added_style = theme_style(:diff, :added, :content) || {}
          informative_style = theme_style(:diff, :informative, :content) || {}

          # Sort ranges by start_col for consistent rendering
          sorted_ranges = ranges.sort_by(&:start_col)

          sorted_ranges.each do |cr|
            # Fill in any gap before this range as unchanged text
            if cursor < cr.start_col
              gap = line_text[cursor...cr.start_col]
              parts << apply_selective_visualization(gap)
            end

            segment = cr.extract_from(line_text)
            next if segment.nil? || segment.empty?

            parts << if formatting
                       # Formatting-only change: only highlight CHANGED segments.
                       case cr.status
                       when :changed_new
                         apply_style_only(segment, formatting_style)
                       else
                         apply_selective_visualization(segment)
                       end
                     elsif informative
                       # Informative change
                       case cr.status
                       when :changed_new
                         apply_style_only(segment, informative_style)
                       else
                         apply_selective_visualization(segment)
                       end
                     else
                       # Normative change: use theme added colors
                       case cr.status
                       when :changed_new
                         apply_style_only(segment, added_style)
                       else
                         apply_selective_visualization(segment)
                       end
                     end

            cursor = cr.end_col
          end

          # Fill in any remaining text after the last range
          if cursor < line_text.length
            tail = line_text[cursor..]
            parts << apply_selective_visualization(tail)
          end

          highlighted_content = parts.join

          # Build the full line
          old_str = blank_line_num
          new_str = format_line_num(line_num)

          marker = if formatting
                     "]"
                   elsif informative
                     ">"
                   else
                     "+"
                   end

          if use_color
            line_color = structure_color(:line_number) || :yellow
            pipe_color = structure_color(:pipe) || :yellow
            marker_color = if formatting
                             theme_color(:diff, :formatting,
                                         :marker) || :bright_blue
                           elsif informative
                             theme_color(:diff, :informative, :marker) || :cyan
                           else
                             theme_color(:diff, :added, :marker) || :green
                           end

            colored_old = colorize(old_str, line_color)
            colored_new = colorize(new_str, line_color)
            colored_pipe1 = colorize("|", pipe_color)
            colored_pipe2 = colorize("|", pipe_color)
            colored_marker = colorize(marker, marker_color)
            "#{colored_old}#{colored_pipe1}#{colored_new}#{colored_marker} #{colored_pipe2} #{highlighted_content}"
          else
            "#{old_str}|#{new_str} #{marker} | #{highlighted_content}"
          end
        end
      end

      # Factory for creating the appropriate renderer for a DiffLine
      class LineRendererFactory
        # @param theme [Hash] The resolved theme hash
        # @param use_color [Boolean] Whether to apply ANSI colors
        # @param line_num_width [Integer] Width for line number padding
        def initialize(theme:, use_color:, line_num_width:)
          @theme = theme
          @use_color = use_color
          @line_num_width = line_num_width
        end

        # Create a renderer for the given diff line
        # @param diff_line [DiffLine]
        # @return [LineRenderer] Appropriate renderer instance
        def for_line(diff_line)
          case diff_line.type
          when :reflow_summary
            ReflowSummaryLineRenderer.new(
              theme: @theme,
              use_color: @use_color,
              line_num_width: @line_num_width,
            )
          when :unchanged
            UnchangedLineRenderer.new(
              theme: @theme,
              use_color: @use_color,
              line_num_width: @line_num_width,
            )
          when :removed
            RemovedLineRenderer.new(
              theme: @theme,
              use_color: @use_color,
              line_num_width: @line_num_width,
            )
          when :added
            AddedLineRenderer.new(
              theme: @theme,
              use_color: @use_color,
              line_num_width: @line_num_width,
            )
          else
            raise ArgumentError, "Unknown diff line type: #{diff_line.type}"
          end
        end
      end
    end
  end
end
