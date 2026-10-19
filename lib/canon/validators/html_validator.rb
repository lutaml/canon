# frozen_string_literal: true

module Canon
  module Validators
    # Validator for HTML input
    #
    # Validates HTML input (HTML4, HTML5, or XHTML) through the
    # engine (strict XML parse for XHTML; the WHATWG parse-lint
    # surface for HTML5 — leptris#1771).
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
      # XHTML is XML: the engine strict parse is the validator. The
      # engine reports the failure position as a byte offset embedded
      # in the error message; line/column derive from it.
      def self.validate_xhtml!(input)
        Canon::XmlParsing.moxml_context.parse(input, strict: true)
      rescue Moxml::ParseError => e
        location = extract_engine_location(e, input)
        raise Canon::ValidationError.new(
          e.message.split("\n").first,
          format: :html,
          line: location[:line],
          column: location[:column],
          details: "XHTML validation failed",
        )
      end

      # Derive line/column from the engine error's "at byte N" offset.
      def self.extract_engine_location(error, input)
        byte = error.message[/at byte (\d+)/, 1].to_i
        before = input.byteslice(0, byte) || ""
        line = before.count("\n") + 1
        last_nl = before.rindex("\n")
        column = last_nl ? byte - (last_nl + 1) : byte
        { line: line, column: column }
      end

      # Validate HTML5 input
      #
      # @param input [String] The HTML5 string to validate
      # @raise [Canon::ValidationError] If HTML5 is malformed
      # @return [void]
      # The HTML5 lint layer is engine-served (leptris#1771 delivered
      # the §13.2.5 parse-error token stream: machine-readable code +
      # line + column, RECOVER class). Engine-direct call — the
      # documented seam exception (moxml's parse_html does not forward
      # the collect_errors option yet; ask filed upstream).
      def self.validate_html5!(input)
        doc = Leptris::XML.parse_html(input, mode: :whatwg,
                                             collect_errors: true)
        errors = doc.errors
        return if errors.empty?

        error = errors.first
        raise Canon::ValidationError.new(
          "[#{error.code}] #{error.message}",
          format: :html,
          line: error.line,
          column: error.column,
          details: build_error_details(errors),
        )
      end

      # Build error details from multiple errors
      #
      # @param errors [Array<Leptris::XML::SyntaxError>] Array of errors
      # @return [String, nil] Combined error details
      def self.build_error_details(errors)
        return nil if errors.size <= 1

        errors[1..3].map do |e|
          msg = e.message
          msg += " (line #{e.line})" if e.respond_to?(:line) && e.line
          msg
        end.join("; ")
      end

      private_class_method :xhtml?, :validate_xhtml!, :validate_html5!,
                           :build_error_details,
                           :extract_engine_location
    end
  end
end
