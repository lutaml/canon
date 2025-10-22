# frozen_string_literal: true

require "paint"
require "yaml"
require_relative "comparison"
require_relative "diff/diff_block"
require_relative "diff/diff_context"
require_relative "diff/diff_report"
require_relative "diff_formatter/debug_output"

module Canon
  # Formatter for displaying semantic differences with color support
  #
  # This is a pure orchestrator class that delegates formatting to mode-specific
  # and format-specific formatters. It provides a unified interface for generating
  # both by-line and by-object diffs across multiple formats (XML, HTML, JSON, YAML).
  #
  # == Architecture
  #
  # DiffFormatter follows the orchestrator pattern with MECE (Mutually Exclusive,
  # Collectively Exhaustive) delegation:
  #
  # 1. **Mode Selection**: Chooses by-line or by-object visualization
  # 2. **Format Delegation**: Dispatches to format-specific formatter
  # 3. **Customization**: Applies color, context, and visualization options
  #
  # == Diff Modes
  #
  # **By-Object Mode** (default for XML/JSON/YAML):
  # - Tree-based semantic diff
  # - Shows only what changed in the structure
  # - Visual tree with box-drawing characters
  # - Best for configuration files and structured data
  #
  # **By-Line Mode** (default for HTML):
  # - Traditional line-by-line diff
  # - Shows changes in document order with context
  # - Syntax-aware token highlighting
  # - Best for markup and when line context matters
  #
  # == Visualization Features
  #
  # - **Color support**: Red (deletions), green (additions), yellow (structure), cyan (informative)
  # - **Whitespace visualization**: Makes invisible characters visible
  # - **Context lines**: Shows unchanged lines around changes
  # - **Diff grouping**: Groups nearby changes into blocks
  # - **Character map customization**: CJK-safe Unicode symbols
  #
  # == Usage
  #
  #   # Basic usage
  #   formatter = Canon::DiffFormatter.new(use_color: true, mode: :by_object)
  #   output = formatter.format(differences, :xml, doc1: xml1, doc2: xml2)
  #
  #   # With options
  #   formatter = Canon::DiffFormatter.new(
  #     use_color: true,
  #     mode: :by_line,
  #     context_lines: 5,
  #     diff_grouping_lines: 10,
  #     show_diffs: :normative
  #   )
  #
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

    # Load character map from YAML file
    #
    # @return [Hash] Hash with :visualization_map, :category_map, :category_names
    def self.load_character_map
      yaml_path = File.join(__dir__, "diff_formatter", "character_map.yml")
      data = YAML.load_file(yaml_path)

      visualization_map = {}
      category_map = {}
      character_metadata = {}

      data["characters"].each do |char_data|
        # Get character from either unicode code point or character field
        char = if char_data["unicode"]
                 # Convert hex string to character
                 [char_data["unicode"].to_i(16)].pack("U")
               else
                 # Use character field directly (handles \n, \r, \t, etc.)
                 char_data["character"]
               end

        vis = char_data["visualization"]
        category = char_data["category"].to_sym
        name = char_data["name"]

        visualization_map[char] = vis
        category_map[char] = category
        character_metadata[char] = {
          visualization: vis,
          category: category,
          name: name,
        }
      end

      category_names = {}
      data["category_names"].each do |key, value|
        category_names[key.to_sym] = value
      end

      {
        visualization_map: visualization_map,
        category_map: category_map,
        category_names: category_names,
        character_metadata: character_metadata,
      }
    end

    # Lazily load and cache character map data
    def self.character_map_data
      @character_map_data ||= load_character_map
    end

    # Default character visualization map (loaded from YAML)
    DEFAULT_VISUALIZATION_MAP = character_map_data[:visualization_map].freeze

    # Character category map (loaded from YAML)
    CHARACTER_CATEGORY_MAP = character_map_data[:category_map].freeze

    # Category display names (loaded from YAML)
    CHARACTER_CATEGORY_NAMES = character_map_data[:category_names].freeze

    # Character metadata including names (loaded from YAML)
    CHARACTER_METADATA = character_map_data[:character_metadata].freeze

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
                   diff_grouping_lines: nil, visualization_map: nil,
                   character_map_file: nil, character_definitions: nil,
                   show_diffs: :all, verbose_diff: false)
      @use_color = use_color
      @mode = mode
      @context_lines = context_lines
      @diff_grouping_lines = diff_grouping_lines
      @show_diffs = show_diffs
      @verbose_diff = verbose_diff
      @visualization_map = build_visualization_map(
        visualization_map: visualization_map,
        character_map_file: character_map_file,
        character_definitions: character_definitions,
      )
    end

    # Merge custom character visualization map with defaults
    #
    # @param custom_map [Hash, nil] Custom character mappings
    # @return [Hash] Merged character visualization map
    def self.merge_visualization_map(custom_map)
      DEFAULT_VISUALIZATION_MAP.merge(custom_map || {})
    end

    # Load character map from custom YAML file
    #
    # @param file_path [String] Path to YAML file with character definitions
    # @return [Hash] Character visualization map
    def self.load_custom_character_map(file_path)
      data = YAML.load_file(file_path)
      visualization_map = {}

      data["characters"].each do |char_data|
        # Get character from either unicode code point or character field
        char = if char_data["unicode"]
                 [char_data["unicode"].to_i(16)].pack("U")
               else
                 char_data["character"]
               end

        visualization_map[char] = char_data["visualization"]
      end

      visualization_map
    end

    # Build character definition from hash
    #
    # @param definition [Hash] Character definition with keys (matching YAML format):
    #   - :character or :unicode (required)
    #   - :visualization (required)
    #   - :category (required)
    #   - :name (required)
    # @return [Hash] Single-entry visualization map
    def self.build_character_definition(definition)
      # Validate required fields
      char = if definition[:unicode]
               [definition[:unicode].to_i(16)].pack("U")
             elsif definition[:character]
               definition[:character]
             else
               raise ArgumentError,
                     "Character definition must include :character or :unicode"
             end

      unless definition[:visualization]
        raise ArgumentError, "Character definition must include :visualization"
      end

      unless definition[:category]
        raise ArgumentError, "Character definition must include :category"
      end

      unless definition[:name]
        raise ArgumentError, "Character definition must include :name"
      end

      { char => definition[:visualization] }
    end

    # Format differences array for display
    #
    # @param differences [Array] Array of difference hashes
    # @param format [Symbol] Format type (:xml, :html, :json, :yaml)
    # @param doc1 [String, nil] First document content (for by-line mode)
    # @param doc2 [String, nil] Second document content (for by-line mode)
    # @param html_version [Symbol, nil] HTML version (:html4 or :html5)
    # @return [String] Formatted output
    def format(differences, format, doc1: nil, doc2: nil, html_version: nil)
      # In by-line mode with doc1/doc2, always perform diff regardless of differences
      if @mode == :by_line && doc1 && doc2
        return by_line_diff(doc1, doc2, format: format,
                                        html_version: html_version,
                                        differences: differences)
      end

      # Check if no differences (handle both ComparisonResult and legacy Array)
      no_diffs = if differences.respond_to?(:equivalent?)
                   # ComparisonResult object (production path)
                   differences.equivalent?
                 else
                   # Legacy Array (for low-level tests)
                   differences.empty?
                 end
      return success_message if no_diffs

      case @mode
      when :by_line
        by_line_diff(doc1, doc2, format: format, html_version: html_version,
                                 differences: differences)
      else
        by_object_diff(differences, format)
      end
    end

    # Format comparison result from Canon::Comparison.equivalent?
    # This is the single entry point for generating diffs from comparison results
    #
    # @param comparison_result [ComparisonResult, Hash, Array, Boolean] Result from Canon::Comparison.equivalent?
    # @param expected [Object] Expected value
    # @param actual [Object] Actual value
    # @return [String] Formatted diff output
    def format_comparison_result(comparison_result, expected, actual)
      # Detect format from expected content
      format = Canon::Comparison.send(:detect_format, expected)

      formatter_options = {
        use_color: @use_color,
        mode: @mode,
        context_lines: @context_lines,
        diff_grouping_lines: @diff_grouping_lines,
        show_diffs: @show_diffs,
        verbose_diff: @verbose_diff,
      }

      output = []

      # 1. CANON VERBOSE tables (ONLY if CANON_VERBOSE=1)
      verbose_tables = DebugOutput.verbose_tables_only(
        comparison_result,
        formatter_options,
      )
      output << verbose_tables unless verbose_tables.empty?

      # 2. Semantic Diff Report (ALWAYS if diffs exist)
      if comparison_result.is_a?(Canon::Comparison::ComparisonResult) &&
          comparison_result.differences.any?
        require_relative "diff_formatter/diff_detail_formatter"
        output << DiffDetailFormatter.format_report(
          comparison_result.differences,
          use_color: @use_color,
        )
      end

      # 3. Main diff output (by-line or by-object) - ALWAYS

      # Check if comparison result is a ComparisonResult object
      if comparison_result.is_a?(Canon::Comparison::ComparisonResult)
        # Use preprocessed strings from comparison - avoids re-preprocessing
        doc1, doc2 = comparison_result.preprocessed_strings
        differences = comparison_result.differences
        html_version = comparison_result.html_version
      elsif comparison_result.is_a?(Hash) && comparison_result[:preprocessed]
        # Legacy Hash format - Use preprocessed strings from comparison
        doc1, doc2 = comparison_result[:preprocessed]
        differences = comparison_result[:differences]
        html_version = comparison_result[:html_version]
      else
        # Legacy path: normalize content for display
        doc1, doc2 = normalize_content_for_display(expected, actual, format)
        # comparison_result is an array of differences when verbose: true
        differences = comparison_result.is_a?(Array) ? comparison_result : []
        html_version = nil
      end

      # Generate diff using existing format method
      output << format(differences, format, doc1: doc1, doc2: doc2,
                                            html_version: html_version)

      output.compact.join("\n")
    end

    private

    # Normalize content for display in diffs
    #
    # @param expected [Object] Expected value
    # @param actual [Object] Actual value
    # @param format [Symbol] Detected format
    # @return [Array<String, String>] Normalized [expected, actual] strings
    def normalize_content_for_display(expected, actual, format)
      case format
      when :xml
        [
          Canon::Xml::C14n.canonicalize(expected, with_comments: false).gsub(
            /></, ">\n<"
          ),
          Canon::Xml::C14n.canonicalize(actual, with_comments: false).gsub(
            /></, ">\n<"
          ),
        ]
      when :html
        require "nokogiri"
        [
          parse_and_format_html(expected),
          parse_and_format_html(actual),
        ]
      when :json
        [
          Canon.format(expected, :json),
          Canon.format(actual, :json),
        ]
      when :yaml
        [
          Canon.format(expected, :yaml),
          Canon.format(actual, :yaml),
        ]
      when :ruby_object
        # For Ruby objects, format as JSON for display
        require "json"
        [
          JSON.pretty_generate(expected),
          JSON.pretty_generate(actual),
        ]
      else
        # Default case including :string format
        [expected.to_s, actual.to_s]
      end
    end

    # Parse and format HTML for display
    #
    # @param html [Object] HTML content
    # @return [String] Formatted HTML
    def parse_and_format_html(html)
      return html.to_html if html.is_a?(Nokogiri::HTML::Document) ||
        html.is_a?(Nokogiri::HTML5::Document)

      require "nokogiri"
      Nokogiri::HTML(html).to_html
    rescue StandardError
      html.to_s
    end

    # Build the final visualization map from various customization options
    #
    # @param visualization_map [Hash, nil] Complete custom visualization map
    # @param character_map_file [String, nil] Path to custom YAML file
    # @param character_definitions [Array<Hash>, nil] Individual character definitions
    # @return [Hash] Final visualization map
    def build_visualization_map(visualization_map: nil, character_map_file: nil,
                                character_definitions: nil)
      # Priority order:
      # 1. If visualization_map is provided, use it as complete replacement
      # 2. Otherwise, start with defaults and apply customizations

      return visualization_map if visualization_map

      # Start with defaults
      result = DEFAULT_VISUALIZATION_MAP.dup

      # Apply custom file if provided
      if character_map_file
        custom_map = self.class.load_custom_character_map(character_map_file)
        result.merge!(custom_map)
      end

      # Apply individual character definitions if provided
      character_definitions&.each do |definition|
        char_map = self.class.build_character_definition(definition)
        result.merge!(char_map)
      end

      result
    end

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
        visualization_map: @visualization_map,
      )

      output << formatter.format(differences, format)

      output.join("\n")
    end

    # Generate by-line diff
    # Delegates to format-specific by-line formatters
    def by_line_diff(doc1, doc2, format: :xml, html_version: nil,
differences: [])
      require_relative "diff_formatter/by_line/base_formatter"

      # For HTML format, use html_version if provided, otherwise default to :html4
      if format == :html && html_version
        format = html_version # Use :html4 or :html5
      end

      # Format display name for header
      format_name = format.to_s.upcase

      output = []
      output << colorize("Line-by-line diff (#{format_name} mode):", :cyan,
                         :bold)

      return output.join("\n") if doc1.nil? || doc2.nil?

      # Delegate to format-specific formatter
      formatter = ByLine::BaseFormatter.for_format(
        format,
        use_color: @use_color,
        context_lines: @context_lines,
        diff_grouping_lines: @diff_grouping_lines,
        visualization_map: @visualization_map,
        show_diffs: @show_diffs,
        differences: differences,
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
