# frozen_string_literal: true

require "nokogiri"
require_relative "html_void_elements"

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
        if xhtml?(html_string)
          format_as_xhtml(html_string)
        else
          format_as_html(html_string)
        end
      end

      private

      def xhtml?(html_string)
        html_string.include?("XHTML") ||
          html_string.include?('xmlns="http://www.w3.org/1999/xhtml"')
      end

      def format_as_xhtml(html_string)
        doc = Nokogiri::XML(html_string, &:noblanks)

        out = if @indent_type == "tab"
                doc.to_xml(indent: 1, indent_text: "\t", encoding: "UTF-8")
              else
                doc.to_xml(indent: @indent, encoding: "UTF-8")
              end

        expand_non_void_self_closing(out)
      end

      def format_as_html(html_string)
        doc = Nokogiri::HTML5(html_string)

        if @indent_type == "tab"
          doc.to_html(indent: 1, indent_text: "\t", encoding: "UTF-8")
        else
          doc.to_html(indent: @indent, encoding: "UTF-8")
        end
      end

      # Rewrite `<tag …/>` into `<tag …></tag>` for every element name that
      # is not an HTML5 void element. `<a/>` is illegal HTML; void tags like
      # `<br/>` and `<img …/>` pass through unchanged.
      def expand_non_void_self_closing(html)
        html.gsub(%r{<([A-Za-z][A-Za-z0-9:_-]*)((?:\s+[^<>"]*(?:"[^"]*"[^<>"]*)*)?)/>}) do
          name = ::Regexp.last_match(1)
          attrs = ::Regexp.last_match(2)
          if HtmlVoidElements.void?(name)
            "<#{name}#{attrs}/>"
          else
            "<#{name}#{attrs}></#{name}>"
          end
        end
      end
    end
  end
end
