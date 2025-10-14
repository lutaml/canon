# frozen_string_literal: true

require "moxml"
require "nokogiri"

module Canon
  # Comparison module for XML and HTML documents
  # Provides a CompareXML-compatible API
  # Uses Moxml for XML and Nokogiri for HTML
  module Comparison
    # Comparison result constants
    EQUIVALENT = 1
    MISSING_ATTRIBUTE = 2
    MISSING_NODE = 3
    UNEQUAL_ATTRIBUTES = 4
    UNEQUAL_COMMENTS = 5
    UNEQUAL_DOCUMENTS = 6
    UNEQUAL_ELEMENTS = 7
    UNEQUAL_NODES_TYPES = 8
    UNEQUAL_TEXT_CONTENTS = 9

    # Default comparison options
    DEFAULT_OPTS = {
      collapse_whitespace: true,
      ignore_attr_order: true,
      force_children: false,
      ignore_children: false,
      ignore_attr_content: [],
      ignore_attrs: [],
      ignore_attrs_by_name: [],
      ignore_comments: true,
      ignore_nodes: [],
      ignore_text_nodes: false,
      verbose: false,
    }.freeze

    class << self
      # Compare two nodes for equivalence
      #
      # @param n1 [String, Moxml::Node] First node or XML/HTML string
      # @param n2 [String, Moxml::Node] Second node or XML/HTML string
      # @param opts [Hash] Comparison options
      # @param child_opts [Hash] Options for child comparison
      # @param diff_children [Boolean] Whether to diff children
      # @return [Boolean, Array] true if equivalent, or array of diffs if
      #   verbose
      def equivalent?(n1, n2, opts = {}, child_opts = {}, diff_children: false)
        opts = DEFAULT_OPTS.merge(opts)
        child_opts = opts.merge(child_opts)

        # Parse nodes if they are strings
        node1 = parse_node(n1)
        node2 = parse_node(n2)

        result = compare_nodes(node1, node2, opts, child_opts, diff_children)

        if opts[:verbose]
          result == EQUIVALENT ? [] : result
        else
          result == EQUIVALENT
        end
      end

      private

      # Parse a node from string or return as-is
      def parse_node(node)
        return node unless node.is_a?(String)

        # Detect if HTML or XML
        if html?(node)
          # Use Nokogiri for HTML and normalize style/script comments
          doc = Nokogiri::HTML(node)
          normalize_html_style_script_comments(doc)
          doc
        else
          # Use Moxml for XML
          Moxml.new.parse(node)
        end
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

      # Detect if string is HTML
      def html?(str)
        str.strip.start_with?("<!DOCTYPE html", "<html", "<HTML")
      end

      # Main comparison dispatcher
      def compare_nodes(n1, n2, opts, child_opts, diff_children)
        # Check if nodes should be excluded
        return EQUIVALENT if node_excluded?(n1, opts) &&
                             node_excluded?(n2, opts)
        return MISSING_NODE if node_excluded?(n1, opts) ||
                               node_excluded?(n2, opts)

        # Check node types match
        return UNEQUAL_NODES_TYPES unless same_node_type?(n1, n2)

        # Dispatch based on node type
        if n1.respond_to?(:element?) && n1.element?
          compare_element_nodes(n1, n2, opts, child_opts, diff_children)
        elsif n1.respond_to?(:text?) && n1.text?
          compare_text_nodes(n1, n2, opts)
        elsif n1.respond_to?(:comment?) && n1.comment?
          compare_comment_nodes(n1, n2, opts)
        elsif n1.respond_to?(:cdata?) && n1.cdata?
          compare_text_nodes(n1, n2, opts)
        elsif n1.respond_to?(:processing_instruction?) &&
              n1.processing_instruction?
          compare_processing_instruction_nodes(n1, n2, opts)
        elsif n1.respond_to?(:root)
          # Document node
          compare_document_nodes(n1, n2, opts, child_opts, diff_children)
        else
          EQUIVALENT
        end
      end

      # Compare two element nodes
      def compare_element_nodes(n1, n2, opts, child_opts, diff_children)
        # Compare element names
        return UNEQUAL_ELEMENTS unless n1.name == n2.name

        # Compare attributes
        attr_result = compare_attribute_sets(n1, n2, opts)
        return attr_result unless attr_result == EQUIVALENT

        # Compare children if not ignored
        return EQUIVALENT if opts[:ignore_children]

        compare_children(n1, n2, opts, child_opts, diff_children)
      end

      # Compare attribute sets
      def compare_attribute_sets(n1, n2, opts)
        attrs1 = filter_attributes(n1.attributes, opts)
        attrs2 = filter_attributes(n2.attributes, opts)

        # Sort attributes if order should be ignored
        if opts[:ignore_attr_order]
          attrs1 = attrs1.sort.to_h
          attrs2 = attrs2.sort.to_h
        end

        return MISSING_ATTRIBUTE unless attrs1.keys.sort == attrs2.keys.sort

        attrs1.each do |name, value|
          return UNEQUAL_ATTRIBUTES unless attrs2[name] == value
        end

        EQUIVALENT
      end

      # Filter attributes based on options
      def filter_attributes(attributes, opts)
        filtered = {}

        attributes.each do |name, attr|
          value = attr.respond_to?(:value) ? attr.value : attr

          # Skip if attribute name should be ignored
          next if should_ignore_attr_by_name?(name, opts)

          # Skip if attribute content should be ignored
          next if should_ignore_attr_content?(value, opts)

          filtered[name] = value
        end

        filtered
      end

      # Check if attribute should be ignored by name
      def should_ignore_attr_by_name?(name, opts)
        opts[:ignore_attrs_by_name].any? do |pattern|
          name.include?(pattern)
        end
      end

      # Check if attribute should be ignored by content
      def should_ignore_attr_content?(value, opts)
        opts[:ignore_attr_content].any? do |pattern|
          value.to_s.include?(pattern)
        end
      end

      # Compare text nodes
      def compare_text_nodes(n1, n2, opts)
        return EQUIVALENT if opts[:ignore_text_nodes]

        text1 = node_text(n1)
        text2 = node_text(n2)

        if opts[:collapse_whitespace]
          text1 = collapse(text1)
          text2 = collapse(text2)
        end

        text1 == text2 ? EQUIVALENT : UNEQUAL_TEXT_CONTENTS
      end

      # Compare comment nodes
      def compare_comment_nodes(n1, n2, opts)
        return EQUIVALENT if opts[:ignore_comments]

        content1 = n1.content.to_s.strip
        content2 = n2.content.to_s.strip

        content1 == content2 ? EQUIVALENT : UNEQUAL_COMMENTS
      end

      # Compare processing instruction nodes
      def compare_processing_instruction_nodes(n1, n2, _opts)
        return UNEQUAL_NODES_TYPES unless n1.target == n2.target

        content1 = n1.content.to_s.strip
        content2 = n2.content.to_s.strip

        content1 == content2 ? EQUIVALENT : UNEQUAL_TEXT_CONTENTS
      end

      # Compare document nodes
      def compare_document_nodes(n1, n2, opts, child_opts, diff_children)
        # Compare root elements
        root1 = n1.root
        root2 = n2.root

        return MISSING_NODE if root1.nil? || root2.nil?

        compare_nodes(root1, root2, opts, child_opts, diff_children)
      end

      # Compare children of two nodes
      def compare_children(n1, n2, opts, child_opts, diff_children)
        children1 = filter_children(n1.children, opts)
        children2 = filter_children(n2.children, opts)

        return MISSING_NODE unless children1.length == children2.length

        children1.zip(children2).each do |child1, child2|
          result = compare_nodes(child1, child2, child_opts, child_opts,
                                 diff_children)
          return result unless result == EQUIVALENT
        end

        EQUIVALENT
      end

      # Filter children based on options
      def filter_children(children, opts)
        children.reject do |child|
          node_excluded?(child, opts)
        end
      end

      # Check if node should be excluded
      def node_excluded?(node, opts)
        # Ignore comments if specified
        return true if opts[:ignore_comments] &&
                       node.respond_to?(:comment?) && node.comment?

        # Ignore text nodes if specified
        return true if opts[:ignore_text_nodes] &&
                       node.respond_to?(:text?) && node.text?

        # Ignore whitespace-only text nodes when collapsing whitespace
        if opts[:collapse_whitespace] &&
           node.respond_to?(:text?) && node.text?
          text = node_text(node)
          return true if collapse(text).empty?
        end

        false
      end

      # Check if two nodes are the same type
      def same_node_type?(n1, n2)
        return true if n1.respond_to?(:element?) && n1.element? &&
                       n2.respond_to?(:element?) && n2.element?
        return true if n1.respond_to?(:text?) && n1.text? &&
                       n2.respond_to?(:text?) && n2.text?
        return true if n1.respond_to?(:comment?) && n1.comment? &&
                       n2.respond_to?(:comment?) && n2.comment?
        return true if n1.respond_to?(:cdata?) && n1.cdata? &&
                       n2.respond_to?(:cdata?) && n2.cdata?
        return true if n1.respond_to?(:processing_instruction?) &&
                       n1.processing_instruction? &&
                       n2.respond_to?(:processing_instruction?) &&
                       n2.processing_instruction?
        return true if n1.respond_to?(:root) && n2.respond_to?(:root)

        false
      end

      # Get text content from a node
      def node_text(node)
        if node.respond_to?(:content)
          node.content.to_s
        elsif node.respond_to?(:text)
          node.text.to_s
        else
          ""
        end
      end

      # Collapse whitespace in text
      def collapse(text)
        text.to_s.gsub(/\s+/, " ").strip
      end
    end
  end
end
