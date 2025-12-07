# frozen_string_literal: true

require "unicode/name"

module Canon
  class DiffFormatter
    # Module for building Unicode character visualization legends
    module Legend
      # Detect non-ASCII characters in text and return their information
      #
      # @param text [String] Text to analyze
      # @param visualization_map [Hash] Character visualization map
      # @return [Hash] Hash of characters with their metadata
      def self.detect_non_ascii(text, visualization_map)
        detected = {}
        category_map = DiffFormatter::CHARACTER_CATEGORY_MAP
        metadata = DiffFormatter::CHARACTER_METADATA

        text.each_char do |char|
          next if char.ord <= 127
          next if detected.key?(char)

          visualization = visualization_map.fetch(char, char)
          next if visualization == char # Skip if no visualization mapping

          codepoint = format("U+%04X", char.ord)

          # Use name from metadata if available, otherwise use Unicode::Name
          name = if metadata[char] && metadata[char][:name]
                   metadata[char][:name]
                 else
                   Unicode::Name.of(char) || "UNKNOWN"
                 end

          detected[char] = {
            visualization: visualization,
            codepoint: codepoint,
            name: name,
            category: category_map.fetch(char, :control),
          }
        end

        detected
      end

      # Build formatted legend from detected characters
      #
      # @param detected_chars [Hash] Hash from detect_non_ascii
      # @param use_color [Boolean] Whether to use colors
      # @return [String, nil] Formatted legend or nil if no characters
      def self.build_legend(detected_chars, use_color: true)
        return nil if detected_chars.empty?

        # Group characters by category
        grouped = detected_chars.group_by { |_char, info| info[:category] }

        output = []
        separator = "━" * 60

        output << colorize("Character Visualization Legend:", :cyan, :bold,
                           use_color)
        output << colorize(separator, :cyan, :bold, use_color)

        # Display each category
        category_names = DiffFormatter::CHARACTER_CATEGORY_NAMES
        category_names.each do |category_key, category_name|
          chars = grouped[category_key]
          next unless chars

          output << colorize("#{category_name}:", :yellow, :bold, use_color)

          chars.sort_by { |char, _info| char.ord }.each do |char, info|
            # Format: '⏓': U+2005 (' ') Four-Per-Em Space
            vis = info[:visualization]
            code = info[:codepoint]
            name = format_name(info[:name])

            # Show original character in quotes, handling special cases
            original = format_original_char(char)

            line = "  '#{vis}': #{code} ('#{original}') #{name}"
            output << (use_color ? line : line)
          end
          output << ""
        end

        output << colorize(separator, :cyan, :bold, use_color)
        output.join("\n")
      end

      # Build diff symbol legend
      #
      # @param use_color [Boolean] Whether to use colors
      # @return [String] Formatted diff symbol legend
      def self.build_diff_symbol_legend(use_color: true)
        output = []
        separator = "━" * 60

        output << colorize("Diff Symbol Legend:", :cyan, :bold, use_color)
        output << colorize(separator, :cyan, :bold, use_color)

        # Normative changes
        output << colorize("Normative Changes (affect equivalence):", :yellow, :bold, use_color)
        output << "  #{colorize('-', :red, :bold, use_color)}: Line removed (normative difference)"
        output << "  #{colorize('+', :green, :bold, use_color)}: Line added (normative difference)"
        output << ""

        # Informative changes
        output << colorize("Informative Changes (do not affect equivalence):", :yellow, :bold, use_color)
        output << "  #{colorize('~', :cyan, :bold, use_color)}: Line differs (informative only)"
        output << ""

        output << colorize(separator, :cyan, :bold, use_color)
        output.join("\n")
      end

      # Format character name for display
      #
      # @param name [String] Unicode character name
      # @return [String] Formatted name
      def self.format_name(name)
        # Convert from "FOUR-PER-EM SPACE" to "Four-Per-Em Space"
        name.split(/[-\s]/).map do |word|
          if word.length <= 2
            word.upcase
          else
            word.capitalize
          end
        end.join("-").gsub("-", "-")
      end

      # Format original character for display in legend
      #
      # @param char [String] Original character
      # @return [String] Formatted for display
      def self.format_original_char(char)
        case char
        when "\n"
          "\\n"
        when "\r"
          "\\r"
        when "\t"
          "\\t"
        when "\u0000"
          "\\0"
        else
          char
        end
      end

      # Colorize text if color is enabled
      #
      # @param text [String] Text to colorize
      # @param colors [Array<Symbol>] Colors to apply
      # @param use_color [Boolean] Whether to use colors
      # @return [String] Colorized or plain text
      def self.colorize(text, *colors, use_color)
        return text unless use_color

        require "paint"
        "\e[0m#{Paint[text, *colors]}"
      end

      private_class_method :format_name, :format_original_char, :colorize
    end
  end
end
