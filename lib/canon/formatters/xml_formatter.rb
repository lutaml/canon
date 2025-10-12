# frozen_string_literal: true

require "nokogiri"
require_relative "../xml/c14n"

module Canon
  module Formatters
    # XML formatter using Canonical XML 1.1
    class XmlFormatter
      # Format XML using C14N 1.1
      # @param xml [String] XML document to canonicalize
      # @return [String] Canonical form per W3C C14N 1.1 specification
      def self.format(xml)
        Canon::Xml::C14n.canonicalize(xml, with_comments: false)
      end

      # Parse XML into a Nokogiri document
      # @param xml [String] XML document to parse
      # @return [Nokogiri::XML::Document] Parsed XML document
      def self.parse(xml)
        Nokogiri::XML(xml)
      end
    end
  end
end
