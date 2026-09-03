# frozen_string_literal: true

require "nokogiri" unless RUBY_ENGINE == "opal"

module Canon
  module PrettyPrinter
    class Xml
      def initialize(indent: 2, indent_type: "space")
        @indent = indent.to_i
        @indent_type = indent_type
      end

      def format(xml_string)
        # Output parity: pretty-printed bytes are canon's product. The
        # leptris serializer matches Nokogiri byte-for-byte for space
        # and tab indentation (moxml#153/#155/#156) and runs ~2x faster
        # end-to-end since moxml#158 — the fixture integrity suite and
        # the CI performance gate are the standing gates. Nokogiri
        # serves the fallback engine and Opal.
        if RUBY_ENGINE == "opal" || Canon::XmlBackend.moxml?
          moxml_format(xml_string)
        else
          nokogiri_format(xml_string)
        end
      end

      private

      def nokogiri_format(xml_string)
        doc = Nokogiri::XML(xml_string, &:noblanks)
        if @indent_type == "tab"
          doc.to_xml(indent: 1, indent_text: "\t", encoding: "UTF-8")
        else
          doc.to_xml(indent: @indent, encoding: "UTF-8")
        end
      end

      def moxml_format(xml_string)
        # noblanks mutates the tree (strips whitespace-only text), so
        # the document cannot be readonly.
        doc = Canon::XmlParsing.moxml_context.parse(xml_string, noblanks: true)
        if @indent_type == "tab"
          doc.to_xml(declaration: true, encoding: "UTF-8",
                     indent: 1, indent_text: "\t", expand_empty: false)
        else
          doc.to_xml(declaration: true, encoding: "UTF-8",
                     indent: @indent, expand_empty: false)
        end
      end
    end
  end
end
