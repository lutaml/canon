# frozen_string_literal: true

module Canon
  # Selection of the YAML engine: :psych (stdlib) or :yeptris
  # (FFI over libyeptris — the YAML counterpart of the leptris XML
  # stack).
  #
  # Mirrors XmlBackend's discipline (MECE — this module owns selection,
  # YamlParsing owns the calls). The default stays :psych until the
  # yeptris Psych-safe_load parity gaps close (yeptris-ruby#29 empty
  # documents crash, #30 sexagesimal scalars, #31 >64-bit integers);
  # yeptris is 3.1x faster at loading (measured, 2,000-item document),
  # so CANON_YAML_BACKEND=yeptris opts in early and the default flips
  # once the parity spec runs clean.
  #
  # Only the namespaced API (Yeptris::YAML) is ever used — requiring
  # "yeptris/psych" rebinds the global ::Psych constant for the whole
  # process, which a library must never do.
  module YamlBackend
    VALID_BACKENDS = %i[psych yeptris].freeze

    class << self
      def active
        @active ||= begin
          wanted = forced || :psych
          # A forced yeptris without a loadable gem/native lib must
          # degrade to Psych, not NameError in the gateway.
          wanted = :psych if wanted == :yeptris && !yeptris_available?
          wanted
        end
      end

      def psych?
        active == :psych
      end

      def yeptris?
        active == :yeptris
      end

      def reset!
        @active = nil
      end

      def yeptris_available?
        return false if RUBY_ENGINE == "opal"

        require "yeptris"
        Yeptris::YAML.respond_to?(:load)
      rescue LoadError, StandardError
        false
      end

      private

      def forced
        value = ENV["CANON_YAML_BACKEND"].to_s.downcase
        return nil unless VALID_BACKENDS.include?(value.to_sym)

        value.to_sym
      end
    end
  end
end
