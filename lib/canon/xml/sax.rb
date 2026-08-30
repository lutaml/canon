# frozen_string_literal: true

module Canon
  module Xml
    # SAX engine selection and driving for the data-model builder.
    #
    # The builder (SaxBuilder) owns tree construction and speaks a single
    # engine-neutral event protocol (Nokogiri-shaped: qname + attribute
    # pairs with xmlns entries inline). Each driver adapts one engine's SAX
    # API to that protocol. OCP: a new engine is a new driver plus one line
    # here; the builder never changes.
    #
    # Engine choice follows the resolved adapter — independent of the
    # DOM engine default: leptris SAX (corruption leptris#625 and the
    # missing xmlns reporting leptris-ruby#99 both fixed) builds canon
    # trees at parity with or faster than Nokogiri SAX, CI-gated. The
    # DOM engine default stays Nokogiri until the record conversion
    # passes the same gate (see XmlBackend). With leptris absent the
    # driver calls Nokogiri directly.
    module Sax
      autoload :NokogiriDriver, "canon/xml/sax/nokogiri_driver"
      autoload :MoxmlDriver, "canon/xml/sax/moxml_driver"

      class << self
        # Drive `builder` with the runtime's SAX engine.
        def parse(xml_string, builder)
          if RUBY_ENGINE == "opal" || Canon::XmlParsing.moxml_adapter_name != :nokogiri
            MoxmlDriver.new(builder).parse(xml_string)
          else
            NokogiriDriver.new(builder).parse(xml_string)
          end
          nil
        end
      end
    end
  end
end
