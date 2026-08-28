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
    # Engine choice: leptris SAX outperforms Nokogiri SAX (1.10x min-of-N
    # on canon's builder, 53KB doc) through moxml 0.5.12's
    # interest-proportional callbacks — BUT the batch-attribute transport
    # reads uninitialized memory at certain buffer offsets, corrupting the
    # first N attributes of an element (leptris-ruby#95). Until that is
    # fixed, CRuby keeps the Nokogiri driver; flipping is the one-line
    # change below.
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
