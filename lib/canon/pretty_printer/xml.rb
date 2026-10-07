# frozen_string_literal: true

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
        # and tab indentation (moxml#153/#155/#156) and runs faster
        # since moxml#158, with the #167 escaping race fixed in 0.5.28
        # — the fixture integrity suite and the CI performance gate are
        # the standing gates. Nokogiri serves the fallback engine and
        # Opal.
        if RUBY_ENGINE == "opal" || Canon::XmlBackend.moxml?
          moxml_format(xml_string)
        else
          nokogiri_format(xml_string)
        end
      end

      private

      def nokogiri_format(xml_string)
        Canon::NokogiriLoader.require!("Nokogiri-engine XML pretty-printing")
        doc = Nokogiri::XML(xml_string, &:noblanks)

        # The loud/tolerant contract, Nokogiri-lane edition: the
        # non-strict parse recovers malformed input and records the
        # errors — non-HTML malformed input stays loud, HTML-shaped
        # input falls back to the HTML parser (mirrors
        # XmlParsing.parse_with_html_fallback).
        if doc.errors.any?
          unless Canon::XmlParsing.html_shaped?(xml_string)
            raise Moxml::ParseError,
                  doc.errors.map(&:message).join("; ")
          end

          doc = Nokogiri::HTML4(xml_string, &:noblanks)
        end

        if @indent_type == "tab"
          doc.to_xml(indent: 1, indent_text: "\t", encoding: "UTF-8")
        else
          doc.to_xml(indent: @indent, encoding: "UTF-8")
        end
      end

      def moxml_format(xml_string)
        # noblanks mutates the tree (strips whitespace-only text), so
        # the document cannot be readonly. HTML producers' output
        # (Asciidoctor cover pages) routes through the tolerant HTML
        # mode instead of failing the comparison (leptris#1564).
        doc = Canon::XmlParsing.parse_with_html_fallback(
          xml_string, noblanks: true
        )
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
