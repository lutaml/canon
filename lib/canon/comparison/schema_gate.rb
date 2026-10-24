# frozen_string_literal: true

module Canon
  module Comparison
    # W5.1 validate-then-compare: runs both documents through the
    # engine's XSD assessment before the diff. Returns a hash of
    # side-index (0 or 1) to Canon::ValidationError — empty when both
    # documents pass and the comparison may proceed.
    module SchemaGate
      module_function

      # @param obj1 [String] first XML document
      # @param obj2 [String] second XML document
      # @param schema [String, Leptris::XML::XSD::Schema] schema text
      #   (compiled once here) or a compiled schema
      # @return [Hash{Integer=>Canon::ValidationError}]
      def gate(obj1, obj2, schema)
        schema = Canon::Validators::XsdValidator.compile(schema) if schema.is_a?(String)
        failures = {}
        [obj1, obj2].each_with_index do |obj, side|
          Canon::Validators::XsdValidator.validate!(obj, schema: schema)
        rescue Canon::ValidationError => e
          failures[side] = e
        end
        failures
      end
    end
  end
end
