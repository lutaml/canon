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
  # when installed; see XmlParsing.moxml_adapter_name). Both engines
  # follow the resolved adapter: SAX since leptris#625/#99 were fixed,
  # DOM since moxml#143's materialize_fields stream (zero-allocation
  # flat buffers) made the conversion competitive. Conformance parity
  # is complete (engine_parity_spec 12/12). CANON_XML_BACKEND forces
  # either engine; the CI performance gate is the standing referee.
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

        # Both engines now run leptris: SAX since leptris#625/#99
        # (CI-gated), DOM since moxml#143's zero-allocation
        # materialize_fields stream made the conversion competitive.
        # The CI performance gate is the standing referee.
        XmlParsing.moxml_adapter_name == :nokogiri ? :nokogiri : :moxml
      end
    end
  end
end
