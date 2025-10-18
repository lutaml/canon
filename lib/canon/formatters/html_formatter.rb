# frozen_string_literal: true

require "nokogiri"
require_relative "html_formatter_base"
require_relative "../pretty_printer/html"
require_relative "../validators/html_validator"

module Canon
  module Formatters
    # HTML formatter for HTML 4/5 and XHTML
    class HtmlFormatter < HtmlFormatterBase
      # Parse HTML into a Nokogiri document
      # @param html [String] HTML document to parse
      # @return [Nokogiri::HTML::Document, Nokogiri::XML::Document]
      #   Parsed HTML or XML document
      def self.parse(html)
        # Validate before parsing
        Canon::Validators::HtmlValidator.validate!(html)

        if xhtml?(html)
          Nokogiri::XML(html)
        else
          Nokogiri::HTML5(html)
        end
      end

      # Check if HTML is XHTML
      def self.xhtml?(html)
        html.include?("XHTML") ||
          html.include?('xmlns="http://www.w3.org/1999/xhtml"') ||
          html.match?(/xmlns:\w+/)
      end

      private_class_method :xhtml?
    end
  end
end
