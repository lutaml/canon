# frozen_string_literal: true

require "nokogiri"
require_relative "xml_comparator"
require_relative "match_options"
require_relative "../diff/diff_node"
require_relative "../diff/diff_classifier"

module Canon
  module Comparison
    # HTML comparison class
    # Handles comparison of HTML nodes with various options
    class HtmlComparator
      # Default comparison options for HTML
      DEFAULT_OPTS = {
        # Structural filtering options
        ignore_children: false,
        ignore_text_nodes: false,
        ignore_attr_content: [],
        ignore_attrs: [],
        ignore_attrs_by_name: [],
        ignore_nodes: [],

        # Output options
        verbose: false,
        diff_children: false,

        # Match system options
        match_profile: nil,
        match: nil,
        preprocessing: nil,
        global_profile: nil,
        global_options: nil,

        # Diff display options
        diff: nil,
      }.freeze

      class << self
        # Compare two HTML nodes for equivalence
        #
        # @param html1 [String, Nokogiri::HTML::Document] First HTML
        # @param html2 [String, Nokogiri::HTML::Document] Second HTML
        # @param opts [Hash] Comparison options
        # @param child_opts [Hash] Options for child comparison
        # @return [Boolean, Array] true if equivalent, or array of diffs if
        #   verbose
        def equivalent?(html1, html2, opts = {}, child_opts = {})
          opts = DEFAULT_OPTS.merge(opts)

          # Resolve match options with format-specific defaults
          match_opts_hash = MatchOptions::Xml.resolve(
            format: :html,
            match_profile: opts[:match_profile],
            match: opts[:match],
            preprocessing: opts[:preprocessing],
            global_profile: opts[:global_profile],
            global_options: opts[:global_options],
          )

          # Wrap in ResolvedMatchOptions for DiffClassifier
          match_opts = Canon::Comparison::ResolvedMatchOptions.new(
            match_opts_hash,
            format: :html,
          )

          # Store resolved match options hash for use in comparison logic
          opts[:match_opts] = match_opts_hash

          # Create child_opts with resolved options
          child_opts = opts.merge(child_opts)

          # Parse nodes if they are strings, applying preprocessing if needed
          node1 = parse_node(html1, match_opts_hash[:preprocessing])
          node2 = parse_node(html2, match_opts_hash[:preprocessing])

          # Serialize preprocessed nodes for diff display (avoid re-preprocessing)
          preprocessed_str1 = serialize_for_display(node1)
          preprocessed_str2 = serialize_for_display(node2)

          differences = []
          diff_children = opts[:diff_children] || false

          # DocumentFragment nodes need special handling - compare their children
          # instead of the fragment nodes themselves
          if node1.is_a?(Nokogiri::HTML4::DocumentFragment) &&
              node2.is_a?(Nokogiri::HTML4::DocumentFragment)
            # Compare children of fragments
            children1 = node1.children.to_a
            children2 = node2.children.to_a

            if children1.length != children2.length
              result = Comparison::UNEQUAL_ELEMENTS
            elsif children1.empty?
              result = Comparison::EQUIVALENT
            else
              # Compare each pair of children
              result = Comparison::EQUIVALENT
              children1.zip(children2).each do |child1, child2|
                child_result = XmlComparator.send(:compare_nodes, child1, child2,
                                                  opts, child_opts, diff_children,
                                                  differences)
                if child_result != Comparison::EQUIVALENT
                  result = child_result
                  break
                end
              end
            end
          else
            result = XmlComparator.send(:compare_nodes, node1, node2, opts,
                                        child_opts, diff_children, differences)
          end

          # Classify DiffNodes as active/inactive if we have verbose output
          if opts[:verbose] && !differences.empty?
            classifier = Canon::Diff::DiffClassifier.new(match_opts)
            classifier.classify_all(differences.select { |d| d.is_a?(Canon::Diff::DiffNode) })
          end

          if opts[:verbose]
            {
              differences: differences,
              preprocessed: [preprocessed_str1, preprocessed_str2],
              html_version: detect_html_version_from_node(node1),
            }
          else
            result == Comparison::EQUIVALENT
          end
        end

        private

        # Parse a node from string or return as-is
        # Applies preprocessing transformation before parsing if specified
        def parse_node(node, preprocessing = :none)
          # If already a Nokogiri node, check for incompatible XML documents
          # Only raise error for non-string incompatible formats
          unless node.is_a?(String)
            # Detect if this is an XML document (not HTML)
            # Strings are allowed since they can be wrapped/parsed as needed
            if is_xml_document?(node)
              raise Canon::CompareFormatMismatchError.new(:xml, :html)
            end
            # For :rendered preprocessing, apply normalization even to pre-parsed nodes
            if preprocessing == :rendered
              # If already a DocumentFragment with :rendered, just normalize it
              if node.is_a?(Nokogiri::HTML4::DocumentFragment) ||
                  node.is_a?(Nokogiri::HTML5::DocumentFragment) ||
                  node.is_a?(Nokogiri::XML::DocumentFragment)
                # Normalize whitespace directly without re-parsing
                normalize_html_style_script_comments(node)
                normalize_rendered_whitespace(node)
                return node
              end

              # Normalize whitespace directly without re-parsing
              normalize_html_style_script_comments(node)
              normalize_rendered_whitespace(node)
              return node
            end

            # For other preprocessing, just return the node (including DocumentFragments)
            return node
          end

          # Check if string contains XML declaration - this indicates XML not HTML
          if node.strip.start_with?("<?xml")
            raise Canon::CompareFormatMismatchError.new(:xml, :html)
          end

          # For :rendered preprocessing, handle separately to avoid double-parsing
          if preprocessing == :rendered
            # Check if this is a full HTML document or a fragment
            # Use full document parsing if it has <html> tag
            if node.match?(/<html[\s>]/i)
              doc = Nokogiri::HTML(node, &:noblanks)
              normalize_html_style_script_comments(doc)
              normalize_rendered_whitespace(doc)
              remove_whitespace_only_text_nodes(doc)
              return doc
            else
              # Use fragment for partial HTML
              frag = Nokogiri::HTML4.fragment(node)
              normalize_html_style_script_comments(frag)
              normalize_rendered_whitespace(frag)
              remove_whitespace_only_text_nodes(frag)
              return frag
            end
          end

          # Apply preprocessing to HTML string before parsing
          html_string = case preprocessing
                        when :normalize
                          # Normalize whitespace: collapse runs, trim lines
                          node.lines.map(&:strip).reject(&:empty?).join("\n")
                        when :c14n
                          # Canonicalize the HTML (use XML canonicalization)
                          Canon::Xml::C14n.canonicalize(node,
                                                        with_comments: false)
                        when :format
                          # Pretty format the HTML
                          Canon.format(node, :html)
                        else
                          # :none or unrecognized - use as-is
                          node
                        end

          # Use Nokogiri for HTML and normalize style/script comments
          # Use noblanks to prevent Nokogiri from adding structural whitespace
          doc = Nokogiri::HTML(html_string, &:noblanks)
          normalize_html_style_script_comments(doc)
          doc
        end

        # Detect HTML version from content
        #
        # @param content [String] HTML content
        # @return [Symbol] :html5 or :html4
        def detect_html_version(content)
          # Check for HTML5 doctype (case-insensitive)
          if content.match?(/<!DOCTYPE\s+html>/i)
            :html5
          # Check for HTML4 doctype patterns
          elsif content.match?(/<!DOCTYPE\s+HTML\s+PUBLIC/i)
            :html4
          else
            # Default to HTML5 for modern usage
            :html5
          end
        end

        # Detect HTML version from Nokogiri node
        #
        # @param node [Nokogiri::XML::Node] Nokogiri HTML node
        # @return [Symbol] :html5 or :html4
        def detect_html_version_from_node(node)
          # Check node type
          if node.is_a?(Nokogiri::HTML5::Document) ||
              node.is_a?(Nokogiri::HTML5::DocumentFragment)
            :html5
          elsif node.is_a?(Nokogiri::HTML4::Document) ||
                node.is_a?(Nokogiri::HTML4::DocumentFragment)
            :html4
          else
            # Default to HTML4 for compatibility
            :html4
          end
        end

        # Serialize node to string for diff display
        # This ensures the displayed diff matches what was compared
        #
        # @param node [Nokogiri::HTML::Document] Parsed HTML node
        # @return [String] Serialized HTML string
        def serialize_for_display(node)
          # Get string representation with formatting for line-by-line diffs
          # Use to_html which preserves line structure for diff display
          node.to_html
        end

        # Normalize HTML comments within style and script tags
        # Also removes whitespace-only CDATA children that Nokogiri creates
        def normalize_html_style_script_comments(doc)
          doc.css("style, script").each do |element|
            # Remove HTML comments from style/script content
            normalized = element.content.gsub(/<!--.*?-->/m, "").strip

            if normalized.empty?
              # Remove all children (including whitespace-only CDATA nodes)
              element.children.remove
            else
              element.content = normalized
            end
          end
        end

        # Normalize whitespace in text nodes according to HTML rendering rules
        # In HTML rendering, sequences of whitespace (spaces, tabs, newlines)
        # collapse to a single space, except in elements where whitespace is
        # significant (pre, code, textarea, script, style)
        def normalize_rendered_whitespace(doc)
          # Elements where whitespace is significant - don't normalize
          preserve_whitespace = %w[pre code textarea script style]

          # Walk all text nodes
          doc.xpath(".//text()").each do |text_node|
            # Skip if this text node is inside a whitespace-preserving element
            # Check all ancestors, not just immediate parent
            parent = text_node.parent
            next if ancestor_preserves_whitespace?(parent, preserve_whitespace)

            # Collapse whitespace sequences (spaces, tabs, newlines) to single
            # space
            normalized = text_node.content.gsub(/\s+/, " ")

            # Trim leading/trailing whitespace if appropriate
            normalized = normalized.strip if should_trim_text_node?(text_node)

            text_node.content = normalized
          end
        end

        # Check if any ancestor of the given node preserves whitespace
        def ancestor_preserves_whitespace?(node, preserve_list)
          current = node
          while current && current.respond_to?(:name)
            return true if preserve_list.include?(current.name.downcase)

            # Stop at document root - documents don't have parents
            break if current.is_a?(Nokogiri::XML::Document)

            current = current.parent
          end
          false
        end

        # Determine if a text node should have leading/trailing whitespace
        # trimmed Text nodes at the start or end of their parent element should
        # be trimmed
        def should_trim_text_node?(text_node)
          parent = text_node.parent
          siblings = parent.children

          # Trim if text is the only child
          return true if siblings.length == 1

          # Trim if text is at the start or end of parent
          text_node == siblings.first || text_node == siblings.last
        end

        # Remove whitespace-only text nodes from the document
        # These are typically insignificant in HTML rendering (e.g., between
        # block elements)
        def remove_whitespace_only_text_nodes(doc)
          doc.xpath(".//text()").each do |text_node|
            # Remove if the text is only whitespace (after normalization)
            if text_node.content.strip.empty?
              text_node.remove
            end
          end
        end

        # Check if a node is an XML document (not HTML)
        # XML documents typically have XML processing instructions or are
        # instances of Nokogiri::XML::Document (not HTML variants)
        def is_xml_document?(node)
          # Check if it's a pure XML document (not HTML4/HTML5 which also
          # inherit from XML::Document)
          return false if node.is_a?(Nokogiri::HTML4::Document) ||
                          node.is_a?(Nokogiri::HTML5::Document)

          # If it's an XML document, check for XML processing instruction
          if node.is_a?(Nokogiri::XML::Document)
            # XML documents often start with <?xml ...?> processing instruction
            return true if node.children.any? do |child|
              child.is_a?(Nokogiri::XML::ProcessingInstruction) &&
                child.name == "xml"
            end
            # Also return true if it's a plain XML::Document
            return true
          end

          # Check if it's a fragment that contains XML processing instructions
          if node.respond_to?(:children)
            return true if node.children.any? do |child|
              child.is_a?(Nokogiri::XML::ProcessingInstruction) &&
                child.name == "xml"
            end
          end

          false
        end
      end
    end
  end
end
