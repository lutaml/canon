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
      # through canon's own API (1MB document) and byte-identical on
      # the parity corpus, but OPT-IN (CANON_C14N_BACKEND=leptris)
      # pending three families verified against libxml2 ground truth
      # (leptris#1096 follow-up): (1) whitespace-only text between
      # elements is preserved — the Ruby lane's parse drops it and
      # compact bytes are canon's product for every pretty-printed
      # document; (2) whitespace-only processing-instruction data is
      # retained (libxml2 drops it); (3) document-level nodes carry
      # no "\n" separators (the Ruby lane, like libxml2, inserts
      # them). libleptris 1.9.176/177 (gem 1.9.177.0) closed the
      # earlier families — attribute ordering, prefix loss and
      # rebinding, `>`/TAB escaping, redundant namespace
      # redeclarations, xmlns:xml omission — and document-level PIs
      # now serialize in document order (the Ruby processor's
      # root-first order is non-conformant for prolog PIs).
      # Relative namespace URIs raise exactly as the Ruby lane does.
      # Comments mode keeps the Ruby path (the native seam exposes no
      # with-comments form).
      def self.native_canonicalize(xml, with_comments)
        return nil if with_comments
        return nil if RUBY_ENGINE == "opal"
        return nil unless ENV["CANON_C14N_BACKEND"].to_s.casecmp("leptris").zero?
        return nil unless Canon::XmlBackend.moxml? &&
          Canon::XmlParsing.moxml_adapter_name == :leptris
        return nil unless native_c14n_available?

        validate_relative_namespaces!(xml)

        doc = Canon::XmlParsing.moxml_context.parse(xml, readonly: true,
                                                         strict: false)
        begin
          doc.native.canonicalize(::Leptris::XML::FFI::C14N_1_1, nil,
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

        # Mark all nodes as NOT in the node-set initially
        mark_all_nodes(root_node, false)

        # Evaluate XPath and mark matched nodes
        matched = XPathEngine.evaluate(root_node, xpath)

        # If XPath matches root or is empty, fall back to full canonicalization
        if matched.empty?
          mark_all_nodes(root_node, true)
        else
          # Mark matched nodes and their ancestors/descendants
          mark_subset(root_node, matched)
        end

        # Process to canonical form
        processor = Processor.new(with_comments: with_comments)
        processor.process(root_node)
      end

      class << self
        private

        # Recursively set in_node_set on all nodes
        def mark_all_nodes(node, value)
          node.in_node_set = value
          node.children.each { |child| mark_all_nodes(child, value) }
        end

        # Mark matched nodes and all required supporting nodes.
        #
        # Per W3C C14N 1.1, only nodes in the node-set are rendered.
        # Ancestors not in the node-set become "omitted ancestors" —
        # the Processor handles namespace/attribute inheritance from them.
        def mark_subset(root_node, matched)
          # Mark matched nodes and their descendants
          matched.each do |node|
            mark_node_and_descendants(node)
          end

          # Root node is always in the set so processing starts
          root_node.in_node_set = true
        end

        def mark_node_and_descendants(node)
          node.in_node_set = true
          node.children.each { |child| mark_node_and_descendants(child) }
        end
      end
    end
  end
end
