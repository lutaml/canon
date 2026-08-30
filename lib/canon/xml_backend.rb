# frozen_string_literal: true

module Canon
  # Selection of the XML engine.
  #
  # Two independent concerns, deliberately separated (MECE):
  # - XML engine — :nokogiri (raw) or :moxml (adapter-mediated). Drives DOM
  #   parsing and serialization of XML (see Canon::XmlParsing).
  # - HTML support — always Nokogiri on CRuby; moxml has no HTML adapter and
  #   leptris no HTML parser (see Canon::Html::NokogiriSupport).
  #
  # SSOT: moxml owns adapter preference (Moxml::Config prefers leptris
  # when installed; see XmlParsing.moxml_adapter_name). The SAX engine
  # follows the resolved adapter — leptris (correct since leptris#625
  # and leptris-ruby#99; CI perf-gated). The DOM engine stays Nokogiri
  # until the record conversion passes the same gate (moxml#143's fix
  # landed; still -40%/-37% from_xml on the CI runner). Conformance
  # parity is complete (engine_parity_spec 12/12, zero pendings).
  # CANON_XML_BACKEND=moxml opts into the leptris DOM engine today.
  #
  # HTML stays on Nokogiri on CRuby (Canon::Html::NokogiriSupport) and the
  # pretty-printers keep the Nokogiri pipeline — pretty-printed bytes are
  # canon's product (moxml#129).
  module XmlBackend
    VALID_BACKENDS = %i[nokogiri moxml].freeze

    class << self
      def active
        @active ||= forced || detect
      end

      def nokogiri?
        active == :nokogiri
      end

      def moxml?
        active == :moxml
      end

      def reset!
        @active = nil
      end

      private

      # Escape hatch and A/B test switch: CANON_XML_BACKEND=nokogiri|moxml.
      def forced
        value = ENV.fetch("CANON_XML_BACKEND", nil)
        return nil if value.nil? || value.empty?

        backend = value.to_sym
        unless VALID_BACKENDS.include?(backend)
          raise Canon::Error,
                "Invalid CANON_XML_BACKEND: #{value.inspect}. " \
                "Must be one of: #{VALID_BACKENDS.join(', ')}"
        end

        backend
      end

      def detect
        return :moxml if RUBY_ENGINE == "opal"

        # The SAX engine flipped to leptris (leptris#625/#99 fixed,
        # CI-gated — see Canon::Xml::Sax), but the DOM conversion still
        # trails Nokogiri on the CI runner (-40%/-37% from_xml after
        # moxml#143's emission fix landed). Nokogiri stays the DOM
        # default until that gate passes; flipping is this one line.
        :nokogiri
      end
    end
  end
end
