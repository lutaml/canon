# frozen_string_literal: true

require "nokogiri"

module Canon
  module PrettyPrinter
    # Pretty printer for HTML with consistent indentation
    class Html
      def initialize(indent: 2, indent_type: "space")
        @indent = indent.to_i
        @indent_type = indent_type
      end

      # Pretty print HTML with consistent indentation
      def format(html_string)
        # Detect if this is XHTML or HTML
        if xhtml?(html_string)
          format_as_xhtml(html_string)
        else
          format_as_html(html_string)
        end
      end

      private

      def xhtml?(html_string)
        # Check for XHTML DOCTYPE or xmlns attribute
        html_string.include?("XHTML") ||
          html_string.include?('xmlns="http://www.w3.org/1999/xhtml"')
      end

      def format_as_xhtml(html_string)
        # Parse as XML for XHTML
        doc = Nokogiri::XML(html_string, &:noblanks)

        # Use Nokogiri's built-in pretty printing
        if @indent_type == "tab"
          doc.to_xml(indent: 1, indent_text: "\t", encoding: "UTF-8")
        else
          doc.to_xml(indent: @indent, encoding: "UTF-8")
        end
      end

      def format_as_html(html_string)
        # Parse as HTML5
        doc = Nokogiri::HTML5(html_string)

        # Use Nokogiri's built-in pretty printing
        if @indent_type == "tab"
          doc.to_html(indent: 1, indent_text: "\t", encoding: "UTF-8")
        else
          doc.to_html(indent: @indent, encoding: "UTF-8")
        end
      end
    end
  end
end
