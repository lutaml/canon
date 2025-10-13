# frozen_string_literal: true

require "nokogiri"
require_relative "../html/pretty_printer"

module Canon
  module Formatters
    # HTML formatter for HTML 4/5 and XHTML
    class HtmlFormatter
      # Format HTML using canonical form (compact, no indentation)
      # @param html [String] HTML document to canonicalize
      # @return [String] Canonical form of HTML
      def self.format(html)
        # Detect if this is XHTML or HTML
        if xhtml?(html)
          format_xhtml(html)
        else
          format_html(html)
        end
      end

      # Parse HTML into a Nokogiri document
      # @param html [String] HTML document to parse
      # @return [Nokogiri::HTML::Document, Nokogiri::XML::Document]
      #   Parsed HTML or XML document
      def self.parse(html)
        if xhtml?(html)
          Nokogiri::XML(html)
        else
          Nokogiri::HTML5(html)
        end
      end

      # Check if HTML is XHTML
      def self.xhtml?(html)
        html.include?("XHTML") ||
          html.include?('xmlns="http://www.w3.org/1999/xhtml"')
      end

      # Format XHTML using XML canonicalization
      def self.format_xhtml(html)
        doc = Nokogiri::XML(html, &:noblanks)
        # Use compact XML format for canonical XHTML
        doc.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::NO_DECLARATION)
          .strip
      end

      # Format HTML5 using compact format
      def self.format_html(html)
        doc = Nokogiri::HTML5(html)
        # Get the HTML body content without extra formatting
        doc.to_html(save_with: Nokogiri::XML::Node::SaveOptions::NO_DECLARATION)
          .strip
      end

      private_class_method :xhtml?, :format_xhtml, :format_html
    end
  end
end
