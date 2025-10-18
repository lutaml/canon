# frozen_string_literal: true

module Canon
  # Base error class for Canon gem
  class Error < StandardError; end

  # Error raised when attempting to compare different formats
  class CompareFormatMismatchError < Error
    # Initialize a new CompareFormatMismatchError
    #
    # @param format1 [Symbol] The first format
    # @param format2 [Symbol] The second format
    def initialize(format1, format2)
      super("Cannot compare different formats: #{format1} vs #{format2}")
    end
  end

  # Error raised when input validation fails
  #
  # This error is raised when input (XML, HTML, JSON, YAML) is malformed
  # or fails validation checks. It includes detailed information about
  # the error location and nature.
  class ValidationError < Error
    attr_reader :format, :line, :column, :details

    # Initialize a new ValidationError
    #
    # @param message [String] The error message
    # @param format [Symbol] The format being validated (:xml, :html, :json,
    #   :yaml)
    # @param line [Integer, nil] The line number where the error occurred
    # @param column [Integer, nil] The column number where the error occurred
    # @param details [String, nil] Additional details about the error
    def initialize(message, format:, line: nil, column: nil, details: nil)
      @format = format
      @line = line
      @column = column
      @details = details
      super(build_message(message))
    end

    private

    # Build a detailed error message with location information
    #
    # @param msg [String] The base error message
    # @return [String] The formatted error message
    def build_message(msg)
      parts = ["#{format.to_s.upcase} Validation Error: #{msg}"]
      parts << "  Line: #{line}" if line
      parts << "  Column: #{column}" if column
      parts << "  Details: #{details}" if details
      parts.join("\n")
    end
  end
end
