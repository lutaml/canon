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
    # Engine choice: Nokogiri on CRuby — per-event C-extension callbacks
    # currently beat FFI SAX (moxml/leptris) by ~1.1-1.4x on large
    # documents. moxml under Opal (rexml adapter, pure Ruby).
    module Sax
      autoload :NokogiriDriver, "canon/xml/sax/nokogiri_driver"
      autoload :MoxmlDriver, "canon/xml/sax/moxml_driver"

      class << self
        # Drive `builder` with the runtime's SAX engine.
        def parse(xml_string, builder)
          if RUBY_ENGINE == "opal"
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
