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
        # moxml serializer cannot yet match Nokogiri's output (empty
        # element expansion, declaration placement, tab indent), so the
        # Nokogiri pipeline is used whenever available — the moxml branch
        # is the Opal fallback.
        if defined?(Nokogiri)
          nokogiri_format(xml_string)
        else
          moxml_format(xml_string)
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
        doc = Canon::XmlParsing.parse(xml_string)
        doc.to_xml
      end
    end
  end
end
