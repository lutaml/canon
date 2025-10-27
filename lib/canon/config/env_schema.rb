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
             verbose_diff algorithm max_file_size max_node_count max_diff_lines]
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
