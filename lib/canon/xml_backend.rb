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
  # installed and capable; see XmlParsing.moxml_adapter_name). Canon's default
  # engine follows it: leptris whenever available, raw Nokogiri only as the
  # fallback when it is not (wrapping Nokogiri in moxml buys nothing — the
  # wrapper layer adds 2-3x overhead). CANON_XML_BACKEND forces either engine.
  #
  # Known leptris conformance gaps are tracked upstream (leptris/leptris
  # #576/#577/#578) and gated in spec/canon/xml/engine_parity_spec.rb plus
  # engine-conditional pendings in the C14N specs; HTML stays on Nokogiri
  # (Canon::Html::NokogiriSupport) and the pretty-printers keep the Nokogiri
  # pipeline until the moxml serializer matches its output byte-for-byte.
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
        value = ENV["CANON_XML_BACKEND"]
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

        XmlParsing.moxml_adapter_name == :nokogiri ? :nokogiri : :moxml
      end
    end
  end
end
