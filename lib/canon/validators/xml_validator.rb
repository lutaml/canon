# frozen_string_literal: true

module Canon
  module Validators
    # Validator for XML input
    #
    # Validates XML input with strict parsing when nokogiri is available
    # (detailed line/column errors). Without nokogiri, validation parses
    # through the active engine (moxml/leptris), which still rejects
    # malformed input — only the location detail is coarser.
    class XmlValidator < BaseValidator
      # Validate XML input
      #
      # @param input [String] The XML string to validate
      # @raise [Canon::ValidationError] If XML is malformed
      # @return [void]
      def self.validate!(input)
        return if input.nil? || input.strip.empty?

        if Canon::NokogiriLoader.available?
          nokogiri_validate!(input)
        else
          engine_validate!(input)
        end
      end

      # Parse with strict error handling
      #
      # @param input [String] The XML string to validate
      # @raise [Canon::ValidationError] If XML is malformed
      # @return [void]
      def self.nokogiri_validate!(input)
        Nokogiri::XML(input) do |config|
          config.strict.nonet
        end
      rescue Nokogiri::XML::SyntaxError => e
        location = extract_location(e)
        raise Canon::ValidationError.new(
          e.message.split("\n").first,
          format: :xml,
          line: location[:line],
          column: location[:column],
          details: extract_details(e),
        )
      end

      # Validate by parsing through the engine selected by
      # Canon::XmlBackend (never raw nokogiri).
      #
      # @param input [String] The XML string to validate
      # @raise [Canon::ValidationError] If XML is malformed
      # @return [void]
      def self.engine_validate!(input)
        Canon::XmlParsing.parse(input)
      rescue StandardError => e
        location = extract_location(e)
        raise Canon::ValidationError.new(
          e.message.split("\n").first,
          format: :xml,
          line: location[:line],
          column: location[:column],
          details: extract_details(e),
        )
      end

      # Extract additional error details
      #
      # @param error [Nokogiri::XML::SyntaxError] The syntax error
      # @return [String, nil] Additional details about the error
      def self.extract_details(_error)
        nil
      end

      private_class_method :extract_details
    end
  end
end
