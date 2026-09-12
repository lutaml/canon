# frozen_string_literal: true

module Canon
  module Xml
    # Document-level Merkle-digest equivalence gate over leptris'
    # content-defined subtree digests (libleptris #869, leptris-ruby
    # Node#digest since 1.9.144).
    #
    # Equal root digests prove the root subtrees carry identical
    # content (whitespace-only nodes dropped), and every canon match
    # behavior is a relaxation of content identity — so equal digests
    # imply equivalence under any option combination EXCEPT the two
    # restrictions that compare things the digest deliberately
    # ignores (attribute order, comments). The caller excludes those;
    # this module answers the digest question only.
    #
    # A digest miss costs two readonly engine parses (no field
    # materialization, no canon tree) — a fraction of the comparison
    # it precedes. Any parse failure answers false and lets the full
    # pipeline surface the error.
    module DigestGate
      module_function

      def available?
        return false if RUBY_ENGINE == "opal"
        return false unless Canon::XmlBackend.moxml? &&
          Canon::XmlParsing.moxml_adapter_name == :leptris

        # Node#digest is the 1.9.144 surface; feature-detect it on a
        # throwaway document rather than probing the class.
        doc = Canon::XmlParsing.moxml_context.parse("<r/>", readonly: true,
                                                            strict: false)
        root = doc.root
        digestable = !root.native.digest(drop_ws: true).nil?
        doc.free
        digestable
      rescue StandardError
        false
      end

      # True when both documents' root subtrees digest identically
      # AND their document-level skeletons (prolog/epilog comments and
      # PIs — the only doc-level nodes canon compares; doctype and
      # whitespace-only text are excluded) serialize identically.
      # Anything else — parse failure, missing root, digest
      # unavailable — is false: the caller falls through to the full
      # pipeline, which surfaces the real parse errors.
      def equal?(xml1, xml2)
        return false unless xml1.is_a?(String) && xml2.is_a?(String)

        begin
          # xml:space documents carry attribute-scoped whitespace canon
          # makes normative and the digest cannot see — decline them.
          # The scan also declines non-ASCII-compatible encodings
          # (include? raises) — those are the full pipeline's to
          # normalize.
          return false if xml1.include?("xml:space") || xml2.include?("xml:space")
        rescue Encoding::CompatibilityError
          return false
        end

        context = Canon::XmlParsing.moxml_context
        begin
          left = fingerprint(context, xml1)
          right = fingerprint(context, xml2)
          !left.nil? && left == right
        rescue StandardError
          # Any engine-level surprise (encodings, broken input) is the
          # full pipeline's domain — it normalizes and surfaces errors.
          false
        end
      end

      # [root digest, doc-level skeleton] or nil when unparseable.
      def fingerprint(context, xml)
        doc = context.parse(xml, readonly: true, strict: false)
        root = doc.root
        return nil unless root

        skeleton = doc.children.filter_map do |child|
          next if child.equal?(root)

          case child
          when Moxml::Comment, Moxml::ProcessingInstruction then child.to_s
          when Moxml::Text then child.content.strip.empty? ? nil : child.to_s
          end
        end
        [root.native.digest(drop_ws: true), skeleton]
      ensure
        doc&.free
      end
    end
  end
end
