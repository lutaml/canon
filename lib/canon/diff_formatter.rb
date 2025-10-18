# frozen_string_literal: true

require "paint"
require_relative "diff/diff_block"
require_relative "diff/diff_context"
require_relative "diff/diff_report"

module Canon
  # Formatter for displaying semantic differences with color support
  # This is a pure orchestrator that delegates to mode-specific formatters
  class DiffFormatter
    # Namespace for by-object mode formatters
    module ByObject
      autoload :BaseFormatter, "canon/diff_formatter/by_object/base_formatter"
      autoload :XmlFormatter, "canon/diff_formatter/by_object/xml_formatter"
      autoload :JsonFormatter, "canon/diff_formatter/by_object/json_formatter"
      autoload :YamlFormatter, "canon/diff_formatter/by_object/yaml_formatter"
    end

    # Namespace for by-line mode formatters
    module ByLine
      autoload :BaseFormatter, "canon/diff_formatter/by_line/base_formatter"
      autoload :SimpleFormatter, "canon/diff_formatter/by_line/simple_formatter"
      autoload :XmlFormatter, "canon/diff_formatter/by_line/xml_formatter"
      autoload :JsonFormatter, "canon/diff_formatter/by_line/json_formatter"
      autoload :YamlFormatter, "canon/diff_formatter/by_line/yaml_formatter"
    end

    # Default character visualization map (CJK-safe)
    DEFAULT_VISUALIZATION_MAP = {
      # Common whitespace characters
      " " => "░", # U+2591 Light Shade (regular space)
      "\t" => "⇥", # U+21E5 Rightwards Arrow to Bar (tab)
      "\u00A0" => "␣", # U+2423 Open Box (non-breaking space)

      # Line endings
      "\n" => "↵",   # U+21B5 Downwards Arrow with Corner Leftwards (LF)
      "\r" => "⏎",   # U+23CE Return Symbol (CR)
      "\r\n" => "↵", # Windows line ending (CRLF)
      "\u0085" => "⏎",   # U+0085 Next Line (NEL)
      "\u2028" => "⤓",   # U+2913 Downwards Arrow to Bar (line separator)
      "\u2029" => "⤓",   # U+2913 Downwards Arrow to Bar (paragraph separator)

      # Unicode spaces (using box characters for CJK safety)
      "\u2002" => "▭",   # U+25AD White Rectangle (en space)
      "\u2003" => "▬",   # U+25AC Black Rectangle (em space)
      "\u2005" => "⏓",   # U+23D3 Metrical Short Over Long (four-per-em space)
      "\u2006" => "⏕",   # U+23D5 Metrical Two Shorts Over Long (six-per-em space)
      "\u2009" => "▯",   # U+25AF White Vertical Rectangle (thin space)
      "\u200A" => "▮",   # U+25AE Black Vertical Rectangle (hair space)
      "\u2007" => "□",   # U+25A1 White Square (figure space)
      "\u202F" => "▫",   # U+25AB White Small Square (narrow no-break space)
      "\u205F" => "▭",   # U+25AD White Rectangle (medium mathematical space)
      "\u3000" => "⎵",   # U+23B5 Bottom Square Bracket (ideographic space)
      "\u303F" => "⏑",   # U+23D1 Metrical Breve (ideographic half space)

      # Zero-width characters (using arrows)
      "\u200B" => "→",   # U+2192 Rightwards Arrow (zero-width space)
      "\u200C" => "↛",   # U+219B Rightwards Arrow with Stroke (zero-width non-joiner)
      "\u200D" => "⇢",   # U+21E2 Rightwards Dashed Arrow (zero-width joiner)
      "\uFEFF" => "⇨",   # U+21E8 Rightwards White Arrow (zero-width no-break space/BOM)

      # Directional markers
      "\u200E" => "⟹",   # U+27F9 Long Rightwards Double Arrow (LTR mark)
      "\u200F" => "⟸",   # U+27F8 Long Leftwards Double Arrow (RTL mark)
      "\u202A" => "⇒",   # U+21D2 Rightwards Double Arrow (LTR embedding)
      "\u202B" => "⇐",   # U+21D0 Leftwards Double Arrow (RTL embedding)
      "\u202C" => "↔",   # U+2194 Left Right Arrow (pop directional formatting)
      "\u202D" => "⇉",   # U+21C9 Rightwards Paired Arrows (LTR override)
      "\u202E" => "⇇",   # U+21C7 Leftwards Paired Arrows (RTL override)

      # Control characters
      "\u0000" => "␀", # U+2400 Symbol for Null
      "\u00AD" => "­‐", # U+2010 Hyphen (soft hyphen)
      "\u0008" => "␈",   # U+2408 Symbol for Backspace)
      "\u007F" => "␡",   # U+2421 Symbol for Delete
    }.freeze

    # Map difference codes to human-readable descriptions
    DIFF_DESCRIPTIONS = {
      Comparison::EQUIVALENT => "Equivalent",
      Comparison::MISSING_ATTRIBUTE => "Missing attribute",
      Comparison::MISSING_NODE => "Missing node",
      Comparison::UNEQUAL_ATTRIBUTES => "Unequal attributes",
      Comparison::UNEQUAL_COMMENTS => "Unequal comments",
      Comparison::UNEQUAL_DOCUMENTS => "Unequal documents",
      Comparison::UNEQUAL_ELEMENTS => "Unequal elements",
      Comparison::UNEQUAL_NODES_TYPES => "Unequal node types",
      Comparison::UNEQUAL_TEXT_CONTENTS => "Unequal text contents",
      Comparison::MISSING_HASH_KEY => "Missing hash key",
      Comparison::UNEQUAL_HASH_VALUES => "Unequal hash values",
      Comparison::UNEQUAL_ARRAY_LENGTHS => "Unequal array lengths",
      Comparison::UNEQUAL_ARRAY_ELEMENTS => "Unequal array elements",
      Comparison::UNEQUAL_TYPES => "Unequal types",
      Comparison::UNEQUAL_PRIMITIVES => "Unequal primitive values",
    }.freeze

    def initialize(use_color: true, mode: :by_object, context_lines: 3,
                   diff_grouping_lines: nil, visualization_map: nil)
      @use_color = use_color
      @mode = mode
      @context_lines = context_lines
      @diff_grouping_lines = diff_grouping_lines
      @visualization_map = visualization_map || DEFAULT_VISUALIZATION_MAP
    end

    # Merge custom character visualization map with defaults
    #
    # @param custom_map [Hash, nil] Custom character mappings
    # @return [Hash] Merged character visualization map
    def self.merge_visualization_map(custom_map)
      DEFAULT_VISUALIZATION_MAP.merge(custom_map || {})
    end

    # Format differences array for display
    #
    # @param differences [Array] Array of difference hashes
    # @param format [Symbol] Format type (:xml, :html, :json, :yaml)
    # @param doc1 [String, nil] First document content (for by-line mode)
    # @param doc2 [String, nil] Second document content (for by-line mode)
    # @return [String] Formatted output
    def format(differences, format, doc1: nil, doc2: nil)
      # In by-line mode with doc1/doc2, always perform diff regardless of differences array
      if @mode == :by_line && doc1 && doc2
        return by_line_diff(doc1, doc2, format: format)
      end

      if differences.empty?
        return success_message
      end

      case @mode
      when :by_line
        by_line_diff(doc1, doc2, format: format)
      else
        by_object_diff(differences, format)
      end
    end

    private

    # Generate success message based on mode
    def success_message
      emoji = @use_color ? "✅ " : ""
      message = case @mode
                when :by_line
                  "Files are identical"
                else
                  "Files are semantically equivalent"
                end

      colorize("#{emoji}#{message}\n", :green, :bold)
    end

    # Generate by-object diff with tree visualization
    # Delegates to format-specific by-object formatters
    def by_object_diff(differences, format)
      require_relative "diff_formatter/by_object/base_formatter"

      output = []
      output << colorize("Visual Diff:", :cyan, :bold)

      # Delegate to format-specific formatter
      formatter = ByObject::BaseFormatter.for_format(
        format,
        use_color: @use_color,
        visualization_map: @visualization_map
      )

      output << formatter.format(differences, format)

      output.join("\n")
    end

    # Generate by-line diff
    # Delegates to format-specific by-line formatters
    def by_line_diff(doc1, doc2, format: :xml)
      require_relative "diff_formatter/by_line/base_formatter"

      output = []
      output << colorize("Line-by-line diff:", :cyan, :bold)

      return output.join("\n") if doc1.nil? || doc2.nil?

      # Delegate to format-specific formatter
      formatter = ByLine::BaseFormatter.for_format(
        format,
        use_color: @use_color,
        context_lines: @context_lines,
        diff_grouping_lines: @diff_grouping_lines,
        visualization_map: @visualization_map
      )

      output << formatter.format(doc1, doc2)

      output.join("\n")
    end

    # Colorize text if color is enabled
    # RSpec-aware: resets any existing ANSI codes before applying new colors
    def colorize(text, *colors)
      return text unless @use_color

      # Reset ANSI codes first to prevent RSpec's initial red from interfering
      "\e[0m#{Paint[text, *colors]}"
    end
  end
end
