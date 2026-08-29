# frozen_string_literal: true

module Canon
  module Xml
    # Builds Canon::Xml::Node tree from SAX events.
    #
    # Engine-neutral: the event protocol is Nokogiri-shaped (qname +
    # attribute pairs with xmlns declarations inline); Canon::Xml::Sax
    # selects the driver. Much faster than DOM parsing + conversion —
    # no intermediate engine DOM tree, no traversal conversion pass.
    #
    # Construction goes through TreeBuilder like every other feed:
    # this class owns only what is SAX-specific — qname parsing, xmlns
    # separation, character-reference decoding, adjacency combining,
    # the namespace stack, and document-level reordering.
    #
    # Usage:
    #   root = SaxBuilder.parse(xml_string, preserve_whitespace: false)
    #   # root is a Canon::Xml::Nodes::RootNode
    #
    # For C14N, use strip_doctype: true to avoid DTD default attribute expansion:
    #   root = SaxBuilder.parse(xml_string, strip_doctype: true)
    #
    class SaxBuilder
      # Parse XML string and return Canon::Xml::Node tree
      #
      # @param xml_string [String] XML content to parse
      # @param preserve_whitespace [Boolean] Whether to preserve whitespace-only text nodes
      # @param strip_doctype [Boolean] Strip DOCTYPE before parsing (for C14N to avoid DTD default attrs)
      # @return [Nodes::RootNode] Root of the data model tree
      def self.parse(xml_string, preserve_whitespace: false,
strip_doctype: false)
        # Strip DOCTYPE to prevent the SAX engine from expanding DTD default attributes
        # This is needed for C14N which should NOT include default attributes from DTD
        # Use string methods instead of complex regex to avoid ReDoS vulnerability
        if strip_doctype
          xml_string = strip_doctype_declaration(xml_string)
        end

        builder = new(preserve_whitespace: preserve_whitespace)
        Canon::Xml::Sax.parse(xml_string, builder)
        builder.result
      end

      # Strip DOCTYPE declaration without using complex regex
      # This avoids ReDoS vulnerability from patterns like \s+ and [^>]*
      #
      # @param xml [String] XML string potentially containing DOCTYPE
      # @return [String] XML string with DOCTYPE removed
      def self.strip_doctype_declaration(xml)
        # Find DOCTYPE start (case-insensitive)
        doctype_start = xml.upcase.index("<!DOCTYPE")
        return xml unless doctype_start

        # Find the end of DOCTYPE - it ends with >
        # Handle both simple DOCTYPE and those with internal subset [...]
        pos = doctype_start + 9 # length of "<!DOCTYPE"
        in_bracket = false

        while pos < xml.length
          char = xml[pos]
          if char == "[" && !in_bracket
            in_bracket = true
          elsif char == "]" && in_bracket
            in_bracket = false
          elsif char == ">" && !in_bracket
            # Found the end of DOCTYPE
            return xml[0...doctype_start] + xml[(pos + 1)..]
          end
          pos += 1
        end

        # If we didn't find a proper end, just return original
        xml
      end

      # Initialize the SAX builder
      #
      # @param preserve_whitespace [Boolean] Whether to preserve whitespace-only text nodes
      def initialize(preserve_whitespace: false)
        @preserve_whitespace = preserve_whitespace
        @root = Nodes::RootNode.new
        @stack = [@root]
        # Track in-scope namespaces at each level
        # Each entry is a hash of prefix => uri
        @namespace_stack = [build_initial_namespaces]
        # Captured libxml errors during SAX parsing.  Surfaced on the
        # resulting RootNode so the diff report can warn the user
        # when a FATAL parse error has caused content loss
        # (see lutaml/canon#130).
        @parse_errors = []
      end

      # SAX callbacks for libxml errors and warnings.  Without these
      # overrides the default handlers swallow the events; with them,
      # libxml's "Attribute xml:lang redefined" and similar messages
      # land in @parse_errors and ride through to ComparisonResult.
      def error(string)
        @parse_errors << string.to_s.strip
      end

      def warning(string)
        @parse_errors << string.to_s.strip
      end

      # Called when an element starts
      #
      # @param name [String] Element name (may include prefix like "ns:element")
      # @param attrs [Array] Array of [name, value] pairs
      def start_element(name, attrs = [])
        parent = @stack.last

        # Parse namespace from name (prefix:localname or just localname)
        prefix, local_name = parse_qname(name)

        # Separate namespace declarations from regular attributes
        ns_decls, regular_attrs = separate_namespaces(attrs)

        # Check for relative namespace URIs (before building hash)
        # Convert to hash for iteration
        ns_hash = build_ns_hash(ns_decls)
        ns_hash.each_value do |uri|
          next if uri.nil? || uri.empty?

          if relative_uri?(uri)
            raise Canon::Error,
                  "Relative namespace URI not allowed: #{uri}"
          end
        end

        # Push new namespace scope with declarations (own shadows
        # inherited — the same merge the TreeBuilder scope kernel applies)
        new_scope = @namespace_stack.last.merge(ns_hash)
        @namespace_stack.push(new_scope)

        element = TreeBuilder::DEFAULT.element(
          name: local_name,
          prefix: prefix,
          namespace_uri: new_scope[prefix.to_s],
          namespace_scope: new_scope,
          attributes: regular_attrs.map do |attr_name, attr_value|
            attr_prefix, attr_local = parse_qname(attr_name)
            attr_ns_uri = attr_prefix ? new_scope[attr_prefix] : nil
            [attr_local, decode_character_references(attr_value || ""), attr_ns_uri, attr_prefix]
          end,
        )

        parent.add_child(element)
        @stack.push(element)
      end

      # Called when an element ends
      #
      # @param _name [String] Element name (unused)
      def end_element(_name)
        @stack.pop
        @namespace_stack.pop
      end

      # Called for text content
      #
      # @param string [String] Text content
      def characters(string)
        return if string.nil?

        append_text(decode_character_references(string), string)
      end

      # Called for CDATA content. CDATA is literal character data:
      # character references inside it are NOT decoded (a literal
      # &#65; stays as written), unlike regular text where they are
      # resolved. Whitespace and adjacency rules match characters so
      # the two forms of character data build identical trees.
      #
      # @param string [String] CDATA content
      def cdata(string)
        return if string.nil?

        append_text(string, string)
      end

      # Append character data to the tree: combine with an adjacent
      # text node if present, else create one (respecting the
      # whitespace-only skip rules).
      #
      # @param decoded_string [String] value with character references resolved
      # @param raw_string [String] value as delivered (pre-resolution)
      def append_text(decoded_string, raw_string)
        parent = @stack.last

        # Combine with previous text node if adjacent (SAX can split text content)
        # This MUST happen before whitespace check, because SAX may split "foo "
        # into "foo" and " " callbacks - we need to combine them before deciding
        # whether to skip whitespace
        last_child = parent.children.last
        if last_child&.node_type == :text
          # Combine both raw and decoded forms
          last_child.value = last_child.value + decoded_string
          last_child.original = (last_child.original || "") + raw_string
          return
        end

        # Skip whitespace-only text nodes unless preserving, per the SAX
        # policy (CR-bearing content always survives for C14N;
        # non-ASCII whitespace is meaningful content; document-level
        # whitespace drops with every policy).
        return unless WhitespacePolicy.keep_sax_text?(decoded_string,
                                                      preserve_whitespace: @preserve_whitespace,
                                                      element_parent: parent.node_type == :element)

        parent.add_child(
          TreeBuilder::DEFAULT.text(decoded_string, keep: true, original: raw_string),
        )
      end
      private :append_text

      # Called for comments
      #
      # @param string [String] Comment content
      def comment(string)
        @stack.last.add_child(TreeBuilder::DEFAULT.comment(string))
      end

      # Called for processing instructions
      #
      # @param name [String] PI target
      # @param content [String] PI content
      def processing_instruction(name, content)
        @stack.last.add_child(
          TreeBuilder::DEFAULT.processing_instruction(name, content || ""),
        )
      end

      # Return the built tree
      #
      # @return [Nodes::RootNode] Root of the tree
      def result
        # Reorder children so that the document element comes first,
        # followed by PIs and comments outside the document element
        # (C14N requires this ordering)
        reorder_children(@root)
        @root.parse_errors = @parse_errors if @parse_errors.any?
        @root
      end

      # Reorder root children so document element comes first
      # followed by PIs and comments (outside document element)
      def reorder_children(root)
        doc_element = root.children.find { |c| c.node_type == :element }
        return unless doc_element

        other_children = root.children.reject { |c| c.node_type == :element }
        root.children = [doc_element] + other_children
      end

      private

      # Build initial namespace scope (includes xml namespace)
      #
      # @return [Hash] Namespace prefix => URI mapping
      def build_initial_namespaces
        {
          "xml" => "http://www.w3.org/XML/1998/namespace",
        }
      end

      # Build namespace hash from declarations array
      #
      # @param ns_decls [Array] Array of [name, value] pairs for namespace declarations
      # @return [Hash] Namespace prefix => URI mapping
      def build_ns_hash(ns_decls)
        result = {}
        ns_decls.each do |name, uri|
          # xmlns="..." for default namespace, xmlns:prefix="..." for prefixed
          prefix = if name == "xmlns"
                     ""
                   else
                     name.sub("xmlns:", "")
                   end
          result[prefix] = uri
        end
        result
      end

      # Parse a QName into prefix and local name
      #
      # @param qname [String] QName like "prefix:local" or "local"
      # @return [Array<(String, String)>] [prefix, local_name] - prefix may be nil
      def parse_qname(qname)
        if qname.include?(":")
          parts = qname.split(":", 2)
          [parts[0], parts[1]]
        else
          [nil, qname]
        end
      end

      # Separate namespace declarations from regular attributes
      #
      # @param attrs [Array] Array of [name, value] pairs
      # @return [Array] Two arrays: [namespace_decls, regular_attrs]
      def separate_namespaces(attrs)
        ns_decls = []
        regular_attrs = []

        attrs.each do |name, value|
          if name == "xmlns" || name.start_with?("xmlns:")
            ns_decls << [name, value]
          else
            regular_attrs << [name, value]
          end
        end

        [ns_decls, regular_attrs]
      end

      # Decode numeric character references (e.g., &#38; → &)
      #
      # @param value [String] String potentially containing character references
      # @return [String] String with character references decoded
      def decode_character_references(value)
        value.gsub(/&#(x?[0-9a-fA-F]+);/) do |match|
          code_str = Regexp.last_match(1)
          code_point = if code_str.start_with?("x")
                         # Hexadecimal: &#xHHHH;
                         code_str[1..].to_i(16)
                       else
                         # Decimal: &#DDDD;
                         code_str.to_i
                       end
          # Convert code point to character (UTF-8)
          [code_point].pack("U")
        rescue StandardError
          # If conversion fails, keep original
          match
        end
      end

      # Check if a URI is relative
      #
      # @param uri [String] URI to check
      # @return [Boolean] true if relative
      def relative_uri?(uri)
        # A URI is relative if it doesn't have a scheme
        uri !~ %r{^[a-zA-Z][a-zA-Z0-9+.-]*:}
      end
    end
  end
end
