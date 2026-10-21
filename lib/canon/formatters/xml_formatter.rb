# frozen_string_literal: true

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

      def self.parse(xml, options = {})
        Canon::Validators::XmlValidator.validate!(xml)
        XmlParsing.parse(xml, options)
      end
    end
  end
end
