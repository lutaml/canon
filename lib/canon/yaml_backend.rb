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

      # The JSON fast path needs the fused C-API materializer
      # (Yeptris::Native — load_json) specifically: the FFI ladder is
      # ~29x slower than the stdlib JSON C extension, so JSON loads
      # fall back to stdlib when only FFI is present.
      def yeptris_native?
        yeptris? && yeptris_available? && !defined?(::Yeptris::Native).nil?
      end

      # JSON defaults to the strict yeptris surface whenever the
      # native materializer is installed (0.1.13.4 ships platform
      # gems — zero compilation, zero env). JSON parity is
      # spec-pinned to JSON.parse upstream and complete except the
      # #37 duplicate-keys leniency; YAML keeps waiting on #30/#31
      # and stays behind the env opt-in. CANON_YAML_BACKEND=psych
      # forces both formats back to stdlib.
      def json_yeptris?
        return false if RUBY_ENGINE == "opal"
        return false if ENV["CANON_YAML_BACKEND"].to_s.casecmp("psych").zero?

        # Independent of the YAML selection: the strict JSON surface
        # is complete on its own, so JSON does not wait for #30/#31.
        yeptris_available? && !defined?(::Yeptris::Native).nil?
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
