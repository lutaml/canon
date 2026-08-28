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
  # SSOT: moxml owns adapter preference (Moxml::Config prefers leptris when
  # installed and capable; see XmlParsing.moxml_adapter_name). Canon's
  # default engine is Nokogiri on CRuby until leptris WINS somewhere
  # measurably: conformance parity is complete (engine_parity_spec 12/12),
  # but the leptris SAX driver is blocked by a data-corruption bug
  # (leptris-ruby#95) and the record-based conversion runs ~0.55x Nokogiri
  # (CI performance gate: -42..45% on from_xml) pending lighter record
  # emission upstream. Flipping the default is the one-line change in
  # #detect; CANON_XML_BACKEND=moxml opts in today. Under Opal the engine
  # is moxml (rexml adapter).
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

        :nokogiri
      end
    end
  end
end
