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

    # rubocop:disable Metrics/ParameterLists
    def initialize(use_color: true, mode: :by_object, context_lines: 3,
                   diff_grouping_lines: nil, visualization_map: nil,
                   character_map_file: nil, character_definitions: nil,
                   show_diffs: :all, verbose_diff: false,
                   show_raw_inputs: false, show_raw_expected: false,
                   show_raw_received: false,
                   show_preprocessed_inputs: false,
                   show_preprocessed_expected: false,
                   show_preprocessed_received: false,
                   show_prettyprint_inputs: false,
                   show_prettyprint_expected: false,
                   show_prettyprint_received: false,
                   show_line_numbered_inputs: false,
                   character_visualization: true,
                   display_preprocessing: :none,
                   pretty_printer_indent: 2,
                   pretty_printer_indent_type: :space,
                   preserve_whitespace_elements: [],
                   collapse_whitespace_elements: [],
                   strip_whitespace_elements: [],
                   pretty_printed_expected: false,
                   pretty_printed_received: false,
                   pretty_printer_sort_attributes: false,
                   compact_semantic_report: false,
                   expand_difference: false,
                   diff_mode: :separate, legacy_terminal: false)
      # rubocop:enable Metrics/ParameterLists
      @use_color = use_color
      @mode = mode
      @context_lines = context_lines
      @diff_grouping_lines = diff_grouping_lines
      @show_diffs = show_diffs
      @verbose_diff = verbose_diff
      @show_raw_inputs = show_raw_inputs
      @show_raw_expected = show_raw_expected
      @show_raw_received = show_raw_received
      @show_preprocessed_inputs = show_preprocessed_inputs
      @show_preprocessed_expected = show_preprocessed_expected
      @show_preprocessed_received = show_preprocessed_received
      @show_prettyprint_inputs = show_prettyprint_inputs
      @show_prettyprint_expected = show_prettyprint_expected
      @show_prettyprint_received = show_prettyprint_received
      @show_line_numbered_inputs = show_line_numbered_inputs
      @character_visualization = character_visualization
      @display_preprocessing = display_preprocessing
      @pretty_printer_indent = pretty_printer_indent
      @pretty_printer_indent_type = pretty_printer_indent_type
      @preserve_whitespace_elements = Array(preserve_whitespace_elements).map(&:to_s)
      @collapse_whitespace_elements = Array(collapse_whitespace_elements).map(&:to_s)
      @strip_whitespace_elements = Array(strip_whitespace_elements).map(&:to_s)
      @pretty_printed_expected = pretty_printed_expected
      @pretty_printed_received = pretty_printed_received
      @pretty_printer_sort_attributes = pretty_printer_sort_attributes
      @compact_semantic_report = compact_semantic_report
      @expand_difference = expand_difference
      @diff_mode = legacy_terminal ? :separate : diff_mode
      @legacy_terminal = legacy_terminal
      @visualization_map = build_visualization_map(
        character_visualization: character_visualization,
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
      # In by-line mode, always use by-line diff
      if @mode == :by_line && doc1 && doc2
        return by_line_diff(doc1, doc2, format: format,
                                        html_version: html_version,
                                        differences: differences)
      end

      # In pretty_diff mode, always use text-LCS diff (bypasses DiffNodeMapper).
      # pretty_diff_format handles nil doc1/doc2 itself (emits header only).
      if @mode == :pretty_diff
        return pretty_diff_format(doc1, doc2, format: format)
      end

      no_diffs = if differences.respond_to?(:equivalent?)
                   differences.equivalent?
                 else
                   differences.empty?
                 end
      return success_message if no_diffs

      case @mode
      when :by_line
        by_line_diff(doc1, doc2, format: format, html_version: html_version,
                                 differences: differences)
      when :pretty_diff
        pretty_diff_format(doc1, doc2, format: format)
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
      format = Canon::Comparison::FormatDetector.detect(expected)

      formatter_options = {
        use_color: @use_color,
        mode: @mode,
        context_lines: @context_lines,
        diff_grouping_lines: @diff_grouping_lines,
        show_diffs: @show_diffs,
        verbose_diff: @verbose_diff,
      }

      output = []

      # Display the algorithm being used
      if comparison_result.is_a?(Canon::Comparison::ComparisonResult)
        algorithm_name = case comparison_result.algorithm
                         when :semantic
                           "SEMANTIC TREE DIFF"
                         else
                           "DOM DIFF"
                         end
        output << colorize("Algorithm: #{algorithm_name}", :cyan, :bold)
        output << "" # Blank line for spacing
      end

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
          show_diffs: @show_diffs,
          compact_semantic_report: @compact_semantic_report,
          expand_difference: @expand_difference,
        )
      end

      # verbose_diff / show_raw_inputs shows both sides as a convenience shorthand.
      # show_raw_expected / show_raw_received give per-side control.
      combined_raw = @verbose_diff || @show_raw_inputs
      show_raw_exp = combined_raw || @show_raw_expected
      show_raw_rec = combined_raw || @show_raw_received
      verbose      = show_raw_exp || show_raw_rec
      # verbose_diff / show_preprocessed_inputs shows both sides as a shorthand.
      # show_preprocessed_expected / show_preprocessed_received give per-side control.
      combined_prep = @verbose_diff || @show_preprocessed_inputs
      show_prep_exp = combined_prep || @show_preprocessed_expected
      show_prep_rec = combined_prep || @show_preprocessed_received
      show_prep = show_prep_exp || show_prep_rec
      show_line = @verbose_diff || @show_line_numbered_inputs

      # 3. Raw/Original Input Display (when show_raw_inputs/show_raw_expected/show_raw_received enabled)
      if verbose && comparison_result.is_a?(Canon::Comparison::ComparisonResult)
        original1, original2 = comparison_result.original_strings
        if original1 && original2
          output << format_raw_inputs(original1, original2,
                                      show_expected: show_raw_exp,
                                      show_received: show_raw_rec)
        end
      end

      # 4. Preprocessed Input Display (when show_preprocessed_inputs/expected/received enabled)
      if show_prep && comparison_result.is_a?(Canon::Comparison::ComparisonResult)
        preprocessed1, preprocessed2 = comparison_result.preprocessed_strings
        if preprocessed1 && preprocessed2
          preprocessing_info = comparison_result.match_options&.dig(:match,
                                                                    :preprocessing)
          output << format_preprocessed_inputs(preprocessed1, preprocessed2,
                                               preprocessing_info,
                                               show_expected: show_prep_exp,
                                               show_received: show_prep_rec)
        end
      end

      # 4.5. Pretty-printed Input Display (when show_prettyprint_inputs/expected/received enabled)
      # Pretty-prints the ORIGINAL strings (not preprocessed) through PrettyPrinter::Xml/Html
      # with NO character visualization — output is plain ASCII suitable for copy-pasting
      # into RSpec fixture heredocs.  verbose_diff does NOT enable these options.
      show_pp_inp = @show_prettyprint_inputs
      show_pp_exp = show_pp_inp || @show_prettyprint_expected
      show_pp_rec = show_pp_inp || @show_prettyprint_received
      show_pp = show_pp_exp || show_pp_rec

      if show_pp && comparison_result.is_a?(Canon::Comparison::ComparisonResult)
        orig1, orig2 = comparison_result.original_strings
        if orig1 && orig2
          pp1, pp2 = prettyprint_for_display(orig1, orig2, format)
          output << format_prettyprint_inputs(pp1, pp2,
                                              show_expected: show_pp_exp,
                                              show_received: show_pp_rec)
        end
      end

      # 5. Line-Numbered Input Display (when show_line_numbered_inputs is enabled)
      if show_line && comparison_result.is_a?(Canon::Comparison::ComparisonResult)
        original1, original2 = comparison_result.original_strings
        if original1 && original2
          output << format_line_numbered_inputs(original1, original2)
        end
      end

      # 6. Main diff output (by-line or by-object) - ALWAYS

      # Check if comparison result is a ComparisonResult object
      if comparison_result.is_a?(Canon::Comparison::ComparisonResult)
        # Use original strings for line diff to show actual formatting/namespace differences
        # Use preprocessed strings for semantic comparison only
        doc1, doc2 = comparison_result.original_strings
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
            "><", ">\n<"
          ),
          Canon::Xml::C14n.canonicalize(actual, with_comments: false).gsub(
            />\s+$/, ""
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

    # Format original input strings with line numbers (RSpec-style)
    # Shows the actual strings that were passed in with line numbers for reference
    #
    # @param original1 [String] First original input string
    # @param original2 [String] Second original input string
    # @return [String] Formatted display with line numbers
    def format_line_numbered_inputs(original1, original2)
      return "" if original1.nil? || original2.nil?

      output = []
      output << ""
      output << colorize("=" * 70, :cyan, :bold)
      output << colorize("  ORIGINAL INPUTS (with line numbers)", :cyan, :bold)
      output << colorize("=" * 70, :cyan, :bold)
      output << ""

      # Format expected
      output << colorize("Expected:", :yellow, :bold)
      original1.each_line.with_index do |line, idx|
        output << "  #{colorize(sprintf('%4d', idx + 1),
                                :blue)} | #{line.chomp}"
      end
      output << ""

      # Format actual
      output << colorize("Received:", :yellow, :bold)
      original2.each_line.with_index do |line, idx|
        output << "  #{colorize(sprintf('%4d', idx + 1),
                                :blue)} | #{line.chomp}"
      end
      output << ""
      output << colorize("=" * 70, :cyan, :bold)
      output << ""

      output.join("\n")
    end

    # Format raw/original inputs for display (user-friendly copyable format)
    # Shows the raw file contents before any preprocessing.
    #
    # Use +show_expected:+ and +show_received:+ to control which side is
    # rendered.  Both default to +true+ so existing callers are unaffected.
    # Pass +show_expected: false+ to suppress the fixture/expected block while
    # still showing the received output (useful when the fixture is very long
    # and the user only wants to see what the generator produced).
    #
    # @param raw1 [String] First raw input string (expected / fixture)
    # @param raw2 [String] Second raw input string (received / actual)
    # @param show_expected [Boolean] Render the EXPECTED block
    # @param show_received [Boolean] Render the RECEIVED block
    # @return [String] Formatted display of raw inputs
    def format_raw_inputs(raw1, raw2, show_expected: true, show_received: true)
      return "" if raw1.nil? || raw2.nil?
      return "" unless show_expected || show_received

      output = []
      output << ""
      output << colorize("=== ORIGINAL INPUTS (Raw) ===", :cyan, :bold)
      output << ""

      if show_expected
        output << colorize("EXPECTED:", :yellow, :bold)
        output << ("-" * 70)
        output << raw1
        output << ""
      end

      if show_received
        output << colorize("RECEIVED:", :yellow, :bold)
        output << ("-" * 70)
        output << raw2
        output << ""
      end

      output << ""
      output.join("\n")
    end

    # Format preprocessed inputs for display (what was actually compared)
    # Shows the content after preprocessing (c14n, normalize, format, etc.)
    #
    # Use +show_expected:+ and +show_received:+ to control which side is rendered.
    # Both default to +true+ so existing callers are unaffected.
    # Pass +show_expected: false+ to suppress the fixture/expected block while
    # still showing the preprocessed received output.
    #
    # @param preprocessed1 [String] First preprocessed string (expected / fixture)
    # @param preprocessed2 [String] Second preprocessed string (received / actual)
    # @param preprocessing_info [Symbol, nil] Preprocessing mode (:c14n, :normalize, :format, etc.)
    # @param show_expected [Boolean] Render the EXPECTED block
    # @param show_received [Boolean] Render the RECEIVED block
    # @return [String] Formatted display of preprocessed inputs
    def format_preprocessed_inputs(preprocessed1, preprocessed2,
                                   preprocessing_info = nil,
                                   show_expected: true, show_received: true)
      return "" if preprocessed1.nil? || preprocessed2.nil?
      return "" unless show_expected || show_received

      output = []
      output << ""
      output << colorize("=== PREPROCESSED INPUTS (Compared) ===", :cyan, :bold)

      # Show preprocessing mode if available
      if preprocessing_info
        output << "Preprocessing: #{preprocessing_info}"
      end
      output << ""

      if show_expected
        output << colorize("EXPECTED:", :yellow, :bold)
        output << ("-" * 70)
        output << preprocessed1
        output << ""
      end

      if show_received
        output << colorize("RECEIVED:", :yellow, :bold)
        output << ("-" * 70)
        output << preprocessed2
        output << ""
      end

      output << ""
      output.join("\n")
    end

    # Build the final visualization map from various customization options
    #
    # @param visualization_map [Hash, nil] Complete custom visualization map
    # @param character_map_file [String, nil] Path to custom YAML file
    # @param character_definitions [Array<Hash>, nil] Individual character definitions
    # @return [Hash] Final visualization map
    def build_visualization_map(character_visualization: true,
                                visualization_map: nil,
                                character_map_file: nil,
                                character_definitions: nil)
      # Priority order:
      # 0. character_visualization: false → return empty map (no substitution)
      # 1. If visualization_map is provided, use it as complete replacement
      # 2. Otherwise, start with defaults and apply customizations

      # false disables all visualization
      return {} if character_visualization == false

      # :content_only currently behaves as true (full map)
      # TODO: apply visualization at DOM text-node level pre-serialization,
      # keeping structural indentation whitespace plain.
      # See docs/features/diff-formatting/character-visualization.adoc

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
      output = []
      output << colorize("Visual Diff:", :cyan, :bold)

      # Extract differences array from ComparisonResult if needed
      diffs_array = if differences.is_a?(Canon::Comparison::ComparisonResult)
                      differences.differences
                    else
                      differences
                    end

      # Delegate to format-specific formatter
      formatter = ByObject::BaseFormatter.for_format(
        format,
        use_color: @use_color,
        visualization_map: @visualization_map,
        show_diffs: @show_diffs,
      )

      output << formatter.format(diffs_array, format)

      output.join("\n")
    end

    # Generate by-line diff
    # Delegates to format-specific by-line formatters
    def by_line_diff(doc1, doc2, format: :xml, html_version: nil,
differences: [])
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

      # Apply display preprocessing (format both sides identically before diff)
      doc1, doc2 = apply_display_preprocessing(doc1, doc2, format)
      # Extract differences array and equivalent status from ComparisonResult if needed
      diffs_array = if differences.is_a?(Canon::Comparison::ComparisonResult)
                      @comparison_equivalent = differences.equivalent?
                      differences.differences
                    else
                      @comparison_equivalent = nil
                      differences
                    end

      # Delegate to format-specific formatter
      formatter = ByLine::BaseFormatter.for_format(
        format,
        use_color: @use_color,
        context_lines: @context_lines,
        diff_grouping_lines: @diff_grouping_lines,
        visualization_map: @visualization_map,
        show_diffs: @show_diffs,
        differences: diffs_array,
        diff_mode: @legacy_terminal ? :separate : @diff_mode,
        legacy_terminal: @legacy_terminal,
        equivalent: @comparison_equivalent,
      )

      output << formatter.format(doc1, doc2)

      output.join("\n")
    end

    # Generate a text-LCS diff against preprocessed lines (pretty_diff mode).
    #
    # This mode bypasses DiffNodeMapper entirely: it applies display_preprocessing
    # to both sides, then runs Diff::LCS.sdiff on the resulting plain-text lines.
    # It is a reliable short-term workaround for #85 (normative changes invisible
    # in :by_line mode when DiffNodeMapper's DOM-address correlation is off).
    #
    # Limitations:
    # - show_diffs :normative / :informative filter is ignored (no DiffNodes)
    # - No inline character highlighting (whole-line granularity only)
    #
    # @param doc1 [String] First document
    # @param doc2 [String] Second document
    # @param format [Symbol] Document format
    # @return [String] Formatted diff output
    def pretty_diff_format(doc1, doc2, format:)
      require "diff/lcs"

      resolved_format = format

      format_name = resolved_format.to_s.upcase
      output = []
      output << colorize("Pretty diff (#{format_name} mode):", :cyan, :bold)

      return output.join("\n") if doc1.nil? || doc2.nil?

      # Apply display preprocessing — same transforms as by_line_diff
      d1, d2 = apply_display_preprocessing(doc1, doc2, resolved_format)

      lines1 = d1.lines.map(&:chomp)
      lines2 = d2.lines.map(&:chomp)

      hunks = ::Diff::LCS.sdiff(lines1, lines2)

      output << render_pretty_diff(hunks)
      output.join("\n")
    end

    # Render sdiff hunks with context windowing and colorization.
    #
    # Uses the same context_lines setting as by_line_diff. Changed hunks
    # (action !=  "=") are expanded by context_lines in each direction; nearby
    # windows are merged; a separator is emitted between non-adjacent blocks.
    #
    # @param hunks [Array<Diff::LCS::ContextChange>] Output of Diff::LCS.sdiff
    # @return [String] Rendered diff lines joined with "\n"
    def render_pretty_diff(hunks)
      # Identify positions of changed hunks
      changed = hunks.each_index.reject { |i| hunks[i].action == "=" }

      return colorize("  (no differences)", :green) if changed.empty?

      ctx = [@context_lines || 3, 0].max

      # Build expanded windows, then merge overlapping/adjacent ones
      windows = changed.map do |pos|
        [
          [pos - ctx, 0].max,
          [pos + ctx, hunks.length - 1].min,
        ]
      end

      merged = []
      windows.each do |lo, hi|
        if merged.empty? || lo > merged.last[1] + 1
          merged << [lo, hi]
        else
          merged.last[1] = [merged.last[1], hi].max
        end
      end

      lines = []
      merged.each_with_index do |(lo, hi), block_idx|
        # Separator between non-adjacent blocks
        if block_idx.positive?
          lines << colorize("--- ---", :cyan)
        elsif lo.positive?
          lines << colorize("--- ---", :cyan)
        end

        (lo..hi).each do |i|
          hunk = hunks[i]
          case hunk.action
          when "="
            lines << (@use_color ? "\e[0m  #{hunk.old_element}" : "  #{hunk.old_element}")
          when "-"
            lines << colorize("- #{hunk.old_element}", :red)
          when "+"
            lines << colorize("+ #{hunk.new_element}", :green)
          when "!"
            lines << colorize("- #{hunk.old_element}", :red)
            lines << colorize("+ #{hunk.new_element}", :green)
          end
        end
      end

      lines.join("\n")
    end

    # Apply display preprocessing to both documents before the line diff.
    #
    # This normalizes both sides through the same formatter so that structural
    # formatting differences (indentation, line breaks) do not confuse the LCS
    # algorithm. Equivalence detection is never affected.
    #
    # NOTE: Character visualization (e.g. U+00A0 → ░) is applied by the
    # line-diff formatters to the output lines *after* this step. Because the
    # pretty-printer introduces only ASCII U+0020 spaces and U+000A newlines
    # for structural indentation, and neither of those is in Canon's default
    # visualization map, pretty-printer whitespace is never misvisualized.
    #
    # Future constraint: if the visualization map is extended to cover common
    # ASCII whitespace, this method must move visualization to a DOM-level pass
    # (walk text nodes before serialization) to keep structural and content
    # whitespace separate. See docs/features/diff-formatting/display-preprocessing.adoc.
    #
    # @param doc1 [String] First document
    # @param doc2 [String] Second document
    # @param format [Symbol] Document format (:xml, :html, :html4, :html5, ...)
    # @return [Array<String, String>] Preprocessed [doc1, doc2]
    def apply_display_preprocessing(doc1, doc2, format)
      case @display_preprocessing
      when :pretty_print
        apply_pretty_print(doc1, doc2, format)
      when :normalize_pretty_print
        apply_normalize_pretty_print(doc1, doc2, format)
      when :c14n
        apply_c14n(doc1, doc2, format)
      else
        [doc1, doc2]
      end
    end

    # Apply mixed-content-aware normalization + visualization to both documents.
    #
    # Uses PrettyPrinter::XmlNormalized, which breaks every XML element onto
    # its own line while preserving and visualizing boundary content whitespace.
    # See PrettyPrinter::XmlNormalized for the full rationale.
    #
    # Whitespace classification is driven by three element-name lists:
    # - preserve_whitespace_elements  → every char significant (e.g. pre, code)
    # - collapse_whitespace_elements → presence matters, form collapses (e.g. p, li)
    # - strip_whitespace_elements → all whitespace dropped (explicit blacklist)
    #
    # For XML the lists default to empty (all insensitive); for HTML built-in
    # defaults cover the common cases. Callers supply format-specific lists via
    # Canon::Config or DiffFormatter constructor keyword arguments.
    def apply_normalize_pretty_print(doc1, doc2, format)
      return [doc1, doc2] unless %i[xml html html4 html5].include?(format)

      indent_type_str = @pretty_printer_indent_type.to_s
      vis_map = @visualization_map.empty? ? DiffFormatter::DEFAULT_VISUALIZATION_MAP : @visualization_map

      require "canon/pretty_printer/xml_normalized"
      # TODO: implement HtmlNormalized for HTML formats; XmlNormalized works via
      # Nokogiri's HTML-aware parse for now.
      #
      # Create side-specific printers so that the pretty_printed_expected and
      # pretty_printed_received flags drop structural \n indentation nodes only
      # on the side that is actually pretty-printed.  If both sides share the
      # same settings, two identical printer instances are created (cheap).
      shared_args = {
        indent: @pretty_printer_indent,
        indent_type: indent_type_str,
        visualization_map: vis_map,
        preserve_whitespace_elements: @preserve_whitespace_elements,
        collapse_whitespace_elements: @collapse_whitespace_elements,
        strip_whitespace_elements: @strip_whitespace_elements,
        sort_attributes: @pretty_printer_sort_attributes,
      }

      printer_expected = Canon::PrettyPrinter::XmlNormalized.new(
        **shared_args,
        pretty_printed: @pretty_printed_expected,
      )
      printer_received = Canon::PrettyPrinter::XmlNormalized.new(
        **shared_args,
        pretty_printed: @pretty_printed_received,
      )

      [safe_format(printer_expected, doc1), safe_format(printer_received, doc2)]
    end

    # Pretty-print both documents using a format-appropriate pretty printer.
    #
    # * HTML formats (:html, :html4, :html5) use +Canon::PrettyPrinter::Html+
    #   which is Nokogiri::HTML5-aware and correctly handles void elements,
    #   optional end tags, and HTML5 serialization rules.
    # * XML uses +Canon::PrettyPrinter::Xml+.
    # * Other formats fall through unchanged.
    def apply_pretty_print(doc1, doc2, format)
      return [doc1, doc2] unless %i[xml html html4 html5].include?(format)

      indent_type_str = @pretty_printer_indent_type.to_s

      printer = if %i[html html4 html5].include?(format)
                  require "canon/pretty_printer/html"
                  Canon::PrettyPrinter::Html.new(
                    indent: @pretty_printer_indent,
                    indent_type: indent_type_str,
                  )
                else
                  require "canon/pretty_printer/xml"
                  Canon::PrettyPrinter::Xml.new(
                    indent: @pretty_printer_indent,
                    indent_type: indent_type_str,
                  )
                end

      [safe_format(printer, doc1), safe_format(printer, doc2)]
    end

    # Normalize both documents for display using canonical serialization.
    #
    # * HTML formats use Nokogiri's HTML5 serializer as a consistent canonical
    #   form (attribute order, void elements, etc. are standardized).
    # * XML uses the XML C14N algorithm (alphabetical attributes, namespace
    #   normalization, etc.).
    # * Other formats fall through unchanged.
    #
    # @param doc1 [String] First document
    # @param doc2 [String] Second document
    # @param format [Symbol] Document format (:xml, :html, :html4, :html5, ...)
    # @return [Array<String, String>] Canonicalized [doc1, doc2]
    def apply_c14n(doc1, doc2, format = :xml)
      if %i[html html4 html5].include?(format)
        [safe_html_normalize(doc1), safe_html_normalize(doc2)]
      else
        require "canon/xml/c14n"
        [safe_c14n(doc1), safe_c14n(doc2)]
      end
    end

    # Pretty-print document strings for the fixture-ready display section.
    #
    # Runs independently of the +display_preprocessing+ setting — it is a
    # standalone display feature, not part of the diff pipeline.
    #
    # The output contains NO character visualization so it can be copy-pasted
    # directly into RSpec heredoc fixtures.
    #
    # @param doc1 [String] First document (expected / fixture)
    # @param doc2 [String] Second document (received / actual)
    # @param format [Symbol] Document format (:xml, :html, :html4, :html5, ...)
    # @return [Array<String, String>] Pretty-printed [doc1, doc2]
    def prettyprint_for_display(doc1, doc2, format)
      indent_type_str = @pretty_printer_indent_type.to_s

      if %i[html html4 html5].include?(format)
        require "canon/pretty_printer/html"
        printer = Canon::PrettyPrinter::Html.new(
          indent: @pretty_printer_indent,
          indent_type: indent_type_str,
        )
      elsif format == :xml
        require "canon/pretty_printer/xml"
        printer = Canon::PrettyPrinter::Xml.new(
          indent: @pretty_printer_indent,
          indent_type: indent_type_str,
        )
      else
        return [doc1, doc2]
      end

      [safe_format(printer, doc1), safe_format(printer, doc2)]
    end

    # Format fixture-ready pretty-printed inputs for display.
    #
    # Unlike +format_preprocessed_inputs+, this section outputs plain ASCII
    # with NO character visualization — the content is intended for
    # copy-pasting into RSpec heredoc fixtures.
    #
    # @param pp1 [String] First pretty-printed string (expected / fixture)
    # @param pp2 [String] Second pretty-printed string (received / actual)
    # @param show_expected [Boolean] Render the EXPECTED block
    # @param show_received [Boolean] Render the RECEIVED block
    # @return [String] Formatted display of pretty-printed inputs
    def format_prettyprint_inputs(pp1, pp2, show_expected: true,
show_received: true)
      return "" if pp1.nil? || pp2.nil?
      return "" unless show_expected || show_received

      output = []
      output << ""
      output << colorize("=== PRETTY-PRINTED INPUTS (Fixture-ready) ===",
                         :cyan, :bold)
      output << ""

      if show_expected
        output << colorize("EXPECTED:", :yellow, :bold)
        output << ("-" * 70)
        output << pp1
        output << ""
      end

      if show_received
        output << colorize("RECEIVED:", :yellow, :bold)
        output << ("-" * 70)
        output << pp2
        output << ""
      end

      output << ""
      output.join("\n")
    end

    # Format a document through the pretty-printer, falling back to the
    # original string on any parse error.
    def safe_format(printer, doc)
      printer.format(doc.to_s)
    rescue StandardError
      doc.to_s
    end

    # Canonicalize a document via C14N, falling back on error.
    def safe_c14n(doc)
      Canon::Xml::C14n.canonicalize(doc.to_s, with_comments: true)
    rescue StandardError
      doc.to_s
    end

    # Serialize HTML through Nokogiri's HTML5 serializer for a canonical form.
    # Normalizes attribute order, void elements, and optional end tags consistently.
    # Falls back to the original string on any parse error.
    def safe_html_normalize(doc)
      require "nokogiri"
      Nokogiri::HTML5(doc.to_s).to_html(encoding: "UTF-8")
    rescue StandardError
      doc.to_s
    end

    # Colorize text if color is enabled.
    # RSpec-aware: resets any existing ANSI codes before applying new colors.
    def colorize(text, *colors)
      return text unless @use_color

      # Reset ANSI codes first to prevent RSpec's initial red from interfering
      "\e[0m#{Paint[text, *colors]}"
    end
  end
end
