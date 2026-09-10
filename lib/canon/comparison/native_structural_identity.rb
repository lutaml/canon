# frozen_string_literal: true

module Canon
  module Comparison
    # Optional leptris-accelerated structural-identity check.
    #
    # libleptris (>= 1.9.127) ships a native tree diff whose equal
    # case prunes subtrees by content-defined Merkle digest (#869):
    # answering "are these two XML strings structurally identical?"
    # costs two C-level parses plus one digest compare per subtree,
    # skipping canon's Ruby comparison pipeline entirely.
    #
    # Soundness: the check only ever answers TRUE for trees the
    # digest proves identical, and structural identity implies
    # equivalence under every canon profile (profiles forgive
    # differences; none create them). A nil answer (engine absent,
    # parse failure, mismatched roots) means "no opinion" and the
    # caller falls through to the normal pipeline.
    module NativeStructuralIdentity
      class << self
        # True when the leptris gem with the diff surface is
        # loaded. The gem is an optional accelerator (dev-only
        # dependency in the Gemfile); nothing in canon requires it.
        def available?
          !defined?(::Leptris::XML::Diff).nil?
        end

        # true / false when the engine decides; nil when it cannot
        # (either string fails to parse — the pipeline then reports
        # the error in canon's own shape).
        def identical?(str1, str2)
          a = parse(str1)
          b = parse(str2)
          return nil if a.nil? || b.nil?
          ::Leptris::XML::Diff.identical?(a, b)
        rescue StandardError
          nil
        end

        private

        def parse(str)
          ::Leptris::XML::Document.parse(str)
        rescue StandardError
          nil
        end
      end
    end
  end
end
