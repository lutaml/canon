# frozen_string_literal: true

require "moxml"
require "nokogiri"
require_relative "xml/whitespace_normalizer"
require_relative "comparison/xml_comparator"
require_relative "comparison/html_comparator"
require_relative "comparison/json_comparator"
require_relative "comparison/yaml_comparator"

module Canon
  # Comparison module for XML, HTML, JSON, and YAML documents
  # Provides format detection and delegation to format-specific comparators
  module Comparison
    # Comparison result constants
    EQUIVALENT = 1
    MISSING_ATTRIBUTE = 2
    MISSING_NODE = 3
    UNEQUAL_ATTRIBUTES = 4
    UNEQUAL_COMMENTS = 5
    UNEQUAL_DOCUMENTS = 6
    UNEQUAL_ELEMENTS = 7
    UNEQUAL_NODES_TYPES = 8
    UNEQUAL_TEXT_CONTENTS = 9
    MISSING_HASH_KEY = 10
    UNEQUAL_HASH_VALUES = 11
    UNEQUAL_ARRAY_LENGTHS = 12
    UNEQUAL_ARRAY_ELEMENTS = 13
    UNEQUAL_TYPES = 14
    UNEQUAL_PRIMITIVES = 15

    class << self
      # Auto-detect format and compare two objects
      #
      # @param obj1 [Object] First object to compare
      # @param obj2 [Object] Second object to compare
      # @param opts [Hash] Comparison options
      #   - :format - Format hint (:xml, :html, :html4, :html5, :json, :yaml, :string)
      # @return [Boolean, Array] true if equivalent, or array of diffs if verbose
      def equivalent?(obj1, obj2, opts = {})
        # Use format hint if provided
        if opts[:format]
          format1 = format2 = opts[:format]
          # Parse HTML strings if format is html/html4/html5
          if %i[html html4 html5].include?(opts[:format])
            obj1 = parse_html(obj1, opts[:format]) if obj1.is_a?(String)
            obj2 = parse_html(obj2, opts[:format]) if obj2.is_a?(String)
            # Normalize html4/html5 to html for comparison
            format1 = format2 = :html
          end
        else
          format1 = detect_format(obj1)
          format2 = detect_format(obj2)
        end

        # Handle string format (plain text comparison)
        if format1 == :string
          if opts[:verbose]
            return obj1.to_s == obj2.to_s ? [] : [:different]
          else
            return obj1.to_s == obj2.to_s
          end
        end

        # Allow comparing json/yaml strings with ruby objects
        # since they parse to the same structure
        formats_compatible = format1 == format2 ||
          (%i[json ruby_object].include?(format1) &&
           %i[json ruby_object].include?(format2)) ||
          (%i[yaml ruby_object].include?(format1) &&
           %i[yaml ruby_object].include?(format2))

        unless formats_compatible
          raise Canon::CompareFormatMismatchError.new(format1, format2)
        end

        # Normalize format for comparison
        comparison_format = case format1
                            when :ruby_object
                              # If comparing ruby_object with json/yaml, use that format
                              %i[json yaml].include?(format2) ? format2 : :json
                            else
                              format1
                            end

        case comparison_format
        when :xml
          XmlComparator.equivalent?(obj1, obj2, opts)
        when :html
          HtmlComparator.equivalent?(obj1, obj2, opts)
        when :json
          JsonComparator.equivalent?(obj1, obj2, opts)
        when :yaml
          YamlComparator.equivalent?(obj1, obj2, opts)
        end
      end

      private

      # Parse HTML string into Nokogiri document
      #
      # @param content [String, Object] Content to parse (returns as-is if not a string)
      # @param format [Symbol] HTML format (:html, :html4, :html5)
      # @return [Nokogiri::HTML::Document, Nokogiri::HTML5::Document, Nokogiri::HTML::DocumentFragment, Object]
      def parse_html(content, _format)
        return content unless content.is_a?(String)
        return content if content.is_a?(Nokogiri::HTML::Document) ||
          content.is_a?(Nokogiri::HTML5::Document) ||
          content.is_a?(Nokogiri::XML::Document) ||
          content.is_a?(Nokogiri::HTML::DocumentFragment) ||
          content.is_a?(Nokogiri::HTML5::DocumentFragment) ||
          content.is_a?(Nokogiri::XML::DocumentFragment)

        # Let HtmlComparator's parse_node handle parsing with preprocessing
        # For now, just return the string and let it be parsed by HtmlComparator
        content
      rescue StandardError
        content
      end

      # Detect the format of an object
      #
      # @param obj [Object] Object to detect format of
      # @return [Symbol] Format type
      def detect_format(obj)
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
          detect_string_format(obj)
        when Hash, Array
          # Raw Ruby objects (from parsed JSON/YAML)
          :ruby_object
        else
          raise Canon::Error, "Unknown format for object: #{obj.class}"
        end
      end

      # Detect the format of a string
      #
      # @param str [String] String to detect format of
      # @return [Symbol] Format type
      def detect_string_format(str)
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
