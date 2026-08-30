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
  # default engine follows it: leptris whenever resolved — its SAX is
  # faster and correct (leptris#625, leptris-ruby#99 fixed), conversion
  # records are light (moxml#143), and conformance parity is complete
  # (engine_parity_spec 12/12, zero pendings). Raw Nokogiri remains the
  # fallback when leptris is absent, and CANON_XML_BACKEND forces either
  # engine. Under Opal the engine is moxml (rexml adapter).
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

        # All flip blockers resolved (leptris#625, leptris-ruby#99,
        # moxml#143): leptris SAX is correct and faster, conversion
        # records are light, conformance parity is 12/12. The leptris
        # engine is the default whenever moxml resolves it; raw
        # Nokogiri remains the fallback when it is absent.
        XmlParsing.moxml_adapter_name == :nokogiri ? :nokogiri : :moxml
      end
    end
  end
end
