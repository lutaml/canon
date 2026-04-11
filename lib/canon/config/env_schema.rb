# frozen_string_literal: true

module Canon
  class Config
    # Schema definition for configuration attributes
    # Defines attribute types and ENV variable mappings
    class EnvSchema
      ATTRIBUTE_TYPES = {
        # DiffConfig attributes
        mode: :symbol,
        use_color: :boolean,
        context_lines: :integer,
        grouping_lines: :integer,
        show_diffs: :symbol,
        verbose_diff: :boolean,
        algorithm: :symbol,
        show_raw_inputs: :boolean,
        show_raw_expected: :boolean,
        show_raw_received: :boolean,
        show_preprocessed_inputs: :boolean,
        show_preprocessed_expected: :boolean,
        show_preprocessed_received: :boolean,
        show_prettyprint_inputs: :boolean,
        show_prettyprint_expected: :boolean,
        show_prettyprint_received: :boolean,
        show_line_numbered_inputs: :boolean,
        character_visualization: :symbol,     # true, false, :content_only
        display_format: :symbol,
        display_preprocessing: :symbol,       # :none, :pretty_print, :normalize_pretty_print, :c14n
        pretty_printer_indent: :integer,
        pretty_printer_indent_type: :symbol,  # :space or :tab
        strict_whitespace_elements: :string_array,        # comma-separated element names
        normalize_whitespace_elements: :string_array,     # comma-separated element names
        insensitive_whitespace_elements: :string_array,   # comma-separated element names
        pretty_printed_expected: :boolean,
        pretty_printed_received: :boolean,
        pretty_printer_sort_attributes: :boolean,
        compact_semantic_report: :boolean,
        expand_difference: :boolean,
        theme: :symbol,

        # MatchConfig attributes
        profile: :symbol,

        # FormatConfig attributes
        preprocessing: :string,

        # Size limits to prevent hangs on large files
        max_file_size: :integer,
        max_node_count: :integer,
        max_diff_lines: :integer,
      }.freeze

      class << self
        def type_for(attribute)
          ATTRIBUTE_TYPES[attribute.to_sym]
        end

        def env_key(format, config_type, attribute)
          "CANON_#{format.to_s.upcase}_#{config_type.to_s.upcase}_#{attribute.to_s.upcase}"
        end

        def global_env_key(attribute)
          "CANON_#{attribute.to_s.upcase}"
        end

        def all_diff_attributes
          %i[mode use_color context_lines grouping_lines show_diffs
             verbose_diff algorithm show_raw_inputs show_raw_expected show_raw_received
             show_preprocessed_inputs show_preprocessed_expected show_preprocessed_received
             show_prettyprint_inputs show_prettyprint_expected show_prettyprint_received
             show_line_numbered_inputs character_visualization
             display_format display_preprocessing
             pretty_printer_indent pretty_printer_indent_type
             strict_whitespace_elements normalize_whitespace_elements insensitive_whitespace_elements
             pretty_printed_expected pretty_printed_received
             pretty_printer_sort_attributes
             compact_semantic_report expand_difference
             max_file_size max_node_count max_diff_lines theme]
        end

        def all_match_attributes
          %i[profile]
        end

        def all_format_attributes
          %i[preprocessing]
        end
      end
    end
  end
end
