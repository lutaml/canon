# frozen_string_literal: true

module Canon
  class Config
    # Type converter for environment variable values
    # Converts string ENV values to appropriate Ruby types
    class TypeConverter
      BOOLEAN_VALUES = {
        "true" => true,
        "1" => true,
        "yes" => true,
        "false" => false,
        "0" => false,
        "no" => false,
      }.freeze

      class << self
        def convert(attribute, value)
          return nil if value.nil? || value.empty?

          type = EnvSchema.type_for(attribute)
          case type
          when :boolean
            convert_boolean(value)
          when :integer
            convert_integer(value)
          when :symbol
            convert_symbol(value)
          when :string
            value
          else
            value
          end
        end

        private

        def convert_boolean(value)
          normalized = value.to_s.downcase
          return BOOLEAN_VALUES[normalized] if BOOLEAN_VALUES.key?(normalized)

          raise ArgumentError,
                "Invalid boolean value: #{value}. " \
                "Valid values: #{BOOLEAN_VALUES.keys.join(', ')}"
        end

        def convert_integer(value)
          Integer(value)
        rescue ArgumentError
          raise ArgumentError, "Invalid integer value: #{value}"
        end

        def convert_symbol(value)
          value.to_sym
        end
      end
    end
  end
end
