# frozen_string_literal: true

require_relative "../errors"

module Canon
  module Validators
    # Base class for all input validators
    #
    # This abstract base class defines the interface that all format-specific
    # validators must implement. Each validator is responsible for validating
    # input in a specific format and raising detailed ValidationError when
    # issues are found.
    class BaseValidator
      # Validate input and raise ValidationError if invalid
      #
      # @param input [String] The input to validate
      # @raise [Canon::ValidationError] If input is invalid
      # @return [void]
      def self.validate!(input)
        raise NotImplementedError,
              "#{name} must implement validate! method"
      end

      # Extract line and column information from an error
      #
      # @param error [Exception] The error containing location information
      # @return [Hash] Hash with :line and :column keys
      def self.extract_location(error)
        line = nil
        column = nil

        # Try to extract line/column from error message
        if error.respond_to?(:line)
          line = error.line
        elsif error.message =~ /line[:\s]+(\d+)/i
          line = ::Regexp.last_match(1).to_i
        end

        if error.respond_to?(:column)
          column = error.column
        elsif error.message =~ /column[:\s]+(\d+)/i
          column = ::Regexp.last_match(1).to_i
        end

        { line: line, column: column }
      end
    end
  end
end
