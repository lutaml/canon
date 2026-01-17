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
          when Nokogiri::HTML::DocumentFragment, Nokogiri::HTML5::DocumentFragment
            # HTML DocumentFragments
            :html
          when Nokogiri::XML::DocumentFragment
            # XML DocumentFragments - check if it's actually HTML
            obj.document&.html? ? :html : :xml
          when Nokogiri::XML::Document, Nokogiri::XML::Node
            # Check if it's HTML by looking at the document type
            obj.html? ? :html : :xml
          when Nokogiri::HTML::Document, Nokogiri::HTML5::Document
            :html
          when String
            detect_string(obj)
          when Hash, Array
            # Raw Ruby objects (from parsed JSON/YAML)
            :ruby_object
          else
            raise Canon::Error, "Unknown format for object: #{obj.class}"
          end
        end

        # Detect the format of a string with caching
        #
        # @param str [String] String to detect format of
        # @return [Symbol] Format type
        def detect_string(str)
          # Use cache for format detection
          Cache.fetch(:format_detect, Cache.key_for_format_detection(str)) do
            detect_string_uncached(str)
          end
        end

        # Detect the format of a string without caching
        #
        # @param str [String] String to detect format of
        # @return [Symbol] Format type
        def detect_string_uncached(str)
          trimmed = str.strip

          # YAML indicators
          return :yaml if trimmed.start_with?("---")
          return :yaml if trimmed.match?(/^[a-zA-Z_]\w*:\s/)

          # JSON indicators
          return :json if trimmed.start_with?("{", "[")

          # HTML indicators
          return :html if trimmed.start_with?("<!DOCTYPE html", "<html", "<HTML")

          # XML indicators - must start with < and end with >
          return :xml if trimmed.start_with?("<") && trimmed.end_with?(">")

          # Default to plain string for everything else
          :string
        end
      end
    end
  end
end
