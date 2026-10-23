# frozen_string_literal: true

module Canon
  module Xml
    # XML Canonicalization 1.1 implementation
    # Per W3C Recommendation: https://www.w3.org/TR/xml-c14n11/
    class C14n
      # Canonicalize an XML document
      # @param xml [String] XML document as string
      # @param with_comments [Boolean] Include comments in canonical form
      # @return [String] Canonical form in UTF-8
      def self.canonicalize(xml, with_comments: false)
        if (native = native_canonicalize(xml, with_comments))
          return native
        end

        # Build XPath data model
        root_node = DataModel.from_xml(xml)

        # Process to canonical form
        processor = Processor.new(with_comments: with_comments)
        processor.process(root_node)
      end

      # leptris' C-side C14N 1.1 — 23x faster than the Ruby processor
      # through canon's own API (1MB document) and the DEFAULT lane
      # since libleptris 1.9.178 (gem 1.9.178.0): the leptris#1117
      # families are closed by the native parse-policy knob
      # (`noblanks: true` — same compact bytes as the Ruby lane's
      # parse) and by the canonicalizer itself (whitespace-only PI
      # data dropped, document-level "\n" separators inserted). The
      # one residual byte difference vs the Ruby lane is intentional
      # and a correctness improvement: document-level PIs now
      # serialize in document order (REC-xml-c14n 2.1) instead of
      # the Ruby lane's non-conformant root-first reorder. Relative
      # namespace URIs raise exactly as the Ruby lane does.
      # Comments mode keeps the Ruby path regardless (the native
      # seam exposes no with-comments form). CANON_C14N_BACKEND=ruby
      # forces the stdlib lane.
      def self.native_canonicalize(xml, with_comments)
        return nil if with_comments
        return nil if RUBY_ENGINE == "opal"
        return nil if ENV["CANON_C14N_BACKEND"].to_s.casecmp("ruby").zero?
        return nil unless Canon::XmlBackend.moxml? &&
          Canon::XmlParsing.moxml_adapter_name == :leptris
        return nil unless native_c14n_available?

        validate_relative_namespaces!(xml)

        doc = Canon::XmlParsing.moxml_context.parse(xml,
                                                    readonly: true,
                                                    strict: false,
                                                    noblanks: true)
        begin
          doc.native.c14n(::Leptris::XML::FFI::C14N_1_1, nil,
                          mode: ::Leptris::XML::FFI::C14N_MODE_CANONICAL)
        ensure
          doc.free
        end
      rescue StandardError
        # Malformed inputs are the Ruby path's domain (recovery parse
        # + parse_errors surfacing), not the native lane's.
        nil
      end

      # Canon::Error parity with the Ruby lane, whose parse rejects
      # relative namespace URIs. A declaration-shaped scan; a
      # relative-URI-shaped string inside CDATA is the only false
      # positive this can produce.
      RELATIVE_NS_DECL = /xmlns(?::[\w.-]+)?="([^"]*)"/
      URI_SCHEME = %r{\A[a-zA-Z][a-zA-Z0-9+.-]*:}

      def self.validate_relative_namespaces!(xml)
        return unless xml.is_a?(String)

        xml.scan(RELATIVE_NS_DECL) do |(uri)|
          next if uri.nil? || uri.empty?

          unless uri.match?(URI_SCHEME)
            raise Canon::Error, "Relative namespace URI not allowed: #{uri}"
          end
        end
      end

      def self.native_c14n_available?
        return @native_c14n_available unless @native_c14n_available.nil?

        @native_c14n_available = defined?(::Leptris::XML::FFI::C14N_1_1) &&
          ::Leptris::XML::FFI.constants.include?(:C14N_MODE_CANONICAL)
      end

      def self.reset_native_probe!
        @native_c14n_available = nil
      end

      # Canonicalize a document subset selected by XPath expression.
      #
      # Implements W3C C14N 1.1 subset canonicalization:
      # 1. Evaluates XPath against the document tree
      # 2. Marks matched nodes as the node-set
      # 3. Renders canonical form for only the selected nodes,
      #    with namespace and attribute inheritance from excluded ancestors
      #
      # @param xml [String] XML document as string
      # @param xpath [String] XPath expression for subset selection
      # @param with_comments [Boolean] Include comments in canonical form
      # @return [String] Canonical form in UTF-8
      def self.canonicalize_subset(xml, xpath, with_comments: false)
        root_node = DataModel.from_xml(xml)

        # Evaluate XPath and mark the node-set (the C14N marking law:
        # matched nodes and their descendants; the root always rides)
        matched = XPathEngine.evaluate(root_node, xpath)
        NodeSetMarker.mark(root_node, matched)

        # Process to canonical form
        processor = Processor.new(with_comments: with_comments)
        processor.process(root_node)
      end
    end
  end
end
