# frozen_string_literal: true

module Canon
  module Comparison
    # Format detection service for auto-detecting document formats
    #
    # Provides format detection for various document types including XML, HTML,
    # JSON, YAML, and plain text. Uses caching for performance optimization.
    #
    # @example Detect format from a string
    #   FormatDetector.detect("<root>content</root>") # => :xml
    #
    # @example Detect format from an object
    #   FormatDetector.detect(Moxml::Document.new) # => :xml
    class FormatDetector
      # Supported format types
      FORMATS = %i[xml html json yaml ruby_object string].freeze

      class << self
        # Detect the format of an object
        #
        # @param obj [Object] Object to detect format of
        # @return [Symbol] Format type (:xml, :html, :json, :yaml, :ruby_object, :string)
        def detect(obj)
          case obj
          when Moxml::Node, Moxml::Document
            :xml
          when String
            detect_string(obj)
          when Hash, Array
            :ruby_object
          else
            detect_nokogiri(obj)
          end
        end

        # Nokogiri nodes arrive from user input regardless of the active
        # XML engine, so detection is by node type (Opal never sees them —
        # Nokogiri is not loaded there).
        def detect_nokogiri(obj)
          return :html if defined?(Nokogiri) && obj.is_a?(Nokogiri::HTML::DocumentFragment)
          return :html if defined?(Nokogiri) && obj.is_a?(Nokogiri::HTML5::DocumentFragment)

          if defined?(Nokogiri) && obj.is_a?(Nokogiri::XML::DocumentFragment)
            return obj.document&.html? ? :html : :xml
          end
          if defined?(Nokogiri) && (obj.is_a?(Nokogiri::XML::Document) || obj.is_a?(Nokogiri::XML::Node))
            return obj.html? ? :html : :xml
          end
          return :html if defined?(Nokogiri) && obj.is_a?(Nokogiri::HTML::Document)
          return :html if defined?(Nokogiri) && obj.is_a?(Nokogiri::HTML5::Document)

          raise Canon::Error, "Unknown format for object: #{obj.class}"
        end

        # Detect the format of a string with caching
        #
        # @param str [String] String to detect format of
        # @return [Symbol] Format type
        def detect_string(str)
          # Use cache for format detection
          Cache.fetch(:format_detect, Cache.key_for_format_detection(str)) do # rubocop:disable Lint/UselessDefaultValueArgument
            detect_string_uncached(str)
          end
        end

        # Detect the format of a string without caching
        #
        # @param str [String] String to detect format of
        # @return [Symbol] Format type
        def detect_string_uncached(str)
          # Convert to UTF-8 for consistent handling if possible
          # This handles cases like UTF-16 encoded XML that would otherwise fail string operations
          str_utf8 = if ["UTF-16", "UTF-16BE",
                         "UTF-16LE"].include?(str.encoding.name)
                       begin
                         str.encode("UTF-8", str.encoding, invalid: :replace,
                                                           undef: :replace, replace: "?")
                       rescue EncodingError
                         str.dup.force_encoding("BINARY").encode("UTF-8")
                       end
                     else
                       str
                     end

          trimmed = str_utf8.strip

          # YAML indicators
          return :yaml if trimmed.start_with?("---")
          return :yaml if trimmed.match?(/^[a-zA-Z_]\w*:\s/)

          # JSON indicators
          return :json if trimmed.start_with?("{", "[")

          # HTML indicators
          return :html if trimmed.start_with?("<!DOCTYPE html", "<html",
                                              "<HTML")

          # XML indicators - must start with < and end with >
          return :xml if trimmed.start_with?("<") && trimmed.end_with?(">")

          # Default to plain string for everything else
          :string
        end
      end
    end
  end
end
