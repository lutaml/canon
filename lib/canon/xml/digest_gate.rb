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

      # moxml 0.5.76+ (moxml#271) surfaces the engine's recover
      # diagnostics — duplicate-attribute events and the like (#1200)
      # — as Document#parse_diagnostics. The direct-leptris-FFI
      # reach-in this replaced was the gate's one documented seam
      # exception; the wrapper ends it.
      def recover_diags?(doc)
        !doc.parse_diagnostics.empty?
      end

      # Whether the HOST opted into attribute-order-sensitive digests
      # (libleptris 1.9.228 honors LEPTRIS_DIGEST_ATTR_ORDER per
      # digest call; leptris#1297). Canon reads the env — never
      # writes it: the flag re-spaces digest values process-wide, so
      # enabling it is the host's call, not a library's. When set,
      # digest equality proves attribute-order identity too, and the
      # verbose lane's signature probe becomes redundant.
      def attr_order_digest?
        ENV["LEPTRIS_DIGEST_ATTR_ORDER"] == "1"
      end

      def available?
        return false if RUBY_ENGINE == "opal"
        return false unless Canon::XmlBackend.moxml? &&
          Canon::XmlParsing.moxml_adapter_name == :leptris

        # moxml Node#digest (moxml#173) wraps leptris Node#digest;
        # feature-detect on a throwaway document.
        doc = Canon::XmlParsing.moxml_context.parse("<r/>", readonly: true,
                                                            strict: false)
        root = doc.root
        digestable = !root.digest(drop_ws_text: true).nil?
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

      # The shared fingerprint ([root digest, doc-level skeleton])
      # when both documents digest identically AND both parse clean of
      # recover errors; nil otherwise. The verbose lane certifies
      # before skipping the pipeline: error-bearing documents decline
      # so the pipeline can produce the identical verbose report
      # (parse-error banner included) it always has.
      def certify(xml1, xml2)
        return nil unless xml1.is_a?(String) && xml2.is_a?(String)

        begin
          return nil if xml1.include?("xml:space") || xml2.include?("xml:space")
        rescue Encoding::CompatibilityError
          return nil
        end

        context = Canon::XmlParsing.moxml_context
        begin
          left = fingerprint(context, xml1, clean: true)
          right = fingerprint(context, xml2, clean: true)
          return nil if left.nil? || left != right

          left
        rescue StandardError
          nil
        end
      end

      # [root digest, doc-level skeleton] or nil when unparseable.
      # With `clean:` a document carrying recover errors also answers
      # nil — only certify uses that; the boolean lane keeps the
      # historical verdict for recovered-equal pairs.
      def fingerprint(context, xml, clean: false)
        doc = context.parse(xml, readonly: true, strict: false)
        root = doc.root
        return nil unless root

        if clean
          return nil if doc.parse_errors.any?
          return nil if recover_diags?(doc)
        end

        skeleton = doc.children.filter_map do |child|
          next if Canon::XmlParsing.same_engine_node?(child, root)

          case child
          when Moxml::Comment, Moxml::ProcessingInstruction then child.to_s
          when Moxml::Text then child.content.strip.empty? ? nil : child.to_s
          end
        end
        digest = root.digest(drop_ws_text: true)
        # nil digest means the adapter has no Merkle support — never
        # treat two nils as equal (that would false-positive under
        # Opal / non-leptris backends where every tree digests nil).
        return nil if digest.nil?

        [digest, skeleton]
      ensure
        doc&.free
      end
    end
  end
end
