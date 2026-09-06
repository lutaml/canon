# frozen_string_literal: true

require "nokogiri" unless RUBY_ENGINE == "opal"
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
        Regexp.new("(</(?:#{BLOCK_ELEMENTS.join('|')})>)(<(?:#{BLOCK_ELEMENTS.join('|')})[\s>])").freeze
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
      # @param doc [Nokogiri::HTML::Document] Parsed HTML document
      # @return [String] Canonical HTML string
      def self.canonicalize(doc)
        # Sort attributes for consistency
        sort_attributes(doc)

        # Normalize whitespace between elements
        normalize_whitespace(doc)

        # Serialize with consistent formatting
        html = doc.to_html(
          save_with: Nokogiri::XML::Node::SaveOptions::NO_DECLARATION,
        ).strip

        # Post-process: ensure spaces between block element tags
        # This is needed because Nokogiri's serialization may remove
        # whitespace text nodes between block elements
        ensure_block_element_spacing(html)
      end

      # Sort element attributes alphabetically throughout document
      # @param doc [Nokogiri::HTML::Document] Document to process
      def self.sort_attributes(doc)
        doc.traverse do |node|
          next unless node.element?
          next if node.attributes.empty?

          names = node.attributes.keys
          # Already-sorted un-namespaced is the common case — removing
          # and re-adding every attribute is expensive, so check first.
          # Namespaced attributes must take the slow path: the
          # remove/re-add below flattens their prefix, and skipping
          # would change the canonical output.
          next if names.each_cons(2).all? { |a, b| (a <=> b) <= 0 } &&
            node.attributes.each_value.all? { |a| a.namespace.nil? }

          sorted_attrs = node.attributes.sort_by { |name, _| name }
          node.attributes.each_key { |name| node.remove_attribute(name) }
          sorted_attrs.each { |name, attr| node[name] = attr.value }
        end
      end

      # Normalize whitespace by removing whitespace-only text nodes
      # between elements and collapsing whitespace within text content
      # @param doc [Nokogiri::HTML::Document] Document to process
      def self.normalize_whitespace(doc)
        # Normalize whitespace in text nodes
        doc.traverse do |node|
          next unless node.text?

          # CRITICAL: Skip normalization for whitespace-sensitive elements
          # In elements like <pre>, <code>, etc., whitespace is semantically
          # significant and must be preserved exactly as-is
          if whitespace_sensitive_element?(node.parent)
            next
          end

          # Handle whitespace-only text nodes
          if node.text.match?(Canon::Xml::WhitespacePolicy::STRIP_ONLY) && node.parent&.element?
            # Check if this text node is between block-level elements
            prev_sibling = node.previous_sibling
            next_sibling = node.next_sibling

            # If between block elements, preserve one space
            if block_element?(prev_sibling) || block_element?(next_sibling) ||
                block_element?(node.parent)
              node.content = " "
            else
              # Otherwise remove it
              node.remove
            end
          else
            # Collapse multiple whitespace characters into single spaces
            # but preserve leading/trailing single spaces for inline content
            text = node.text
            normalized = text.gsub(/\s+/, " ")
            # Only strip if the entire parent chain suggests it's appropriate
            # (e.g., at document boundaries)
            if node.parent&.name == "body" &&
                (node.previous_sibling.nil? || node.next_sibling.nil?)
              normalized = normalized.strip
            end
            # node.content= re-parses the string — skip it when nothing
            # changed (text with no collapsible whitespace).
            node.content = normalized unless normalized == text
          end
        end
      end

      # Ensure spacing between block element tags in serialized HTML
      # @param html [String] Serialized HTML string
      # @return [String] HTML with proper spacing between block elements
      def self.ensure_block_element_spacing(html)
        # Add space between closing and opening block element tags
        # (pattern compiled once — see BLOCK_SPACING_PATTERN)
        html.gsub(BLOCK_SPACING_PATTERN, '\1 \2')
      end

      # Check if a node is a block-level element
      # @param node [Nokogiri::XML::Node, nil] Node to check
      # @return [Boolean] true if node is a block element
      def self.block_element?(node)
        return false unless node&.element?

        name = node.name
        BLOCK_ELEMENT_SET.include?(name) ||
          BLOCK_ELEMENT_SET.include?(name.downcase)
      end

      # Check if a node is a whitespace-sensitive element
      # @param node [Nokogiri::XML::Node, nil] Node to check
      # @return [Boolean] true if node is whitespace-sensitive
      def self.whitespace_sensitive_element?(node)
        return false unless node&.element?

        # Check if this element or any ancestor is whitespace-sensitive
        current = node
        while current
          if current.element?
            name = current.name
            # Nokogiri lowercases HTML names — the downcase fallback
            # only allocates for unusual mixed-case input.
            if WHITESPACE_SENSITIVE_ELEMENTS.include?(name) ||
                WHITESPACE_SENSITIVE_ELEMENTS.include?(name.downcase)
              return true
            end
          end
          # Stop at document root - documents don't have parents
          break if current.is_a?(Nokogiri::XML::Document) || current.is_a?(Nokogiri::HTML5::Document)

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
