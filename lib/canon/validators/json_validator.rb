# frozen_string_literal: true

require "json"
require_relative "base_validator"

module Canon
  module Validators
    # Validator for JSON input
    #
    # Validates JSON input using Ruby's JSON parser.
    # Raises detailed ValidationError with position information
    # when malformed JSON is detected.
    class JsonValidator < BaseValidator
      # Validate JSON input
      #
      # @param input [String] The JSON string to validate
      # @raise [Canon::ValidationError] If JSON is malformed
      # @return [void]
      def self.validate!(input)
        return if input.nil?
        return if input.is_a?(Hash) || input.is_a?(Array) # Already parsed
        return if input.strip.empty?

        JSON.parse(input)
      rescue JSON::ParserError => e
        # Extract position from error message
        position = extract_position(e.message)

        raise Canon::ValidationError.new(
          clean_error_message(e.message),
          format: :json,
          line: position[:line],
          column: position[:column],
          details: extract_context(input, position),
        )
      end

      # Extract line and column from JSON error message
      #
      # @param message [String] The error message
      # @return [Hash] Hash with :line and :column keys
      def self.extract_position(message)
        line = nil
        column = nil

        # JSON errors often report character position
        if message =~ /at line (\d+), column (\d+)/i
          line = ::Regexp.last_match(1).to_i
          column = ::Regexp.last_match(2).to_i
        elsif /at character offset (\d+)/i.match?(message)
          # For character offset, we can't easily determine line/column
          # without parsing the input
        end

        { line: line, column: column }
      end

      # Clean error message by removing technical details
      #
      # @param message [String] The raw error message
      # @return [String] Cleaned error message
      def self.clean_error_message(message)
        # Remove 'unexpected token' technical details and keep main message
        message.split(" at ").first.strip
      end

      # Extract context around the error position
      #
      # @param input [String] The input JSON string
      # @param position [Hash] Position hash with :line key
      # @return [String, nil] Context snippet around the error
      def self.extract_context(input, position)
        return nil unless position[:line]

        lines = input.split("\n")
        line_idx = position[:line] - 1
        return nil if line_idx.negative? || line_idx >= lines.size

        # Get the problematic line and surrounding lines
        start_idx = [0, line_idx - 1].max
        end_idx = [lines.size - 1, line_idx + 1].min

        context_lines = lines[start_idx..end_idx]
        "Near: #{context_lines.join(' ')}"
      end

      private_class_method :extract_position, :clean_error_message,
                           :extract_context
    end
  end
end
