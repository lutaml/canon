# frozen_string_literal: true

module Canon
  class Config
    # Schema definition for configuration attributes.
    #
    # Diff attribute types and names are derived lazily from
    # +Canon::Config::DiffConfig.config_keys+ (the single source of
    # truth declared via {ConfigDSL}).  Match and Format attribute
    # types are declared here because those config classes do not yet
    # use the DSL.
    #
    # The lookup is intentionally lazy so that {EnvSchema} can be
    # loaded before {DiffConfig} is defined — the methods are only
    # called once a {DiffConfig} instance is being built, by which
    # time the DSL registry is populated.
    class EnvSchema
      MATCH_ATTRIBUTE_TYPES = {
        profile: :symbol,
      }.freeze

      FORMAT_ATTRIBUTE_TYPES = {
        preprocessing: :string,
      }.freeze

      class << self
        def type_for(attribute)
          key = attribute.to_sym
          diff_type(key) || match_type(key) || format_type(key)
        end

        def env_key(format, config_type, attribute)
          "CANON_#{format.to_s.upcase}_#{config_type.to_s.upcase}_#{attribute.to_s.upcase}"
        end

        def global_env_key(attribute)
          "CANON_#{attribute.to_s.upcase}"
        end

        # All diff attributes declared via {ConfigDSL} on {DiffConfig}.
        #
        # @return [Array<Symbol>]
        def all_diff_attributes
          diff_config_keys.keys
        end

        # Match attributes subject to ENV override.
        #
        # @return [Array<Symbol>]
        def all_match_attributes
          %i[profile
             preserve_whitespace_elements collapse_whitespace_elements
             strip_whitespace_elements]
        end

        # Format attributes subject to ENV override.
        #
        # @return [Array<Symbol>]
        def all_format_attributes
          %i[preprocessing]
        end

        private

        def diff_type(key)
          meta = diff_config_keys[key]
          meta&.fetch(:type)
        end

        def match_type(key)
          MATCH_ATTRIBUTE_TYPES[key]
        end

        def format_type(key)
          FORMAT_ATTRIBUTE_TYPES[key]
        end

        def diff_config_keys
          Canon::Config::DiffConfig.config_keys
        end
      end
    end
  end
end
