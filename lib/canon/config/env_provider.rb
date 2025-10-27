# frozen_string_literal: true

require_relative "env_schema"
require_relative "type_converter"

module Canon
  class Config
    # Provides environment variable values for configuration
    # Reads and parses CANON_* environment variables
    class EnvProvider
      class << self
        # Load environment overrides for a specific format's diff config
        def load_diff_for_format(format)
          load_config_for_format(format, :diff, EnvSchema.all_diff_attributes)
        end

        # Load environment overrides for a specific format's match config
        def load_match_for_format(format)
          load_config_for_format(format, :match, EnvSchema.all_match_attributes)
        end

        # Load environment overrides for a specific format's format config
        def load_format_for_format(format)
          load_config_for_format(format, :format,
                                 EnvSchema.all_format_attributes)
        end

        # Load global environment overrides (apply to all formats)
        def load_global_diff
          load_global_config(EnvSchema.all_diff_attributes)
        end

        private

        def load_config_for_format(format, config_type, attributes)
          result = {}
          attributes.each do |attr|
            # Try format-specific ENV var first
            env_key = EnvSchema.env_key(format, config_type, attr)
            value = ENV[env_key]

            # Fall back to global ENV var if format-specific not set
            if value.nil?
              global_key = EnvSchema.global_env_key(attr)
              value = ENV[global_key]
            end

            # Convert and store if value exists
            if value
              result[attr] = TypeConverter.convert(attr, value)
            end
          end
          result
        end

        def load_global_config(attributes)
          result = {}
          attributes.each do |attr|
            global_key = EnvSchema.global_env_key(attr)
            value = ENV[global_key]

            if value
              result[attr] = TypeConverter.convert(attr, value)
            end
          end
          result
        end
      end
    end
  end
end
