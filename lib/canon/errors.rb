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

  # Error raised when input exceeds size limits
  #
  # This error is raised when input files or trees exceed configured size
  # limits to prevent performance issues or hangs.
  class SizeLimitExceededError < Error
    attr_reader :limit_type, :actual, :limit

    # Initialize a new SizeLimitExceededError
    #
    # @param limit_type [Symbol] The type of limit exceeded (:file_size,
    #   :node_count, :diff_lines)
    # @param actual [Integer] The actual size that exceeded the limit
    # @param limit [Integer] The configured limit
    def initialize(limit_type, actual, limit)
      @limit_type = limit_type
      @actual = actual
      @limit = limit
      super(build_message)
    end

    private

    # Build a descriptive error message
    #
    # @return [String] The formatted error message
    def build_message
      case limit_type
      when :file_size
        "File size (#{format_bytes(actual)}) exceeds limit (#{format_bytes(limit)}). " \
          "Increase limit via CANON_MAX_FILE_SIZE or config.diff.max_file_size"
      when :node_count
        "Tree node count (#{actual}) exceeds limit (#{limit}). " \
          "Increase limit via CANON_MAX_NODE_COUNT or config.diff.max_node_count"
      when :diff_lines
        "Diff output (#{actual} lines) exceeds limit (#{limit} lines). " \
          "Output truncated. Increase limit via CANON_MAX_DIFF_LINES or config.diff.max_diff_lines"
      else
        "Size limit exceeded: #{limit_type} (#{actual} > #{limit})"
      end
    end

    # Format bytes into human-readable size
    #
    # @param bytes [Integer] Size in bytes
    # @return [String] Formatted size string
    def format_bytes(bytes)
      if bytes < 1024
        "#{bytes} bytes"
      elsif bytes < 1_048_576
        "#{(bytes / 1024.0).round(2)} KB"
      else
        "#{(bytes / 1_048_576.0).round(2)} MB"
      end
    end
  end
end
