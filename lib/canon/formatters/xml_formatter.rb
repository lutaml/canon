# frozen_string_literal: true

require "nokogiri"
require_relative "../xml/c14n"
require_relative "../pretty_printer/xml"
require_relative "../validators/xml_validator"

module Canon
  module Formatters
    # XML formatter using Canonical XML 1.1 or pretty printing
    class XmlFormatter
      # Format XML with pretty printing by default
      # @param xml [String] XML document to format
      # @param pretty [Boolean] Whether to pretty print (default: true)
      # @param indent [Integer] Number of spaces for indentation (default: 2)
      # @return [String] Formatted XML
      def self.format(xml, pretty: true, indent: 2)
        if pretty
          Canon::PrettyPrinter::Xml.new(indent: indent).format(xml)
        else
          Canon::Xml::C14n.canonicalize(xml, with_comments: false)
        end
      end

      # Parse XML into a Nokogiri document
      # @param xml [String] XML document to parse
      # @return [Nokogiri::XML::Document] Parsed XML document
      def self.parse(xml)
        # Validate before parsing
        Canon::Validators::XmlValidator.validate!(xml)
        Nokogiri::XML(xml)
      end
    end
  end
end
