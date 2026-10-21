# frozen_string_literal: true

require "set"

module Canon
  module Formatters
    # Base class for HTML formatters with shared canonicalization logic
    #
    # This abstract base class provides common HTML canonicalization logic
    # for both HTML4 and HTML5 formatters. It handles:
    # - Attribute sorting for consistency
    # - Whitespace normalization
    # - Block element spacing
    #
    # == Canonicalization Process
    #
    # 1. Parse HTML using format-specific parser (subclass responsibility)
    # 2. Sort all element attributes alphabetically
    # 3. Normalize whitespace (remove whitespace-only text nodes, collapse runs)
    # 4. Ensure proper spacing between block-level elements
    # 5. Serialize to HTML string
    #
    # == Subclass Implementation
    #
    # Subclasses must implement the `parse` class method:
    #
    #   def self.parse(html)
    #     # Return Nokogiri::HTML4::Document or Nokogiri::HTML5::Document
    #   end
    #
    # == Block Elements
    #
    # The following elements are treated as block-level and will have spacing
    # preserved between them: address, article, aside, blockquote, dd, details,
    # dialog, div, dl, dt, fieldset, figcaption, figure, footer, form, h1-h6,
    # header, hgroup, hr, li, main, nav, ol, p, pre, section, table, tbody,
    # td, tfoot, th, thead, tr, ul
    #
    # == Usage
    #
    #   # Via subclass (Html4Formatter or Html5Formatter)
    #   canonical_html = Canon::Formatters::Html4Formatter.format(html_string)
    #
    class HtmlFormatterBase
      # Block-level HTML elements that should preserve spacing between them
      BLOCK_ELEMENTS = %w[
        address article aside blockquote dd details dialog div dl dt
        fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6
        header hgroup hr li main nav ol p pre section table tbody
        td tfoot th thead tr ul
      ].freeze

      # HTML elements where whitespace is semantically significant
      # and should NOT be normalized
      WHITESPACE_SENSITIVE_ELEMENTS = %w[
        pre code textarea script style
      ].freeze
      # Set form for the per-sibling hot lookup; Nokogiri lowercases
      # HTML element names, so the downcase fallback only runs for
      # unusual (already-mixed-case) input.
      BLOCK_ELEMENT_SET = BLOCK_ELEMENTS.to_set
      # Compiled once — building the alternation and compiling the
      # regex per format call cost more than the gsub it drives.
      BLOCK_SPACING_PATTERN =
        Regexp.new("(</(?:#{BLOCK_ELEMENTS.join('|')})>)(?:\n*)(<(?:#{BLOCK_ELEMENTS.join('|')})[\s>])").freeze
      # Engine-inserted newlines after a block close, before ANY next
      # tag (the serializer's indent model breaks lines where canon's
      # normalize step kept no text node) — folded to the canonical
      # single space so serialization is idempotent.
      AFTER_BLOCK_NEWLINE_PATTERN =
        Regexp.new("(</(?:#{BLOCK_ELEMENTS.join('|')})>)(\n+)(<(?!/))").freeze
      # Format HTML using canonical form
      # @param html [String] HTML document to canonicalize
      # @return [String] Canonical form of HTML
      def self.format(html)
        doc = parse(html)
        canonicalize(doc)
      end

      # Parse HTML into a Nokogiri document
      # @param html [String] HTML document to parse
      # @return [Nokogiri::HTML::Document, Nokogiri::XML::Document]
      #   Parsed HTML document
      def self.parse(_html)
        raise NotImplementedError,
              "Subclasses must implement the parse method"
      end

      # Canonicalize HTML document
      # @param doc [Moxml::Document] Parsed document
      # @param serializer [:html, :xml] XHTML input must serialize
      #   XML-shaped (self-closed voids) so the output stays
      #   well-formed; HTML input takes the HTML shape.
      # @return [String] Canonical HTML string
      def self.canonicalize(doc, serializer: :html)
        # Sort attributes for consistency
        sort_attributes(doc)

        # Normalize whitespace between elements
        normalize_whitespace(doc)

        # Serialize with consistent formatting — the engine emits no
        # declaration; empty elements self-close in the XML shape.
        html = (if serializer == :xml
                  doc.to_xml(expand_empty: false)
                else
                  doc.to_html
                end).strip

        # Post-process: ensure spaces between block element tags
        # This is needed because Nokogiri's serialization may remove
        # whitespace text nodes between block elements
        ensure_block_element_spacing(html)
      end

      # Sort element attributes alphabetically throughout document
      # (the shared canonical attribute order — TODO.sota/03)
      # @param doc [Moxml::Document] Parsed document
      def self.sort_attributes(doc)
        Canon::Xml::AttributeSorter.sort!(doc)
      end

      # Depth-first element walk (pre-order).
      def self.walk_elements(node, &block)
        return unless node.is_a?(Moxml::Element)

        yield(node)
        node.children.to_a.each { |child| walk_elements(child, &block) }
      end

      # Normalize whitespace by removing whitespace-only text nodes
      # between elements and collapsing whitespace within text content
      # @param doc [Moxml::Document] Parsed document
      def self.normalize_whitespace(doc)
        # Walk parented text nodes only — the engine's content= on a
        # parentless node raises an opaque Invalid argument (upstream
        # note), and parentless text has no canonical meaning anyway.
        walk_text_nodes(doc.root) do |text, parent|
          # CRITICAL: Skip normalization for whitespace-sensitive elements
          # In elements like <pre>, <code>, etc., whitespace is semantically
          # significant and must be preserved exactly as-is
          next if whitespace_sensitive_element?(parent)

          if text.content.match?(Canon::Xml::WhitespacePolicy::STRIP_ONLY)
            # Whitespace-only text: keep one space between block
            # elements (information-preserving canonical form),
            # otherwise remove. The walk yields parented nodes only —
            # the engine content= raises on parentless text upstream.
            if block_element?(prev_element_sibling(parent, text)) ||
                block_element?(next_element_sibling(parent, text)) ||
                block_element?(parent)
              text.content = " "
            else
              text.remove
            end
          else
            # Collapse multiple whitespace characters into single spaces
            # but preserve leading/trailing single spaces for inline content
            content = text.content
            normalized = content.gsub(/\s+/, " ")
            # Only strip if the entire parent chain suggests it's appropriate
            # (e.g., at document boundaries)
            if parent.name == "body" &&
                (first_real_child?(parent, text) || last_real_child?(parent, text))
              normalized = normalized.strip
            end
            # content= re-parses the string — skip it when nothing
            # changed (text with no collapsible whitespace).
            text.content = normalized unless normalized == content
          end
        end
      end

      def self.walk_text_nodes(node, parent = nil, &block)
        case node
        when Moxml::Text
          yield(node, parent) if parent
        when Moxml::Element
          node.children.to_a.each { |child| walk_text_nodes(child, node, &block) }
        end
      end

      def self.prev_element_sibling(parent, text)
        siblings = parent.children.to_a
        idx = siblings.index(text)
        siblings[0...idx].reverse_each.find { |s| s.is_a?(Moxml::Element) }
      end

      def self.next_element_sibling(parent, text)
        siblings = parent.children.to_a
        idx = siblings.index(text)
        siblings[(idx + 1)..].find { |s| s.is_a?(Moxml::Element) }
      end

      def self.first_real_child?(parent, text)
        siblings = parent.children.to_a
        siblings.find { |s| !(s.is_a?(Moxml::Text) && s.content.strip.empty?) }.equal?(text)
      end

      def self.last_real_child?(parent, text)
        siblings = parent.children.to_a
        siblings.reverse_each.find { |s| !(s.is_a?(Moxml::Text) && s.content.strip.empty?) }.equal?(text)
      end

      # Ensure spacing between block element tags in serialized HTML
      # @param html [String] Serialized HTML string
      # @return [String] HTML with proper spacing between block elements
      def self.ensure_block_element_spacing(html)
        # Space between closing and opening block element tags
        # (pattern compiled once — see BLOCK_SPACING_PATTERN)
        html = html.gsub(BLOCK_SPACING_PATTERN, '\1 \2')
        # The engine's serializer inserts its own newlines after a
        # block close when the tree has no whitespace text node there
        # (normalize_whitespace keeps a single space only where one
        # existed). Collapse those self-inserted newlines to the same
        # canonical space — without this, format is not idempotent:
        # pass 1 emits "</p>\n<br>", pass 2 answers "</p> <br>"
        # (the property suite, TODO.sota/03).
        html.gsub(AFTER_BLOCK_NEWLINE_PATTERN, '\1 \3')
      end

      # Check if a node is a block-level element
      # @param node [Nokogiri::XML::Node, nil] Node to check
      # @return [Boolean] true if node is a block element
      def self.block_element?(node)
        return false unless node.is_a?(Moxml::Element)

        name = node.name
        BLOCK_ELEMENT_SET.include?(name) ||
          BLOCK_ELEMENT_SET.include?(name.downcase)
      end

      # Check if a node is a whitespace-sensitive element
      # @param node [Moxml::Element, nil] Node to check
      # @return [Boolean] true if node is whitespace-sensitive
      def self.whitespace_sensitive_element?(node)
        current = node
        while current.is_a?(Moxml::Element)
          name = current.name
          # The downcase fallback only allocates for unusual mixed-case
          # input.
          if WHITESPACE_SENSITIVE_ELEMENTS.include?(name) ||
              WHITESPACE_SENSITIVE_ELEMENTS.include?(name.downcase)
            return true
          end

          current = current.parent
        end
        false
      end

      private_class_method :sort_attributes, :normalize_whitespace,
                           :ensure_block_element_spacing, :block_element?,
                           :whitespace_sensitive_element?
    end
  end
end
