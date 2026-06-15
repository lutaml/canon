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
        if Canon::XmlParsing.document_fragment?(node1) &&
            Canon::XmlParsing.document_fragment?(node2)
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

      # Filter children — delegates to MarkupComparator.
      def self.filter_children(children, opts)
        MarkupComparator.filter_children(children, opts)
      end

      # Build a side-specific opts copy that activates the pretty-print
      # structural-whitespace heuristic for the given side.
      #
      # When +pretty_printed_expected+ (side :expected) or
      # +pretty_printed_received+ (side :received) is truthy in match_opts,
      # returns a shallow copy of +opts+ with an ephemeral
      # +_pretty_print_side_active: true+ flag merged into +:match_opts+.
      # Otherwise returns +opts+ unchanged (no allocation overhead).
      #
      # The flag is consumed by +node_excluded?+ to drop whitespace-only text
      # nodes that start with "\n" in +:normalize+ whitespace elements.
      # It is intentionally NOT propagated to recursive +compare_nodes+ calls —
      # each level of +ChildComparison.compare+ re-evaluates it from the
      # original +pretty_printed_*+ flags.
      #
      # @param opts  [Hash]   Full comparison options hash
      # @param side  [Symbol] :expected or :received
      # @return [Hash] opts copy with ephemeral flag, or opts itself
      def self.opts_for_side(opts, side)
        match_opts = opts[:match_opts]
        return opts unless match_opts

        active = case side
                 when :expected then match_opts[:pretty_printed_expected]
                 when :received then match_opts[:pretty_printed_received]
                 else false
                 end

        return opts unless active

        opts.merge(match_opts: match_opts.merge(_pretty_print_side_active: true))
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

        # Filter children before comparison to handle ignored nodes (like comments with :ignore).
        # Apply side-specific pretty-print heuristic when the relevant flag is active.
        children1 = filter_children(childrenode1,
                                    opts_for_side(opts, :expected))
        children2 = filter_children(childrenode2,
                                    opts_for_side(opts, :received))

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
        if node1.is_a?(Canon::Xml::Node) && node2.is_a?(Canon::Xml::Node)
          dispatch_canon_node_type(node1, node2, opts, child_opts,
                                   diff_children, differences)
        else
          dispatch_legacy_node_type(node1, node2, opts, child_opts,
                                    diff_children, differences)
        end
      end

      # Private helper methods

      # Check if a node should be excluded — delegates to MarkupComparator.
      def self.node_excluded?(node, opts)
        MarkupComparator.node_excluded?(node, opts)
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
        node1_comment = comment_node?(node1, check_children: true)
        node2_comment = comment_node?(node2, check_children: true)

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

        case node1
        when Canon::Xml::Node
          node1.node_type == node2.node_type
        else
          if Canon::XmlBackend.nokogiri?
            node1.is_a?(Nokogiri::XML::Node) && node1.node_type == node2.node_type
          else
            Canon::XmlParsing.xml_node?(node1) && Canon::XmlParsing.node_type(node1) == Canon::XmlParsing.node_type(node2)
          end
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
      # @param check_children [Boolean] Whether to check child nodes
      # @return [Boolean] true if node is a comment
      def self.comment_node?(node, check_children: false)
        return true if NodeInspector.comment_node?(node)

        if check_children && Canon::XmlParsing.element?(node) && !Canon::XmlParsing.children(node).empty?
          node.children.any? { |child| NodeInspector.comment_node?(child) }
        else
          false
        end
      end

      # Check if a node is a text node
      #
      # @param node [Object] Node to check
      # @return [Boolean] true if node is a text node
      def self.text_node?(node)
        NodeInspector.text_node?(node)
      end

      # Extract text content from a node
      #
      # @param node [Object] Node to extract text from
      # @return [String] Text content
      def self.node_text(node)
        return "" unless node

        NodeInspector.text_content(node)
      end

      # Dispatch by Canon::Xml::Node type
      def self.dispatch_canon_node_type(node1, node2, opts, child_opts,
diff_children, differences)
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
        if Canon::XmlParsing.document?(node1)
          XmlComparator.compare_document_nodes(node1, node2, opts, child_opts,
                                               diff_children, differences)
        elsif Canon::XmlParsing.xml_node?(node1)
          if Canon::XmlParsing.element?(node1)
            XmlComparator.compare_element_nodes(node1, node2, opts, child_opts,
                                                diff_children, differences)
          elsif Canon::XmlParsing.text_node?(node1) || Canon::XmlParsing.cdata?(node1)
            XmlComparator.compare_text_nodes(node1, node2, opts, differences)
          elsif Canon::XmlParsing.comment?(node1)
            XmlComparator.compare_comment_nodes(node1, node2, opts, differences)
          elsif Canon::XmlParsing.processing_instruction?(node1)
            XmlComparator.compare_processing_instruction_nodes(node1, node2,
                                                               opts, differences)
          else
            Comparison::EQUIVALENT
          end
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

        XmlComparator.add_difference(node1, node2, diff1, diff2, dimension,
                                     opts, differences)
      end
    end
  end
end
