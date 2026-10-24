# frozen_string_literal: true

require "leptris" # the XSD lane rides the engine's tier-1 validator
# (libleptris >= 1.9.321, leptris#1075)

module Canon
  module Validators
    # XSD validation (W5.1) through the engine's tier-1 validator:
    # schema compilation, whole-instance assessment, enumerated
    # failures. The schema is a compiled `Leptris::XML::XSD::Schema`
    # — callers validating many documents against one schema compile
    # once and reuse (compilation is the expensive step).
    #
    #     schema = Canon::Validators::XsdValidator.compile(schema_xml)
    #     Canon::Validators::XsdValidator.validate!(xml, schema: schema)
    class XsdValidator < BaseValidator
      # Compile a schema from XSD text. Raises Canon::ValidationError
      # when the text is not well-formed XML, and when the engine
      # reports schema-level problems.
      #
      # @param schema_xml [String] the XSD document
      # @return [Leptris::XML::XSD::Schema] the compiled schema
      def self.compile(schema_xml)
        schema = Leptris::XML::XSD.compile(schema_xml)
        if (detail = schema.error)
          raise Canon::ValidationError.new(
            "schema invalid: #{detail}",
            format: :xml,
          )
        end
        schema
      end

      # Validate an XML instance against a compiled schema
      #
      # @param input [String] the XML instance
      # @param schema [Leptris::XML::XSD::Schema] a compiled schema
      # @raise [Canon::ValidationError] if the instance fails
      #   assessment; the message carries the first failure, details
      #   carry the full enumerated list
      # @return [void]
      def self.validate!(input, schema:)
        return if input.nil? || input.strip.empty?

        doc = Leptris::XML.parse(input, readonly: true)
        errors = schema.validate_errors(doc)
        return if errors.empty?

        raise Canon::ValidationError.new(
          errors.first.to_s,
          format: :xml,
          details: errors.join("\n"),
        )
      end
    end
  end
end
