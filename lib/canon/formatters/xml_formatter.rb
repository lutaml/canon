# frozen_string_literal: true

require "nokogiri" unless RUBY_ENGINE == "opal"
require_relative "../xml_backend"
require_relative "../xml/c14n"
require_relative "../pretty_printer/xml"
require_relative "../validators/xml_validator"

module Canon
  module Formatters
    class XmlFormatter
      def self.format(xml, pretty: true, indent: 2)
        if pretty
          Canon::PrettyPrinter::Xml.new(indent: indent).format(xml)
        else
          Canon::Xml::C14n.canonicalize(xml, with_comments: false)
        end
      end

      def self.parse(xml)
        Canon::Validators::XmlValidator.validate!(xml)
        if XmlBackend.nokogiri?
          Nokogiri::XML(xml)
        else
          XmlParsing.parse(xml)
        end
      end
    end
  end
end
