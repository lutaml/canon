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

          # Parse nodes if they are strings
          node1 = parse_node(html1)
          node2 = parse_node(html2)

          differences = []
          diff_children = opts[:diff_children] || false

          result = XmlComparator.send(:compare_nodes, node1, node2, opts,
                                      child_opts, diff_children, differences)

          if opts[:verbose]
            differences
          else
            result == Comparison::EQUIVALENT
          end
        end

        private

        # Parse a node from string or return as-is
        def parse_node(node)
          return node unless node.is_a?(String)

          # Use Nokogiri for HTML and normalize style/script comments
          doc = Nokogiri::HTML(node)
          normalize_html_style_script_comments(doc)
          doc
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
