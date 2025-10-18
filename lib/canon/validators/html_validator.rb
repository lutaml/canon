# frozen_string_literal: true

require "nokogiri"
require_relative "base_validator"

module Canon
  module Validators
    # Validator for HTML input
    #
    # Validates HTML input (HTML4, HTML5, or XHTML) using Nokogiri.
    # Automatically detects the HTML type and applies appropriate validation.
    # Raises detailed ValidationError with line and column information
    # when malformed HTML is detected.
    class HtmlValidator < BaseValidator
      # Validate HTML input
      #
      # @param input [String] The HTML string to validate
      # @raise [Canon::ValidationError] If HTML is malformed
      # @return [void]
      def self.validate!(input)
        return if input.nil? || input.strip.empty?

        # Strip XML declaration for validation (it's not critical for parsing)
        cleaned_input = input.sub(/\A\s*<\?xml[^?]*\?>\s*/, "")

        if xhtml?(cleaned_input)
          validate_xhtml!(cleaned_input)
        else
          validate_html5!(cleaned_input)
        end
      end

      # Check if HTML is XHTML
      #
      # @param html [String] The HTML string to check
      # @return [Boolean] true if XHTML, false otherwise
      def self.xhtml?(html)
        html.include?("XHTML") ||
          html.include?('xmlns="http://www.w3.org/1999/xhtml"') ||
          html.match?(/xmlns:\w+/)
      end

      # Validate XHTML input using XML strict parsing
      #
      # @param input [String] The XHTML string to validate
      # @raise [Canon::ValidationError] If XHTML is malformed
      # @return [void]
      def self.validate_xhtml!(input)
        Nokogiri::XML(input) do |config|
          config.strict.nonet
        end
      rescue Nokogiri::XML::SyntaxError => e
        location = extract_location(e)
        raise Canon::ValidationError.new(
          e.message.split("\n").first,
          format: :html,
          line: location[:line],
          column: location[:column],
          details: "XHTML validation failed: #{extract_details(e)}",
        )
      end

      # Validate HTML5 input
      #
      # @param input [String] The HTML5 string to validate
      # @raise [Canon::ValidationError] If HTML5 is malformed
      # @return [void]
      def self.validate_html5!(input)
        doc = Nokogiri::HTML5(input, max_errors: 100)

        # Check for parse errors
        return unless doc.errors.any?

        # Find first significant error (level 2 = error, level 1 = warning)
        # Filter out doctype warnings and other non-critical issues
        significant_errors = doc.errors.select do |e|
          e.level >= 2 && !doctype_or_warning?(e)
        end

        return if significant_errors.empty?

        error = significant_errors.first
        location = extract_location(error)
        raise Canon::ValidationError.new(
          error.message,
          format: :html,
          line: location[:line],
          column: location[:column],
          details: build_error_details(significant_errors),
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

      # Build error details from multiple errors
      #
      # @param errors [Array<Nokogiri::XML::SyntaxError>] Array of errors
      # @return [String, nil] Combined error details
      def self.build_error_details(errors)
        return nil if errors.size <= 1

        significant = errors.select { |e| e.level >= 2 }
        return nil if significant.empty?

        details = significant[1..3].map do |e|
          loc = extract_location(e)
          msg = e.message
          msg += " (line #{loc[:line]})" if loc[:line]
          msg
        end
        details.join("; ")
      end

      # Check if error is a doctype or other non-critical warning
      #
      # @param error [Nokogiri::XML::SyntaxError] The error to check
      # @return [Boolean] true if error is non-critical
      def self.doctype_or_warning?(error)
        error.message.match?(/doctype|Expected a doctype token/i)
      end

      private_class_method :xhtml?, :validate_xhtml!, :validate_html5!,
                           :extract_details, :build_error_details,
                           :doctype_or_warning?
    end
  end
end
