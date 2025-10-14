# frozen_string_literal: true

require "nokogiri"

module Canon
  module Formatters
    # Base class for HTML formatters with shared canonicalization logic
    class HtmlFormatterBase
      # Block-level HTML elements that should preserve spacing between them
      BLOCK_ELEMENTS = %w[
        address article aside blockquote dd details dialog div dl dt
        fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6
        header hgroup hr li main nav ol p pre section table tbody
        td tfoot th thead tr ul
      ].freeze
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

          # Handle whitespace-only text nodes
          if node.text.strip.empty? && node.parent&.element?
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
            normalized = node.text.gsub(/\s+/, " ")
            # Only strip if the entire parent chain suggests it's appropriate
            # (e.g., at document boundaries)
            if node.parent&.name == "body" &&
                (node.previous_sibling.nil? || node.next_sibling.nil?)
              normalized = normalized.strip
            end
            node.content = normalized
          end
        end
      end

      # Ensure spacing between block element tags in serialized HTML
      # @param html [String] Serialized HTML string
      # @return [String] HTML with proper spacing between block elements
      def self.ensure_block_element_spacing(html)
        # Build regex pattern for block element tags
        block_tags = BLOCK_ELEMENTS.join("|")

        # Add space between closing and opening block element tags
        # Match: ><opening_block_tag or </closing_block_tag><opening_block_tag
        html.gsub(/(<\/(?:#{block_tags})>)(<(?:#{block_tags})[\s>])/, '\1 \2')
      end

      # Check if a node is a block-level element
      # @param node [Nokogiri::XML::Node, nil] Node to check
      # @return [Boolean] true if node is a block element
      def self.block_element?(node)
        node&.element? && BLOCK_ELEMENTS.include?(node.name.downcase)
      end

      private_class_method :sort_attributes, :normalize_whitespace,
                           :ensure_block_element_spacing, :block_element?
    end
  end
end
