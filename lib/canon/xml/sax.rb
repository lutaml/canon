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
    # Engine choice: the leptris SAX flip is armed but blocked twice over.
    # The batch-attribute corruption (leptris-ruby#95) is answered by a
    # correctness-first path in leptris 1.9.36 — attributes are correct,
    # but that path DROPS namespace declarations from SAX events
    # entirely (raw `["<root xmlns:a=.../>", []]` — xmlns pairs vanish),
    # blinding namespace comparison. Until xmlns reporting is restored
    # (and then the fast path returns with the C fix), CRuby keeps the
    # Nokogiri driver; the flip is the one-line change below. With
    # leptris absent (moxml resolving nokogiri) the driver calls Nokogiri
    # directly — the wrapper layer only adds overhead there.
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
