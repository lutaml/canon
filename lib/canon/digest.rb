# frozen_string_literal: true

require "openssl"

module Canon
  # W5.3 — canonical digests: the hash of a document's canonical form
  # as a first-class API for deduplication and change detection.
  #
  # The digest is taken over the format's CANONICAL form — the form
  # under which the comparison pipeline deems documents equivalent:
  # XML rides Canonical XML 1.1 (attribute order sorted,
  # namespace-normalized); JSON/YAML ride the key-sorted forms; HTML
  # rides the whitespace-law form with sorted attributes. Two
  # documents that compare equivalent under the canonical form
  # produce identical digests. The digests are stable across releases
  # for as long as the canonical form is (the digest-stability suite
  # pins the bytes per release pair).
  module Digest
    DEFAULT_ALGORITHM = "sha256"

    class << self
      # @param content [String] the document
      # @param format [Symbol] the format (see SUPPORTED_FORMATS)
      # @param algorithm [String, Symbol] any OpenSSL digest name
      # @return [String] the hex digest of the canonical form
      def digest(content, format, algorithm: DEFAULT_ALGORITHM)
        OpenSSL::Digest.new(algorithm.to_s)
          .hexdigest(canonical_form(content, format))
      end

      # The canonical form the digest rides: XML's is C14N (the
      # pretty-printed form preserves attribute order and is NOT
      # canonical); every other format's formatter output IS the
      # canonical form.
      def canonical_form(content, format)
        if format.to_sym == :xml
          Formatters::XmlFormatter.format(content, pretty: false)
        else
          Canon.format(content, format)
        end
      end
    end
  end
end
