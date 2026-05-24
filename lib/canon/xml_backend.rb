# frozen_string_literal: true

module Canon
  # Centralized XML backend detection for Canon.
  #
  # Canon supports two XML backends:
  # - :nokogiri — MRI with Nokogiri installed (default, existing code path)
  # - :moxml    — Opal runtime or MRI without Nokogiri (uses Oga via moxml)
  #
  # The active backend is determined once at load time and cached.
  # All XML-related code should check `Canon::XmlBackend.moxml?` or
  # `Canon::XmlBackend.nokogiri?` to select the appropriate code path.
  #
  # This module intentionally does NOT wrap Nokogiri through moxml.
  # Each backend path is independent — the Nokogiri path is the existing
  # battle-tested code; the moxml path is a parallel implementation for
  # environments where Nokogiri is unavailable.
  module XmlBackend
    class << self
      def active
        @active ||= detect
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

      def detect
        if RUBY_ENGINE == "opal"
          :moxml
        elsif defined?(Nokogiri)
          :nokogiri
        else
          :moxml
        end
      end
    end
  end
end
