# frozen_string_literal: true

module Canon
  class Config
    # DSL for declaring config-backed attributes on a config class.
    #
    # A config class (DiffConfig, MatchConfig, FormatConfig) extends this
    # module and declares each user-tunable attribute with {config_key}.
    # The DSL generates the matching getter/setter pair and registers
    # the attribute's metadata (type, enum, default, coercion) in a
    # per-class registry so other components (EnvSchema, TypeConverter)
    # can discover it without duplicating the schema.
    #
    # Goals (lutaml/canon TODO.improve/07):
    # - Eliminate the 5-line getter/setter boilerplate per attribute
    # - Provide a single source of truth for attribute types/enums
    # - Keep the public API stable (methods behave exactly as before)
    #
    # @example Declare a simple boolean key
    #   class DiffConfig
    #     extend ConfigDSL
    #     config_key :verbose_diff, type: :boolean, default: false
    #   end
    #
    # @example Declare an enum-constrained symbol key
    #   config_key :mode, type: :symbol,
    #                       enum: %i[by_line by_object pretty_diff],
    #                       default: :by_line
    #
    # @example Declare a key with setter coercion
    #   config_key :preserve_whitespace_elements,
    #             type: :string_array,
    #             default: [],
    #             coerce: ->(v) { Array(v).map(&:to_s) }
    module ConfigDSL
      # Per-class attribute registry, lazily initialized on first
      # +config_key+ declaration.  Stored on the extending class so
      # each config class owns its own map without registry leakage.
      def config_keys
        @config_keys ||= {}
      end

      # Declare a config-backed attribute.
      #
      # Generates a getter and setter on the extending class.  The
      # getter reads through the resolver; the setter validates against
      # +enum+ (if provided), applies +coerce+ (if provided), and
      # writes through the resolver.
      #
      # @param name [Symbol] Attribute name
      # @param type [Symbol] Type tag for ENV conversion
      #   (:boolean, :integer, :symbol, :string, :string_array,
      #    :pass_through)
      # @param enum [Array, nil] Allowed values; setter validates
      # @param default [Object, Proc] Default value, or a callable that
      #   returns the default.  Callables are evaluated each time the
      #   resolver is (re)built, so they pick up runtime state such as
      #   +ColorDetector.supports_color?+ when stubs are installed by
      #   the test suite.
      # @param coerce [Proc, nil] Setter coercion proc (value → value)
      # @param getter_coerce [Proc, nil] Getter coercion proc
      # @return [void]
      def config_key(name, type: :pass_through, enum: nil, default: nil,
                     coerce: nil, getter_coerce: nil)
        sym = name.to_sym
        config_keys[sym] = {
          type: type,
          enum: enum,
          default: default,
          default_proc: default.is_a?(Proc) ? default : nil,
          coerce: coerce,
          getter_coerce: getter_coerce,
        }.freeze

        define_getter(sym, getter_coerce)
        define_setter(sym, coerce)
      end

      # Resolve a declared default to a concrete value.
      #
      # If the declared default is a callable (e.g. a proc or method
      # object), it is invoked each time this method is called so the
      # result reflects the current runtime state.  Otherwise the
      # stored default value is returned as-is.
      #
      # @param key [Symbol] Attribute name
      # @return [Object] Resolved default value (may be +nil+)
      def resolve_default(key)
        meta = config_keys[key]
        return nil unless meta

        proc_form = meta[:default_proc]
        return proc_form.call if proc_form

        meta[:default]
      end

      # Validate a value against an attribute's enum, if any.
      #
      # Mirrors the original +DiffConfig.validate_config_value!+ API
      # so existing call sites (and specs) keep working.
      #
      # @param key [Symbol] Attribute name
      # @param value [Object] Value to validate
      # @raise [ArgumentError] if value is not in the enum
      # @return [void]
      def validate_config_value!(key, value)
        meta = config_keys[key]
        return unless meta&.dig(:enum)
        return if meta[:enum].include?(value)

        raise ArgumentError,
              "Invalid value #{value.inspect} for #{key}. " \
              "Valid values: #{meta[:enum].map(&:inspect).join(', ')}"
      end

      # Enum constraint map, keyed by attribute name.
      #
      # Derived from declared config_keys for backward compatibility
      # with the original +VALID_ENUM_VALUES+ constant.
      #
      # @return [Hash{Symbol => Array}] Enum values per attribute
      def enum_values
        config_keys.filter_map { |k, m| [k, m[:enum]] if m[:enum] }.to_h
      end

      private

      # Define the reader method for +name+.
      def define_getter(name, getter_coerce)
        if getter_coerce
          define_method(name) do
            instance_exec(@resolver.resolve(name), &getter_coerce)
          end
        else
          define_method(name) do
            @resolver.resolve(name)
          end
        end
      end

      # Define the writer method for +name+.
      def define_setter(name, coerce)
        if coerce
          define_method("#{name}=") do |value|
            coerced = instance_exec(value, &coerce)
            self.class.validate_config_value!(name, coerced)
            @resolver.set_programmatic(name, coerced)
          end
        else
          define_method("#{name}=") do |value|
            self.class.validate_config_value!(name, value)
            @resolver.set_programmatic(name, value)
          end
        end
      end
    end
  end
end
