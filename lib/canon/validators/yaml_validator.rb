# frozen_string_literal: true

require "yaml"
require "date"
require "time"
require_relative "base_validator"

module Canon
  module Validators
    # Validator for YAML input
    #
    # Validates YAML input using Ruby's YAML parser.
    # Raises detailed ValidationError with position information
    # when malformed YAML is detected.
    class YamlValidator < BaseValidator
      # Validate YAML input
      #
      # @param input [String] The YAML string to validate
      # @raise [Canon::ValidationError] If YAML is malformed
      # @return [void]
      def self.validate!(input)
        return if input.nil? || input.strip.empty?

        YAML.safe_load(input, permitted_classes: [Symbol, Date, Time])
      rescue Psych::SyntaxError => e
        location = extract_location(e)

        raise Canon::ValidationError.new(
          clean_error_message(e.message),
          format: :yaml,
          line: location[:line],
          column: location[:column],
          details: extract_context(input, e),
        )
      end

      # Clean error message by removing file path details
      #
      # @param message [String] The raw error message
      # @return [String] Cleaned error message
      def self.clean_error_message(message)
        # Remove file path and keep main message
        message.gsub(/\(<unknown>\):\s*/, "").split("\n").first.strip
      end

      # Extract context around the error
      #
      # @param input [String] The input YAML string
      # @param error [Psych::SyntaxError] The syntax error
      # @return [String, nil] Context snippet around the error
      def self.extract_context(input, error)
        return nil unless error.line

        lines = input.split("\n")
        line_idx = error.line - 1
        return nil if line_idx.negative? || line_idx >= lines.size

        # Get the problematic line
        problem_line = lines[line_idx]

        # Add column indicator if available
        if error.column
          indicator = "#{' ' * (error.column - 1)}^"
          "Line content: #{problem_line}\n#{indicator}"
        else
          "Line content: #{problem_line}"
        end
      end

      private_class_method :clean_error_message, :extract_context
    end
  end
end
