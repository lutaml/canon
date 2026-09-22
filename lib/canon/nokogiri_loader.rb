# frozen_string_literal: true

module Canon
  # Nokogiri is an OPTIONAL dependency.
  #
  # canon's XML engine runs on moxml's resolved adapter — leptris on every
  # platform (leptris ships native gems for all of them, including platforms
  # where nokogiri has no prebuilt). Nokogiri is required only by the raw
  # `CANON_XML_BACKEND=nokogiri` engine and by HTML support (moxml has no
  # HTML adapter). Everything here turns "nokogiri missing" into a loud,
  # actionable Canon::Error at the moment a nokogiri-only feature is used,
  # instead of a LoadError at gem-install or require time.
  module NokogiriLoader
    MSG = "requires the nokogiri gem, which is not installed. " \
          "XML canonicalization, comparison, diffing, and pretty-printing " \
          "work without it (moxml + leptris engine); install nokogiri only " \
          "if you need HTML support or the CANON_XML_BACKEND=nokogiri engine."
    private_constant :MSG

    class << self
      # Load nokogiri or raise a helpful Canon::Error naming the feature.
      # No-op under Opal (matches the historical `unless RUBY_ENGINE`
      # guards).
      def require!(feature)
        return if RUBY_ENGINE == "opal"

        require "nokogiri"
      rescue LoadError
        raise Canon::Error, "#{feature} #{MSG}"
      end

      # True when nokogiri can be loaded (never raises).
      def available?
        return false if RUBY_ENGINE == "opal"

        require "nokogiri"
        true
      rescue LoadError
        false
      end
    end
  end
end
