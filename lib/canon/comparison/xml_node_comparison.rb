# frozen_string_literal: true

module Canon
  module Comparison
    # XML Node Comparison Utilities
    #
    # Provides public comparison methods for XML/HTML nodes.
    # This module extracts shared comparison logic that was previously
    # accessed via send() from HtmlComparator.
    #
    # This is a simple utility module with focused responsibilities.
    module XmlNodeComparison
      # Main comparison dispatcher for XML nodes
      #
      # This method handles the high-level comparison logic, delegating
      # to specific comparison methods based on node types.
      #
      # @param node1 [Object] First node
      # @param node2 [Object] Second node
      # @param opts [Hash] Comparison options
      # @param child_opts [Hash] Options for child comparison
      # @param diff_children [Boolean] Whether to diff children
      # @param differences [Array] Array to append differences to
      # @return [Symbol] Comparison result constant
      def self.compare_nodes(node1, node2, opts, child_opts, diff_children,
differences)
        # Handle DocumentFragment nodes - compare their children instead
        if node1.is_a?(Nokogiri::XML::DocumentFragment) &&
            node2.is_a?(Nokogiri::XML::DocumentFragment)
          return compare_document_fragments(node1, node2, opts, child_opts,
                                            diff_children, differences)
        end

        # Check if nodes should be excluded
        return Comparison::EQUIVALENT if node_excluded?(node1, opts) &&
          node_excluded?(node2, opts)

        if node_excluded?(node1, opts) || node_excluded?(node2, opts)
          add_difference(node1, node2, Comparison::MISSING_NODE,
                         Comparison::MISSING_NODE, :text_content, opts,
                         differences)
          return Comparison::MISSING_NODE
        end

        # Handle comment vs non-comment comparisons specially
        # When comparing a comment with a non-comment node (due to zip pairing),
        # create a :comments dimension difference instead of UNEQUAL_NODES_TYPES
        if comment_vs_non_comment_comparison?(node1, node2)
          match_opts = opts[:match_opts]
          comment_behavior = match_opts ? match_opts[:comments] : nil

          # Create a :comments dimension difference
          # The difference will be marked as normative or not based on the HtmlCompareProfile
          add_difference(node1, node2, Comparison::MISSING_NODE,
                         Comparison::MISSING_NODE, :comments, opts,
                         differences)

          # Return EQUIVALENT if comments are ignored, otherwise return UNEQUAL
          if comment_behavior == :ignore
            Comparison::EQUIVALENT
          else
            Comparison::UNEQUAL_COMMENTS
          end
        end

        # Check node types match
        unless same_node_type?(node1, node2)
          add_difference(node1, node2, Comparison::UNEQUAL_NODES_TYPES,
                         Comparison::UNEQUAL_NODES_TYPES, :text_content, opts,
                         differences)
          return Comparison::UNEQUAL_NODES_TYPES
        end

        # Dispatch based on node type
        dispatch_by_node_type(node1, node2, opts, child_opts, diff_children,
                              differences)
      end

      # Filter children based on options
      #
      # Removes nodes that should be excluded from comparison based on
      # options like :ignore_nodes, :ignore_comments, etc.
      #
      # @param children [Array] Array of child nodes
      # @param opts [Hash] Comparison options
      # @return [Array] Filtered array of children
      def self.filter_children(children, opts)
        children.reject do |child|
          node_excluded?(child, opts)
        end
      end

      # Compare document fragments by comparing their children
      #
      # @param node1 [Nokogiri::XML::DocumentFragment] First fragment
      # @param node2 [Nokogiri::XML::DocumentFragment] Second fragment
      # @param opts [Hash] Comparison options
      # @param child_opts [Hash] Options for child comparison
      # @param diff_children [Boolean] Whether to diff children
      # @param differences [Array] Array to append differences to
      # @return [Symbol] Comparison result constant
      def self.compare_document_fragments(node1, node2, opts, child_opts,
                                          diff_children, differences)
        childrenode1 = node1.children.to_a
        childrenode2 = node2.children.to_a

        # Filter children before comparison to handle ignored nodes (like comments with :ignore)
        children1 = filter_children(childrenode1, opts)
        children2 = filter_children(childrenode2, opts)

        if children1.length != children2.length
          add_difference(node1, node2, Comparison::UNEQUAL_ELEMENTS,
                         Comparison::UNEQUAL_ELEMENTS, :text_content, opts,
                         differences)
          # Continue comparing children to find deeper differences like attribute values
          # Use zip to compare up to the shorter length
        end

        if children1.empty? && children2.empty?
          Comparison::EQUIVALENT
        else
          # Compare each pair of children (up to the shorter length)
          result = Comparison::EQUIVALENT
          children1.zip(children2).each do |child1, child2|
            # Skip if one is nil (due to different lengths)
            next if child1.nil? || child2.nil?

            child_result = compare_nodes(child1, child2, opts, child_opts,
                                         diff_children, differences)
            result = child_result unless result == Comparison::EQUIVALENT
          end
          result
        end
      end

      # Dispatch comparison based on node type
      #
      # @param node1 [Object] First node
      # @param node2 [Object] Second node
      # @param opts [Hash] Comparison options
      # @param child_opts [Hash] Options for child comparison
      # @param diff_children [Boolean] Whether to diff children
      # @param differences [Array] Array to append differences to
      # @return [Symbol] Comparison result constant
      def self.dispatch_by_node_type(node1, node2, opts, child_opts,
diff_children, differences)
        # Canon::Xml::Node types use .node_type method that returns symbols
        # Nokogiri also has .node_type but returns integers, so check for Symbol
        if node1.respond_to?(:node_type) && node2.respond_to?(:node_type) &&
            node1.node_type.is_a?(Symbol) && node2.node_type.is_a?(Symbol)
          dispatch_canon_node_type(node1, node2, opts, child_opts,
                                   diff_children, differences)
        # Moxml/Nokogiri types use .element?, .text?, etc. methods
        else
          dispatch_legacy_node_type(node1, node2, opts, child_opts,
                                    diff_children, differences)
        end
      end

      # Private helper methods

      # Check if a node should be excluded from comparison
      #
      # @param node [Object] Node to check
      # @param opts [Hash] Comparison options
      # @return [Boolean] true if node should be excluded
      def self.node_excluded?(node, opts)
        return false if node.nil?

        return true if opts[:ignore_nodes]&.include?(node)
        return true if opts[:ignore_comments] && comment_node?(node)
        return true if opts[:ignore_text_nodes] && text_node?(node)

        # Check match options
        match_opts = opts[:match_opts]
        return false unless match_opts

        # Filter comments based on match options and format
        # HTML: Filter comments to avoid spurious differences from zip pairing
        #       BUT only when not in verbose mode (verbose needs differences recorded)
        # XML: Don't filter comments (allow informative differences to be recorded)
        if match_opts[:comments] == :ignore && comment_node?(node)
          # In verbose mode, don't filter comments - we want to record the differences
          return false if opts[:verbose]

          # Only filter comments for HTML, not XML (when not verbose)
          format = opts[:format] || match_opts[:format]
          if %i[html html4 html5].include?(format)
            return true
          end
        end

        # Filter out whitespace-only text nodes based on structural_whitespace setting
        # - :ignore or :normalize: Filter all whitespace-only text nodes
        # - :strict: Preserve all whitespace-only text nodes (don't filter any)
        if text_node?(node) && %i[ignore
                                  normalize].include?(match_opts[:structural_whitespace])
          text = node_text(node)
          return true if MatchOptions.normalize_text(text).empty?
        end

        false
      end

      # Check if this is a comment vs non-comment comparison
      #
      # This handles the case where zip pairs a comment with a non-comment node
      # due to different lengths in the children arrays. We create a :comments
      # dimension difference instead of UNEQUAL_NODES_TYPES.
      #
      # @param node1 [Object] First node
      # @param node2 [Object] Second node
      # @return [Boolean] true if one node is a comment and the other isn't
      def self.comment_vs_non_comment_comparison?(node1, node2)
        node1_comment = comment_node?(node1)
        node2_comment = comment_node?(node2)

        # XOR: exactly one is a comment
        node1_comment ^ node2_comment
      end

      # Check if two nodes are of the same type
      #
      # @param node1 [Object] First node
      # @param node2 [Object] Second node
      # @return [Boolean] true if nodes are same type
      def self.same_node_type?(node1, node2)
        return false if node1.class != node2.class

        # For Nokogiri/Canon::Xml nodes, check node type
        if node1.respond_to?(:node_type) && node2.respond_to?(:node_type)
          node1.node_type == node2.node_type
        else
          true
        end
      end

      # Check if a node is a comment node
      #
      # For XML/XHTML, this checks the node's comment? method or node_type.
      # For HTML, this also checks TEXT nodes that contain HTML-style comments
      # (Nokogiri parses HTML comments as TEXT nodes with content like "<!-- comment -->"
      # or escaped like "<\\!-- comment -->" in full HTML documents).
      #
      # @param node [Object] Node to check
      # @return [Boolean] true if node is a comment
      def self.comment_node?(node)
        return true if node.respond_to?(:comment?) && node.comment?
        return true if node.respond_to?(:node_type) && node.node_type == :comment

        # HTML comments are parsed as TEXT nodes by Nokogiri
        # Check if this is a text node with HTML comment content
        if text_node?(node)
          text = node_text(node)
          # Strip whitespace and backslashes for comparison
          # Nokogiri escapes HTML comments as "<\\!-- comment -->" in full documents
          text_stripped = text.to_s.strip.gsub("\\", "")
          return true if text_stripped.start_with?("<!--") && text_stripped.end_with?("-->")
        end

        false
      end

      # Check if a node is a text node
      #
      # @param node [Object] Node to check
      # @return [Boolean] true if node is a text node
      def self.text_node?(node)
        node.respond_to?(:text?) && node.text? &&
          !node.respond_to?(:element?) ||
          node.respond_to?(:node_type) && node.node_type == :text
      end

      # Extract text content from a node
      #
      # @param node [Object] Node to extract text from
      # @return [String] Text content
      def self.node_text(node)
        return "" unless node

        if node.respond_to?(:content)
          node.content.to_s
        elsif node.respond_to?(:text)
          node.text.to_s
        elsif node.respond_to?(:value)
          node.value.to_s
        else
          ""
        end
      end

      # Dispatch by Canon::Xml::Node type
      def self.dispatch_canon_node_type(node1, node2, opts, child_opts,
diff_children, differences)
        # Import XmlComparator to use its comparison methods
        require_relative "xml_comparator"

        case node1.node_type
        when :root
          XmlComparator.compare_children(node1, node2, opts, child_opts,
                                         diff_children, differences)
        when :element
          XmlComparator.compare_element_nodes(node1, node2, opts, child_opts,
                                              diff_children, differences)
        when :text
          XmlComparator.compare_text_nodes(node1, node2, opts, differences)
        when :comment
          XmlComparator.compare_comment_nodes(node1, node2, opts, differences)
        when :cdata
          XmlComparator.compare_text_nodes(node1, node2, opts, differences)
        when :processing_instruction
          XmlComparator.compare_processing_instruction_nodes(node1, node2,
                                                             opts, differences)
        else
          Comparison::EQUIVALENT
        end
      end

      # Dispatch by legacy Nokogiri/Moxml node type
      def self.dispatch_legacy_node_type(node1, node2, opts, child_opts,
diff_children, differences)
        # Import XmlComparator to use its comparison methods
        require_relative "xml_comparator"

        if node1.respond_to?(:element?) && node1.element?
          XmlComparator.compare_element_nodes(node1, node2, opts, child_opts,
                                              diff_children, differences)
        elsif node1.respond_to?(:text?) && node1.text?
          XmlComparator.compare_text_nodes(node1, node2, opts, differences)
        elsif node1.respond_to?(:comment?) && node1.comment?
          XmlComparator.compare_comment_nodes(node1, node2, opts, differences)
        elsif node1.respond_to?(:cdata?) && node1.cdata?
          XmlComparator.compare_text_nodes(node1, node2, opts, differences)
        elsif node1.respond_to?(:processing_instruction?) && node1.processing_instruction?
          XmlComparator.compare_processing_instruction_nodes(node1, node2,
                                                             opts, differences)
        elsif node1.respond_to?(:root)
          XmlComparator.compare_document_nodes(node1, node2, opts, child_opts,
                                               diff_children, differences)
        else
          Comparison::EQUIVALENT
        end
      end

      # Add a difference to the differences array
      #
      # @param node1 [Object] First node
      # @param node2 [Object] Second node
      # @param diff1 [Symbol] Difference type for node1
      # @param diff2 [Symbol] Difference type for node2
      # @param dimension [Symbol] The dimension of the difference
      # @param opts [Hash] Comparison options
      # @param differences [Array] Array to append difference to
      def self.add_difference(node1, node2, diff1, diff2, dimension, opts,
differences)
        return unless opts[:verbose]

        require_relative "xml_comparator"
        XmlComparator.add_difference(node1, node2, diff1, diff2, dimension,
                                     opts, differences)
      end

      # Serialize a Canon::Xml::Node to XML string
      #
      # This utility method handles serialization of different node types
      # to their string representation for display and debugging purposes.
      #
      # @param node [Canon::Xml::Node, Object] Node to serialize
      # @return [String] XML string representation
      def self.serialize_node_to_xml(node)
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
    end
  end
end
