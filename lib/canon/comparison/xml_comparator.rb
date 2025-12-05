# frozen_string_literal: true

require_relative "../xml/c14n"
require_relative "match_options"
require_relative "../diff/diff_node"
require_relative "../diff/diff_classifier"
require_relative "comparison_result"
require_relative "../tree_diff"
require_relative "strategies/match_strategy_factory"

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

          # Use tree diff if semantic_diff option is enabled
          if match_opts.semantic_diff?
            return perform_semantic_tree_diff(n1, n2, opts, match_opts_hash)
          end

          # Create child_opts with resolved options
          child_opts = opts.merge(child_opts)

          # Parse nodes if they are strings, applying preprocessing if needed
          node1 = parse_node(n1, match_opts_hash[:preprocessing])
          node2 = parse_node(n2, match_opts_hash[:preprocessing])

          differences = []
          diff_children = opts[:diff_children] || false

          result = compare_nodes(node1, node2, opts, child_opts,
                                 diff_children, differences)

          # Classify DiffNodes as normative/informative if we have verbose output
          if opts[:verbose] && !differences.empty?
            classifier = Canon::Diff::DiffClassifier.new(match_opts)
            classifier.classify_all(differences.select do |d|
              d.is_a?(Canon::Diff::DiffNode)
            end)
          end

          if opts[:verbose]
            # Serialize parsed nodes for consistent formatting
            # This ensures both sides formatted identically, showing only real differences
            preprocessed = [
              serialize_node_to_xml(node1).gsub(/></, ">\n<"),
              serialize_node_to_xml(node2).gsub(/></, ">\n<"),
            ]

            ComparisonResult.new(
              differences: differences,
              preprocessed_strings: preprocessed,
              format: :xml,
              match_options: match_opts_hash,
              algorithm: :dom,
            )
          else
            result == Comparison::EQUIVALENT
          end
        end

        private

        # Perform semantic tree diff using SemanticTreeMatchStrategy
        #
        # @param n1 [String, Moxml::Node] First node
        # @param n2 [String, Moxml::Node] Second node
        # @param opts [Hash] Comparison options
        # @param match_opts_hash [Hash] Resolved match options
        # @return [Boolean, ComparisonResult] Result of tree diff comparison
        def perform_semantic_tree_diff(n1, n2, opts, match_opts_hash)
          # Parse to Canon::Xml::Node (preserves preprocessing)
          node1 = parse_node(n1, match_opts_hash[:preprocessing])
          node2 = parse_node(n2, match_opts_hash[:preprocessing])

          # Create strategy using factory
          strategy = Strategies::MatchStrategyFactory.create(
            format: :xml,
            match_options: match_opts_hash,
          )

          # Pass Canon::Xml::Node directly - XML adapter now handles it
          differences = strategy.match(node1, node2)

          # Return based on verbose mode
          if opts[:verbose]
            # Get preprocessed strings for display
            preprocessed = strategy.preprocess_for_display(node1, node2)

            # Return ComparisonResult with strategy metadata
            ComparisonResult.new(
              differences: differences,
              preprocessed_strings: preprocessed,
              format: :xml,
              match_options: match_opts_hash.merge(strategy.metadata),
              algorithm: :semantic,
            )
          else
            # Simple boolean result - equivalent if no normative differences
            differences.none?(&:normative?)
          end
        end

        # Parse a node from string or return as-is
        # Applies preprocessing transformation before parsing if specified
        def parse_node(node, preprocessing = :none)
          # If already a Canon::Xml::Node, return as-is
          return node if node.is_a?(Canon::Xml::Node)

          # If it's a Nokogiri or Moxml node, convert to DataModel
          unless node.is_a?(String)
            # Convert to XML string then parse through DataModel
            xml_str = if node.respond_to?(:to_xml)
                        node.to_xml
                      elsif node.respond_to?(:to_s)
                        node.to_s
                      else
                        raise Canon::Error,
                              "Unable to convert node to string: #{node.class}"
                      end
            return Canon::Xml::DataModel.from_xml(xml_str)
          end

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

          # Use Canon::Xml::DataModel for parsing to get Canon::Xml::Node instances
          Canon::Xml::DataModel.from_xml(xml_string)
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
          # Canon::Xml::Node types use .node_type method that returns symbols
          # Nokogiri also has .node_type but returns integers, so check for Symbol
          if n1.respond_to?(:node_type) && n2.respond_to?(:node_type) &&
              n1.node_type.is_a?(Symbol) && n2.node_type.is_a?(Symbol)
            case n1.node_type
            when :root
              compare_children(n1, n2, opts, child_opts, diff_children,
                               differences)
            when :element
              compare_element_nodes(n1, n2, opts, child_opts, diff_children,
                                    differences)
            when :text
              compare_text_nodes(n1, n2, opts, differences)
            when :comment
              compare_comment_nodes(n1, n2, opts, differences)
            when :cdata
              compare_text_nodes(n1, n2, opts, differences)
            when :processing_instruction
              compare_processing_instruction_nodes(n1, n2, opts, differences)
            else
              Comparison::EQUIVALENT
            end
          # Moxml/Nokogiri types use .element?, .text?, etc. methods
          elsif n1.respond_to?(:element?) && n1.element?
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
            # Document node (Moxml/Nokogiri - legacy path)
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

          # Compare namespace URIs - elements with different namespaces are different elements
          ns1 = n1.respond_to?(:namespace_uri) ? n1.namespace_uri : nil
          ns2 = n2.respond_to?(:namespace_uri) ? n2.namespace_uri : nil

          unless ns1 == ns2
            add_difference(n1, n2, Comparison::UNEQUAL_ELEMENTS,
                           Comparison::UNEQUAL_ELEMENTS, :namespace_uri, opts,
                           differences)
            return Comparison::UNEQUAL_ELEMENTS
          end

          # Compare namespace URIs - elements with different namespaces are different elements
          ns1 = n1.respond_to?(:namespace_uri) ? n1.namespace_uri : nil
          ns2 = n2.respond_to?(:namespace_uri) ? n2.namespace_uri : nil

          unless ns1 == ns2
            # Create descriptive reason showing the actual namespace URIs
            ns1_display = ns1.nil? || ns1.empty? ? "(no namespace)" : ns1
            ns2_display = ns2.nil? || ns2.empty? ? "(no namespace)" : ns2

            diff_node = Canon::Diff::DiffNode.new(
              node1: n1,
              node2: n2,
              dimension: :namespace_uri,
              reason: "namespace '#{ns1_display}' vs '#{ns2_display}' on element '#{n1.name}'",
            )
            differences << diff_node if opts[:verbose]
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
          # Get attributes using the appropriate method for each node type
          raw_attrs1 = n1.respond_to?(:attribute_nodes) ? n1.attribute_nodes : n1.attributes
          raw_attrs2 = n2.respond_to?(:attribute_nodes) ? n2.attribute_nodes : n2.attributes

          attrs1 = filter_attributes(raw_attrs1, opts)
          attrs2 = filter_attributes(raw_attrs2, opts)

          match_opts = opts[:match_opts]
          attribute_order_behavior = match_opts[:attribute_order] || :strict

          # Check attribute order if not ignored
          if attribute_order_behavior == :strict
            # Strict mode: attribute order matters
            # Check if keys are in same order
            keys1 = attrs1.keys.map(&:to_s)
            keys2 = attrs2.keys.map(&:to_s)

            if keys1 != keys2
              # Keys are different or in different order
              # First check if it's just ordering (same keys, different order)
              if keys1.sort == keys2.sort
                # Same keys, different order - this is an attribute_order difference
                add_difference(n1, n2, Comparison::UNEQUAL_ATTRIBUTES,
                               Comparison::UNEQUAL_ATTRIBUTES,
                               :attribute_order, opts, differences)
                return Comparison::UNEQUAL_ATTRIBUTES
              else
                # Different keys - this is attribute_presence difference
                add_difference(n1, n2, Comparison::MISSING_ATTRIBUTE,
                               Comparison::MISSING_ATTRIBUTE,
                               :attribute_presence, opts, differences)
                return Comparison::MISSING_ATTRIBUTE
              end
            end

            # Order matches, now check values in order
          else
            # Ignore/normalize mode: sort attributes so order doesn't matter
            attrs1 = attrs1.sort_by { |k, _v| k.to_s }.to_h
            attrs2 = attrs2.sort_by { |k, _v| k.to_s }.to_h

            unless attrs1.keys.map(&:to_s).sort == attrs2.keys.map(&:to_s).sort
              add_difference(n1, n2, Comparison::MISSING_ATTRIBUTE,
                             Comparison::MISSING_ATTRIBUTE,
                             :attribute_presence, opts, differences)
              return Comparison::MISSING_ATTRIBUTE
            end

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

          # Handle Canon::Xml::Node attribute format (array of AttributeNode)
          if attributes.is_a?(Array)
            attributes.each do |attr|
              name = attr.name
              value = attr.value

              # Skip if attribute name should be ignored
              next if should_ignore_attr_by_name?(name, opts)

              # Skip if attribute content should be ignored
              next if should_ignore_attr_content?(value, opts)

              # Apply match options for attribute values
              behavior = match_opts[:attribute_values] || :strict
              value = MatchOptions.process_attribute_value(value, behavior)

              filtered[name] = value
            end
          else
            # Handle Nokogiri and Moxml attribute formats (Hash-like):
            # - Nokogiri: key is String name, val is Nokogiri::XML::Attr object
            # - Moxml: key is Moxml::Attribute object, val is nil
            attributes.each do |key, val|
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

          # Canon::Xml::Node CommentNode uses .value, Nokogiri uses .content
          content1 = node_text(n1)
          content2 = node_text(n2)

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

        # Compare children of two nodes using semantic matching
        #
        # Uses ElementMatcher to pair children semantically (by identity attributes
        # or position), then compares matched pairs and detects position changes.
        def compare_children(n1, n2, opts, child_opts, diff_children,
                             differences)
          children1 = filter_children(n1.children, opts)
          children2 = filter_children(n2.children, opts)

          # Quick check: if both have no children, they're equivalent
          return Comparison::EQUIVALENT if children1.empty? && children2.empty?

          # Check if we can use ElementMatcher (requires Canon::Xml::DataModel nodes)
          # ElementMatcher expects nodes with .node_type method that returns symbols
          # and only works with element nodes (filters out text, comment, etc.)
          can_use_matcher = children1.all? do |c|
            c.is_a?(Canon::Xml::Node) && c.node_type == :element
          end &&
            children2.all? { |c| c.is_a?(Canon::Xml::Node) && c.node_type == :element }

          if can_use_matcher && !children1.empty? && !children2.empty?
            # Use ElementMatcher for semantic matching with position tracking
            use_element_matcher_comparison(children1, children2, n1, opts,
                                           child_opts, diff_children, differences)
          else
            # Fall back to simple positional comparison for Moxml/Nokogiri nodes
            # Length check
            unless children1.length == children2.length
              add_difference(n1, n2, Comparison::MISSING_NODE,
                             Comparison::MISSING_NODE, :text_content, opts,
                             differences)
              return Comparison::MISSING_NODE
            end

            # Compare children pairwise by position
            children1.zip(children2).each do |child1, child2|
              result = compare_nodes(child1, child2, child_opts, child_opts,
                                     diff_children, differences)
              return result unless result == Comparison::EQUIVALENT
            end

            Comparison::EQUIVALENT
          end
        end

        # Use ElementMatcher for semantic comparison (Canon::Xml::DataModel nodes)
        def use_element_matcher_comparison(children1, children2, parent_node,
                                          opts, child_opts, diff_children,
                                          differences)
          require_relative "../xml/element_matcher"

          # Create temporary RootNode wrappers to use ElementMatcher
          # Don't modify parent pointers - just set @children directly
          require_relative "../xml/nodes/root_node"

          temp_root1 = Canon::Xml::Nodes::RootNode.new
          temp_root1.instance_variable_set(:@children, children1.dup)

          temp_root2 = Canon::Xml::Nodes::RootNode.new
          temp_root2.instance_variable_set(:@children, children2.dup)

          matcher = Canon::Xml::ElementMatcher.new
          matches = matcher.match_trees(temp_root1, temp_root2)

          # Filter matches to only include direct children
          # match_trees returns ALL descendants, but we only want direct children
          matches = matches.select do |m|
            (m.elem1.nil? || children1.include?(m.elem1)) &&
              (m.elem2.nil? || children2.include?(m.elem2))
          end

          # If no matches and children exist, they're all different
          if matches.empty? && (!children1.empty? || !children2.empty?)
            add_difference(parent_node, parent_node, Comparison::MISSING_NODE,
                           Comparison::MISSING_NODE, :text_content, opts,
                           differences)
            return Comparison::UNEQUAL_ELEMENTS
          end

          all_equivalent = true

          matches.each do |match|
            case match.status
            when :matched
              # Check if element position changed
              if match.position_changed?
                match_opts = opts[:match_opts]
                position_behavior = match_opts[:element_position] || :strict

                # Only create DiffNode if element_position is not :ignore
                if position_behavior != :ignore
                  add_difference(
                    match.elem1,
                    match.elem2,
                    "position #{match.pos1}",
                    "position #{match.pos2}",
                    :element_position,
                    opts,
                    differences,
                  )
                  all_equivalent = false if position_behavior == :strict
                end
              end

              # Compare the matched elements for content/attribute differences
              result = compare_nodes(match.elem1, match.elem2, child_opts,
                                     child_opts, diff_children, differences)
              all_equivalent = false unless result == Comparison::EQUIVALENT

            when :deleted
              # Element present in first tree but not second
              add_difference(match.elem1, nil, Comparison::MISSING_NODE,
                             Comparison::MISSING_NODE, :text_content, opts,
                             differences)
              all_equivalent = false

            when :inserted
              # Element present in second tree but not first
              add_difference(nil, match.elem2, Comparison::MISSING_NODE,
                             Comparison::MISSING_NODE, :text_content, opts,
                             differences)
              all_equivalent = false
            end
          end

          all_equivalent ? Comparison::EQUIVALENT : Comparison::UNEQUAL_ELEMENTS
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

          # Determine node type
          # Canon::Xml::Node uses node_type that returns Symbol
          # Nokogiri uses node_type that returns Integer, so check for Symbol first
          is_comment = if node.respond_to?(:node_type) && node.node_type.is_a?(Symbol)
                         node.node_type == :comment
                       else
                         node.respond_to?(:comment?) && node.comment?
                       end

          is_text = if node.respond_to?(:node_type) && node.node_type.is_a?(Symbol)
                      node.node_type == :text
                    else
                      node.respond_to?(:text?) && node.text?
                    end

          # Ignore comments based on match options
          return true if is_comment && match_opts[:comments] == :ignore

          # Ignore text nodes if specified
          return true if opts[:ignore_text_nodes] && is_text

          # Ignore whitespace-only text nodes based on structural_whitespace
          # Both :ignore and :normalize should filter out whitespace-only nodes
          if %i[ignore
                normalize].include?(match_opts[:structural_whitespace]) && is_text
            text = node_text(node)
            return true if MatchOptions.normalize_text(text).empty?
          end

          false
        end

        # Check if two nodes are the same type
        def same_node_type?(n1, n2)
          # Canon::Xml::Node types - check node_type method
          if n1.respond_to?(:node_type) && n2.respond_to?(:node_type)
            return n1.node_type == n2.node_type
          end

          # Moxml/Nokogiri types - check individual type methods
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
          # Canon::Xml::Node TextNode uses .value
          if node.respond_to?(:value)
            node.value.to_s
          elsif node.respond_to?(:content)
            node.content.to_s
          elsif node.respond_to?(:text)
            node.text.to_s
          else
            ""
          end
        end

        # Extract element path for context (best effort)
        # @param node [Object] Node to extract path from
        # @return [Array<String>] Path components
        def extract_element_path(node)
          path = []
          current = node
          max_depth = 20
          depth = 0

          while current && depth < max_depth
            if current.respond_to?(:name) && current.name
              path.unshift(current.name)
            end

            break unless current.respond_to?(:parent)

            current = current.parent
            depth += 1

            # Stop at document root
            break if current.respond_to?(:root)
          end

          path
        end

        # Serialize a node to XML string
        # @param node [Canon::Xml::Node, Object] Node to serialize
        # @return [String] XML string representation
        def serialize_node_to_xml(node)
          if node.is_a?(Canon::Xml::Nodes::RootNode)
            # Serialize all children of root
            node.children.map { |child| serialize_node_to_xml(child) }.join
          elsif node.is_a?(Canon::Xml::Nodes::ElementNode)
            # Serialize element with attributes and children
            attrs = node.attribute_nodes.map do |a|
              " #{a.name}=\"#{a.value}\""
            end.join
            children_xml = node.children.map do |c|
              serialize_node_to_xml(c)
            end.join

            if children_xml.empty?
              "<#{node.name}#{attrs}/>"
            else
              "<#{node.name}#{attrs}>#{children_xml}</#{node.name}>"
            end
          elsif node.is_a?(Canon::Xml::Nodes::TextNode)
            node.value
          elsif node.is_a?(Canon::Xml::Nodes::CommentNode)
            "<!--#{node.value}-->"
          elsif node.is_a?(Canon::Xml::Nodes::ProcessingInstructionNode)
            "<?#{node.target} #{node.data}?>"
          elsif node.respond_to?(:to_xml)
            node.to_xml
          else
            node.to_s
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

          # Build informative reason message
          reason = build_difference_reason(node1, node2, diff1, diff2, dimension)

          diff_node = Canon::Diff::DiffNode.new(
            node1: node1,
            node2: node2,
            dimension: dimension,
            reason: reason,
          )
          differences << diff_node
        end

        # Build a human-readable reason for a difference
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param diff1 [String] Difference description for node1
        # @param diff2 [String] Difference description for node2
        # @param dimension [Symbol] The dimension of the difference
        # @return [String] Human-readable reason
        def build_difference_reason(node1, node2, diff1, diff2, dimension)
          # For deleted/inserted nodes, include namespace information if available
          if dimension == :text_content && (node1.nil? || node2.nil?)
            node = node1 || node2
            if node.respond_to?(:name) && node.respond_to?(:namespace_uri)
              ns = node.namespace_uri
              ns_info = if ns.nil? || ns.empty?
                          ""
                        else
                          " (namespace: #{ns})"
                        end
              return "element '#{node.name}'#{ns_info}: #{diff1} vs #{diff2}"
            end
          end

          "#{diff1} vs #{diff2}"
        end
      end
    end
  end
end
