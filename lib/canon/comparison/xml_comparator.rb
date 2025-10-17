# frozen_string_literal: true

require "moxml"

module Canon
  module Comparison
    # XML comparison class
    # Handles comparison of XML nodes with various options
    class XmlComparator
      # Default comparison options for XML
      DEFAULT_OPTS = {
        collapse_whitespace: true,
        flexible_whitespace: false,
        ignore_attr_order: true,
        force_children: false,
        ignore_children: false,
        ignore_attr_content: [],
        ignore_attrs: [],
        ignore_attrs_by_name: [],
        ignore_comments: true,
        ignore_nodes: [],
        ignore_text_nodes: false,
        normalize_tag_whitespace: false,
        verbose: false,
      }.freeze

      class << self
        # Compare two XML nodes for equivalence
        #
        # @param n1 [String, Moxml::Node] First node
        # @param n2 [String, Moxml::Node] Second node
        # @param opts [Hash] Comparison options
        # @param child_opts [Hash] Options for child comparison
        # @return [Boolean, Array] true if equivalent, or array of diffs if
        #   verbose
        def equivalent?(n1, n2, opts = {}, child_opts = {})
          opts = DEFAULT_OPTS.merge(opts)
          child_opts = opts.merge(child_opts)

          # Parse nodes if they are strings
          node1 = parse_node(n1)
          node2 = parse_node(n2)

          differences = []
          diff_children = opts[:diff_children] || false

          result = compare_nodes(node1, node2, opts, child_opts,
                                 diff_children, differences)

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

          # Use Moxml for XML
          Moxml.new.parse(node)
        end

        # Main comparison dispatcher
        def compare_nodes(n1, n2, opts, child_opts, diff_children, differences)
          # Check if nodes should be excluded
          return Comparison::EQUIVALENT if node_excluded?(n1, opts) &&
            node_excluded?(n2, opts)

          if node_excluded?(n1, opts) || node_excluded?(n2, opts)
            add_difference(n1, n2, Comparison::MISSING_NODE,
                           Comparison::MISSING_NODE, opts, differences)
            return Comparison::MISSING_NODE
          end

          # Check node types match
          unless same_node_type?(n1, n2)
            add_difference(n1, n2, Comparison::UNEQUAL_NODES_TYPES,
                           Comparison::UNEQUAL_NODES_TYPES, opts, differences)
            return Comparison::UNEQUAL_NODES_TYPES
          end

          # Dispatch based on node type
          if n1.respond_to?(:element?) && n1.element?
            compare_element_nodes(n1, n2, opts, child_opts, diff_children,
                                  differences)
          elsif n1.respond_to?(:text?) && n1.text?
            compare_text_nodes(n1, n2, opts, differences)
          elsif n1.respond_to?(:comment?) && n1.comment?
            compare_comment_nodes(n1, n2, opts, differences)
          elsif n1.respond_to?(:cdata?) && n1.cdata?
            compare_text_nodes(n1, n2, opts, differences)
          elsif n1.respond_to?(:processing_instruction?) &&
              n1.processing_instruction?
            compare_processing_instruction_nodes(n1, n2, opts, differences)
          elsif n1.respond_to?(:root)
            # Document node
            compare_document_nodes(n1, n2, opts, child_opts, diff_children,
                                   differences)
          else
            Comparison::EQUIVALENT
          end
        end

        # Compare two element nodes
        def compare_element_nodes(n1, n2, opts, child_opts, diff_children,
                                  differences)
          # Compare element names
          unless n1.name == n2.name
            add_difference(n1, n2, Comparison::UNEQUAL_ELEMENTS,
                           Comparison::UNEQUAL_ELEMENTS, opts, differences)
            return Comparison::UNEQUAL_ELEMENTS
          end

          # Compare attributes
          attr_result = compare_attribute_sets(n1, n2, opts, differences)
          return attr_result unless attr_result == Comparison::EQUIVALENT

          # Compare children if not ignored
          return Comparison::EQUIVALENT if opts[:ignore_children]

          compare_children(n1, n2, opts, child_opts, diff_children, differences)
        end

        # Compare attribute sets
        def compare_attribute_sets(n1, n2, opts, differences)
          attrs1 = filter_attributes(n1.attributes, opts)
          attrs2 = filter_attributes(n2.attributes, opts)

          # Sort attributes if order should be ignored
          if opts[:ignore_attr_order]
            attrs1 = attrs1.sort_by { |k, _v| k.to_s }.to_h
            attrs2 = attrs2.sort_by { |k, _v| k.to_s }.to_h
          end

          unless attrs1.keys.map(&:to_s).sort == attrs2.keys.map(&:to_s).sort
            add_difference(n1, n2, Comparison::MISSING_ATTRIBUTE,
                           Comparison::MISSING_ATTRIBUTE, opts, differences)
            return Comparison::MISSING_ATTRIBUTE
          end

          attrs1.each do |name, value|
            unless attrs2[name] == value
              add_difference(n1, n2, Comparison::UNEQUAL_ATTRIBUTES,
                             Comparison::UNEQUAL_ATTRIBUTES, opts, differences)
              return Comparison::UNEQUAL_ATTRIBUTES
            end
          end

          Comparison::EQUIVALENT
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
        def compare_text_nodes(n1, n2, opts, differences)
          return Comparison::EQUIVALENT if opts[:ignore_text_nodes]

          text1 = node_text(n1)
          text2 = node_text(n2)

          if opts[:normalize_tag_whitespace]
            text1 = normalize_tag_whitespace(text1)
            text2 = normalize_tag_whitespace(text2)
          elsif opts[:collapse_whitespace]
            text1 = collapse(text1)
            text2 = collapse(text2)
          end

          if text1 == text2
            Comparison::EQUIVALENT
          else
            add_difference(n1, n2, Comparison::UNEQUAL_TEXT_CONTENTS,
                           Comparison::UNEQUAL_TEXT_CONTENTS, opts, differences)
            Comparison::UNEQUAL_TEXT_CONTENTS
          end
        end

        # Compare comment nodes
        def compare_comment_nodes(n1, n2, opts, differences)
          return Comparison::EQUIVALENT if opts[:ignore_comments]

          content1 = n1.content.to_s.strip
          content2 = n2.content.to_s.strip

          if content1 == content2
            Comparison::EQUIVALENT
          else
            add_difference(n1, n2, Comparison::UNEQUAL_COMMENTS,
                           Comparison::UNEQUAL_COMMENTS, opts, differences)
            Comparison::UNEQUAL_COMMENTS
          end
        end

        # Compare processing instruction nodes
        def compare_processing_instruction_nodes(n1, n2, opts, differences)
          unless n1.target == n2.target
            add_difference(n1, n2, Comparison::UNEQUAL_NODES_TYPES,
                           Comparison::UNEQUAL_NODES_TYPES, opts, differences)
            return Comparison::UNEQUAL_NODES_TYPES
          end

          content1 = n1.content.to_s.strip
          content2 = n2.content.to_s.strip

          if content1 == content2
            Comparison::EQUIVALENT
          else
            add_difference(n1, n2, Comparison::UNEQUAL_TEXT_CONTENTS,
                           Comparison::UNEQUAL_TEXT_CONTENTS, opts, differences)
            Comparison::UNEQUAL_TEXT_CONTENTS
          end
        end

        # Compare document nodes
        def compare_document_nodes(n1, n2, opts, child_opts, diff_children,
                                   differences)
          # Compare root elements
          root1 = n1.root
          root2 = n2.root

          if root1.nil? || root2.nil?
            add_difference(n1, n2, Comparison::MISSING_NODE,
                           Comparison::MISSING_NODE, opts, differences)
            return Comparison::MISSING_NODE
          end

          compare_nodes(root1, root2, opts, child_opts, diff_children,
                        differences)
        end

        # Compare children of two nodes
        def compare_children(n1, n2, opts, child_opts, diff_children,
                             differences)
          children1 = filter_children(n1.children, opts)
          children2 = filter_children(n2.children, opts)

          unless children1.length == children2.length
            add_difference(n1, n2, Comparison::MISSING_NODE,
                           Comparison::MISSING_NODE, opts, differences)
            return Comparison::MISSING_NODE
          end

          children1.zip(children2).each do |child1, child2|
            result = compare_nodes(child1, child2, child_opts, child_opts,
                                   diff_children, differences)
            return result unless result == Comparison::EQUIVALENT
          end

          Comparison::EQUIVALENT
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

        # Normalize tag whitespace
        def normalize_tag_whitespace(text)
          text.to_s
            .gsub(/\s+/, " ")  # Collapse multiple whitespace to single space
            .strip             # Remove leading/trailing whitespace
        end

        # Add a difference to the differences array
        def add_difference(node1, node2, diff1, diff2, opts, differences)
          return unless opts[:verbose]

          differences << {
            node1: node1,
            node2: node2,
            diff1: diff1,
            diff2: diff2,
          }
        end
      end
    end
  end
end
