# frozen_string_literal: true

require_relative "../xml/c14n"
require_relative "match_options"
require_relative "../diff/diff_node"
require_relative "../diff/diff_classifier"
require_relative "comparison_result"

module Canon
  module Comparison
    # XML comparison class
    # Handles comparison of XML nodes with various options
    class XmlComparator
      # Default comparison options for XML
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

          # Resolve match options with format-specific defaults
          match_opts_hash = MatchOptions::Xml.resolve(
            format: :xml,
            match_profile: opts[:match_profile],
            match: opts[:match],
            preprocessing: opts[:preprocessing],
            global_profile: opts[:global_profile],
            global_options: opts[:global_options],
          )

          # Wrap in ResolvedMatchOptions for DiffClassifier
          match_opts = Canon::Comparison::ResolvedMatchOptions.new(
            match_opts_hash,
            format: :xml,
          )

          # Store resolved match options hash for use in comparison logic
          opts[:match_opts] = match_opts_hash

          # Create child_opts with resolved options
          child_opts = opts.merge(child_opts)

          # Parse nodes if they are strings, applying preprocessing if needed
          node1 = parse_node(n1, match_opts_hash[:preprocessing])
          node2 = parse_node(n2, match_opts_hash[:preprocessing])

          differences = []
          diff_children = opts[:diff_children] || false

          result = compare_nodes(node1, node2, opts, child_opts,
                                 diff_children, differences)

          # Classify DiffNodes as active/inactive if we have verbose output
          if opts[:verbose] && !differences.empty?
            classifier = Canon::Diff::DiffClassifier.new(match_opts)
            classifier.classify_all(differences.select do |d|
              d.is_a?(Canon::Diff::DiffNode)
            end)
          end

          if opts[:verbose]
            # Return ComparisonResult for proper equivalence checking
            # Format XMLfor line-by-line display by adding line breaks between elements
            xml1 = node1.respond_to?(:to_xml) ? node1.to_xml : node1.to_s
            xml2 = node2.respond_to?(:to_xml) ? node2.to_xml : node2.to_s

            preprocessed = [
              xml1.gsub(/></, ">\n<"),
              xml2.gsub(/></, ">\n<"),
            ]

            ComparisonResult.new(
              differences: differences,
              preprocessed_strings: preprocessed,
              format: :xml,
              match_options: match_opts_hash,
            )
          else
            result == Comparison::EQUIVALENT
          end
        end

        private

        # Parse a node from string or return as-is
        # Applies preprocessing transformation before parsing if specified
        def parse_node(node, preprocessing = :none)
          return node unless node.is_a?(String)

          # Apply preprocessing to XML string before parsing
          xml_string = case preprocessing
                       when :normalize
                         # Normalize whitespace: collapse runs, trim lines
                         node.lines.map(&:strip).reject(&:empty?).join("\n")
                       when :c14n
                         # Canonicalize the XML
                         Canon::Xml::C14n.canonicalize(node,
                                                       with_comments: false)
                       when :format
                         # Pretty format the XML
                         Canon.format(node, :xml)
                       else
                         # :none or unrecognized - use as-is
                         node
                       end

          # Use Moxml for XML parsing
          Moxml.new.parse(xml_string)
        end

        # Main comparison dispatcher
        def compare_nodes(n1, n2, opts, child_opts, diff_children, differences)
          # Handle DocumentFragment nodes - compare their children instead
          if n1.is_a?(Nokogiri::XML::DocumentFragment) &&
              n2.is_a?(Nokogiri::XML::DocumentFragment)
            children1 = n1.children.to_a
            children2 = n2.children.to_a

            if children1.length != children2.length
              add_difference(n1, n2, Comparison::UNEQUAL_ELEMENTS,
                             Comparison::UNEQUAL_ELEMENTS, :text_content, opts,
                             differences)
              return Comparison::UNEQUAL_ELEMENTS
            elsif children1.empty?
              return Comparison::EQUIVALENT
            else
              # Compare each pair of children
              result = Comparison::EQUIVALENT
              children1.zip(children2).each do |child1, child2|
                child_result = compare_nodes(child1, child2, opts, child_opts,
                                             diff_children, differences)
                if child_result != Comparison::EQUIVALENT
                  result = child_result
                  break
                end
              end
              return result
            end
          end

          # Check if nodes should be excluded
          return Comparison::EQUIVALENT if node_excluded?(n1, opts) &&
            node_excluded?(n2, opts)

          if node_excluded?(n1, opts) || node_excluded?(n2, opts)
            add_difference(n1, n2, Comparison::MISSING_NODE,
                           Comparison::MISSING_NODE, :text_content, opts, differences)
            return Comparison::MISSING_NODE
          end

          # Check node types match
          unless same_node_type?(n1, n2)
            add_difference(n1, n2, Comparison::UNEQUAL_NODES_TYPES,
                           Comparison::UNEQUAL_NODES_TYPES, :text_content, opts,
                           differences)
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
                           Comparison::UNEQUAL_ELEMENTS, :text_content, opts,
                           differences)
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

          # Always sort attributes since attribute order doesn't matter in XML/HTML
          attrs1 = attrs1.sort_by { |k, _v| k.to_s }.to_h
          attrs2 = attrs2.sort_by { |k, _v| k.to_s }.to_h

          unless attrs1.keys.map(&:to_s).sort == attrs2.keys.map(&:to_s).sort
            add_difference(n1, n2, Comparison::MISSING_ATTRIBUTE,
                           Comparison::MISSING_ATTRIBUTE,
                           :attribute_presence, opts, differences)
            return Comparison::MISSING_ATTRIBUTE
          end

          attrs1.each do |name, value|
            unless attrs2[name] == value
              add_difference(n1, n2, Comparison::UNEQUAL_ATTRIBUTES,
                             Comparison::UNEQUAL_ATTRIBUTES,
                             :attribute_values, opts, differences)
              return Comparison::UNEQUAL_ATTRIBUTES
            end
          end

          Comparison::EQUIVALENT
        end

        # Filter attributes based on options
        def filter_attributes(attributes, opts)
          filtered = {}
          match_opts = opts[:match_opts]

          attributes.each do |key, val|
            # Handle both Nokogiri and Moxml attribute formats:
            # - Nokogiri: key is String name, val is Nokogiri::XML::Attr object
            # - Moxml: key is Moxml::Attribute object, val is nil

            if key.is_a?(String)
              # Nokogiri format: key=name (String), val=attr object
              name = key
              value = val.respond_to?(:value) ? val.value : val.to_s
            else
              # Moxml format: key=attr object, val=nil
              name = key.respond_to?(:name) ? key.name : key.to_s
              value = key.respond_to?(:value) ? key.value : key.to_s
            end

            # Skip if attribute name should be ignored
            next if should_ignore_attr_by_name?(name, opts)

            # Skip if attribute content should be ignored
            next if should_ignore_attr_content?(value, opts)

            # Apply match options for attribute values
            behavior = match_opts[:attribute_values] || :strict
            value = MatchOptions.process_attribute_value(value, behavior)

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

          # Use match options
          match_opts = opts[:match_opts]
          behavior = match_opts[:text_content]

          # For HTML, check if text node is inside whitespace-preserving element
          # If so, always use strict comparison regardless of text_content setting
          if should_preserve_whitespace_strictly?(n1, n2)
            behavior = :strict
          end

          if MatchOptions.match_text?(text1, text2, behavior)
            Comparison::EQUIVALENT
          else
            # Determine the correct dimension for this difference
            # - If text_content is :strict, ALL differences use :text_content dimension
            # - If text_content is :normalize, whitespace-only diffs use :structural_whitespace
            # - Otherwise use :text_content
            dimension = if behavior == :normalize && whitespace_only_difference?(
              text1, text2
            )
                          :structural_whitespace
                        else
                          :text_content
                        end

            add_difference(n1, n2, Comparison::UNEQUAL_TEXT_CONTENTS,
                           Comparison::UNEQUAL_TEXT_CONTENTS, dimension,
                           opts, differences)
            Comparison::UNEQUAL_TEXT_CONTENTS
          end
        end

        # Check if the difference between two texts is only whitespace-related
        # @param text1 [String] First text
        # @param text2 [String] Second text
        # @return [Boolean] true if difference is only in whitespace
        def whitespace_only_difference?(text1, text2)
          # Normalize both texts (collapse/trim whitespace)
          norm1 = MatchOptions.normalize_text(text1)
          norm2 = MatchOptions.normalize_text(text2)

          # If normalized texts are the same, the difference was only whitespace
          norm1 == norm2
        end

        # Check if whitespace should be preserved strictly for these text nodes
        # This applies to HTML elements like pre, code, textarea, script, style
        def should_preserve_whitespace_strictly?(n1, n2)
          # Only applies to Nokogiri nodes (HTML)
          return false unless n1.respond_to?(:parent) && n2.respond_to?(:parent)
          return false unless n1.parent.respond_to?(:name) && n2.parent.respond_to?(:name)

          # Elements where whitespace must be preserved in HTML
          preserve_elements = %w[pre code textarea script style]

          # Check if either node is inside a whitespace-preserving element
          in_preserve_element?(n1, preserve_elements) ||
            in_preserve_element?(n2, preserve_elements)
        end

        # Check if a node is inside a whitespace-preserving element
        def in_preserve_element?(node, preserve_list)
          current = node.parent
          while current.respond_to?(:name)
            return true if preserve_list.include?(current.name.downcase)

            # Stop at document root
            break if current.is_a?(Nokogiri::XML::Document) ||
              current.is_a?(Nokogiri::HTML4::Document) ||
              current.is_a?(Nokogiri::HTML5::Document)

            current = current.parent if current.respond_to?(:parent)
            break unless current
          end
          false
        end

        # Compare comment nodes
        def compare_comment_nodes(n1, n2, opts, differences)
          match_opts = opts[:match_opts]
          behavior = match_opts[:comments]

          # If comments are ignored, consider them equivalent
          return Comparison::EQUIVALENT if behavior == :ignore

          content1 = n1.content.to_s
          content2 = n2.content.to_s

          if MatchOptions.match_text?(content1, content2, behavior)
            Comparison::EQUIVALENT
          else
            add_difference(n1, n2, Comparison::UNEQUAL_COMMENTS,
                           Comparison::UNEQUAL_COMMENTS, :comments, opts,
                           differences)
            Comparison::UNEQUAL_COMMENTS
          end
        end

        # Compare processing instruction nodes
        def compare_processing_instruction_nodes(n1, n2, opts, differences)
          unless n1.target == n2.target
            add_difference(n1, n2, Comparison::UNEQUAL_NODES_TYPES,
                           Comparison::UNEQUAL_NODES_TYPES, :text_content, opts,
                           differences)
            return Comparison::UNEQUAL_NODES_TYPES
          end

          content1 = n1.content.to_s.strip
          content2 = n2.content.to_s.strip

          if content1 == content2
            Comparison::EQUIVALENT
          else
            add_difference(n1, n2, Comparison::UNEQUAL_TEXT_CONTENTS,
                           Comparison::UNEQUAL_TEXT_CONTENTS, :text_content,
                           opts, differences)
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
                           Comparison::MISSING_NODE, :text_content, opts, differences)
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
                           Comparison::MISSING_NODE, :text_content, opts, differences)
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
          match_opts = opts[:match_opts]

          # Ignore comments based on match options
          if node.respond_to?(:comment?) && node.comment? && (match_opts[:comments] == :ignore)
            return true
          end

          # Ignore text nodes if specified
          return true if opts[:ignore_text_nodes] &&
            node.respond_to?(:text?) && node.text?

          # Ignore whitespace-only text nodes based on structural_whitespace
          # Both :ignore and :normalize should filter out whitespace-only nodes
          if %i[ignore
                normalize].include?(match_opts[:structural_whitespace]) &&
              node.respond_to?(:text?) && node.text?
            text = node_text(node)
            return true if MatchOptions.normalize_text(text).empty?
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

        # Add a difference to the differences array
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param diff1 [String] Difference type for node1
        # @param diff2 [String] Difference type for node2
        # @param dimension [Symbol] The match dimension causing this difference
        # @param opts [Hash] Options
        # @param differences [Array] Array to append difference to
        def add_difference(node1, node2, diff1, diff2, dimension, opts,
                           differences)
          return unless opts[:verbose]

          # All differences must be DiffNode objects (OO architecture)
          if dimension.nil?
            raise ArgumentError,
                  "dimension required for DiffNode"
          end

          diff_node = Canon::Diff::DiffNode.new(
            node1: node1,
            node2: node2,
            dimension: dimension,
            reason: "#{diff1} vs #{diff2}",
          )
          differences << diff_node
        end
      end
    end
  end
end
