# frozen_string_literal: true

require "nokogiri"

module Canon
  module Xml
    # Pretty printer for XML with consistent indentation
    class PrettyPrinter
      def initialize(indent: 2, indent_type: "space")
        @indent = indent.to_i
        @indent_type = indent_type
      end

      # Pretty print XML with consistent indentation
      def format(xml_string)
        doc = Nokogiri::XML(xml_string) do |config|
          config.noblanks
        end

        # Use Nokogiri's built-in pretty printing
        if @indent_type == "tab"
          # For tabs, use indent_text parameter
          doc.to_xml(indent: 1, indent_text: "\t", encoding: "UTF-8")
        else
          # For spaces, use indent parameter
          doc.to_xml(indent: @indent, encoding: "UTF-8")
        end
      end
    end
  end
end
