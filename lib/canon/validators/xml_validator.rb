# frozen_string_literal: true

require "nokogiri"
require_relative "base_validator"

module Canon
  module Validators
    # Validator for XML input
    #
    # Validates XML input using Nokogiri's strict parsing mode.
    # Raises detailed ValidationError with line and column information
    # when malformed XML is detected.
    class XmlValidator < BaseValidator
      # Validate XML input
      #
      # @param input [String] The XML string to validate
      # @raise [Canon::ValidationError] If XML is malformed
      # @return [void]
      def self.validate!(input)
        return if input.nil? || input.strip.empty?

        # Parse with strict error handling
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

      # Extract additional error details
      #
      # @param error [Nokogiri::XML::SyntaxError] The syntax error
      # @return [String, nil] Additional details about the error
      def self.extract_details(error)
        return nil unless error.respond_to?(:errors)

        details = error.errors.map(&:message).reject do |msg|
          msg == error.message
        end
        details.join("; ") unless details.empty?
      end

      private_class_method :extract_details
    end
  end
end
