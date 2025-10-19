# frozen_string_literal: true

require "nokogiri"
require_relative "xml_comparator"
require_relative "match_options"

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
          match_opts = MatchOptions::Xml.resolve(
            format: :html,
            match_profile: opts[:match_profile],
            match: opts[:match],
            preprocessing: opts[:preprocessing],
            global_profile: opts[:global_profile],
            global_options: opts[:global_options],
          )

          # Store resolved match options for use in comparison logic
          opts[:match_opts] = match_opts

          # Create child_opts with resolved options
          child_opts = opts.merge(child_opts)

          # Parse nodes if they are strings, applying preprocessing if needed
          node1 = parse_node(html1, match_opts[:preprocessing])
          node2 = parse_node(html2, match_opts[:preprocessing])

          # Serialize preprocessed nodes for diff display (avoid re-preprocessing)
          preprocessed_str1 = serialize_for_display(node1)
          preprocessed_str2 = serialize_for_display(node2)

          differences = []
          diff_children = opts[:diff_children] || false

          result = XmlComparator.send(:compare_nodes, node1, node2, opts,
                                      child_opts, diff_children, differences)

          if opts[:verbose]
            {
              differences: differences,
              preprocessed: [preprocessed_str1, preprocessed_str2],
            }
          else
            result == Comparison::EQUIVALENT
          end
        end

        private

        # Parse a node from string or return as-is
        # Applies preprocessing transformation before parsing if specified
        def parse_node(node, preprocessing = :none)
          return node unless node.is_a?(String)

          # For :rendered preprocessing, handle separately to avoid double-parsing
          if preprocessing == :rendered
            # Normalize via Nokogiri's to_html to get rendered-equivalent output
            # This respects element-specific whitespace behavior
            html_version = detect_html_version(node)

            # Parse with appropriate parser for HTML version
            doc = if html_version == :html5
                    Nokogiri::HTML5(node, max_tree_depth: -1)
                  else
                    Nokogiri::HTML4::Document.parse(node)
                  end

            # Convert to HTML and remove all leading indentation
            # This ensures both documents are in the same canonical form
            html_string = doc.to_html
              .lines
              .map(&:lstrip)
              .join

            # Re-parse to ensure consistent structure
            doc = Nokogiri::HTML(html_string, &:noblanks)
            normalize_html_style_script_comments(doc)
            return doc
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

        # Serialize node to string for diff display
        # This ensures the displayed diff matches what was compared
        #
        # @param node [Nokogiri::HTML::Document] Parsed HTML node
        # @return [String] Serialized HTML string
        def serialize_for_display(node)
          # Get string representation - to_html will add indentation
          html_str = node.to_html

          # Strip indentation to match preprocessing behavior
          # This ensures diff display matches compared content
          html_str.lines.map(&:lstrip).join
        end

        # Normalize HTML comments within style and script tags
        def normalize_html_style_script_comments(doc)
          doc.css("style, script").each do |element|
            next if element.content.strip.empty?

            # Remove HTML comments from style/script content
            normalized = element.content.gsub(/<!--.*?-->/m, "").strip
            element.content = normalized
          end
        end
      end
    end
  end
end
