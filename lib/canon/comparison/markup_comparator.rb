# frozen_string_literal: true

module Canon
  module Comparison
    # Base class for markup document comparison (XML, HTML)
    #
    # Provides shared comparison functionality for markup documents,
    # including node type checking, text extraction, filtering,
    # and difference creation.
    #
    # Format-specific comparators (XmlComparator, HtmlComparator)
    # inherit from this class and add format-specific behavior.
    class MarkupComparator
      class << self
        # Add a difference to the differences array.
        #
        # Delegates to DiffNodeBuilder, the single DiffNode factory for
        # the DOM comparison path.
        def add_difference(node1, node2, diff1, diff2, dimension, _opts,
                           differences)
          differences << Canon::Comparison::DiffNodeBuilder.build(
            node1: node1, node2: node2, diff1: diff1, diff2: diff2,
            dimension: dimension
          )
        end

        # Serialize a node to string for display
        #
        # @param node [Object, nil] Node to serialize
        # @return [String, nil] Serialized content
        def serialize_node(node)
          return nil if node.nil?

          Canon::Diff::NodeSerializer.serialize(node)
        end

        # Extract attributes from a node
        #
        # @param node [Object, nil] Node to extract attributes from
        # @return [Hash, nil] Hash of attribute name => value pairs
        def extract_attributes(node)
          return nil if node.nil?

          Canon::Diff::NodeSerializer.extract_attributes(node)
        end

        # Filter children based on options
        #
        # Removes nodes that should be excluded from comparison based on
        # options like :ignore_nodes, :ignore_comments, etc.
        #
        # @param children [Array] Array of child nodes
        # @param opts [Hash] Comparison options
        # @return [Array] Filtered array of children
        def filter_children(children, opts)
          children.reject do |child|
            node_excluded?(child, opts)
          end
        end

        # Check if node should be excluded from comparison
        #
        # @param node [Object] Node to check
        # @param opts [Hash] Comparison options
        # @return [Boolean] true if node should be excluded
        def node_excluded?(node, opts)
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

          # Strip whitespace-only text nodes based on parent element configuration.
          # Use preserve_whitespace_elements / strip_whitespace_elements to control.
          # Blacklist (strip) > preserve > collapse > format defaults.
          return false unless text_node?(node) && node.parent
          return false unless MatchOptions.normalize_text(node_text(node)).empty?

          # NBSP (U+00A0) is never insignificant whitespace —
          # it always renders as a visible non-breaking space.
          # For HTML: always preserve NBSP nodes.
          # For XML with whitespace_type: :strict: preserve NBSP nodes so
          # different Unicode whitespace types remain distinguishable.
          format = opts[:format] || match_opts[:format]
          whitespace_type = match_opts[:whitespace_type] || :strict
          if (%i[html html4
                 html5].include?(format) || whitespace_type == :strict) && WhitespaceSensitivity.contains_nbsp?(node_text(node))
            return false
          end

          if %i[html html4
                html5].include?(format) && WhitespaceSensitivity.inline_whitespace_significant?(node)
            # Whitespace between inline element siblings is semantically
            # significant (renders as a visible gap) and must not be stripped.
            return false
          end

          return true unless WhitespaceSensitivity.whitespace_preserved?(
            node.parent, match_opts
          )

          # When the pretty-print-side flag is active (set by opts_for_side in
          # ChildComparison.compare), drop whitespace-only text nodes that start
          # with "\n" inside :collapse elements — they are structural indentation
          # from the pretty-printer, not content.  Space-only nodes (no initial "\n") are
          # real inline content and are kept for normalised comparison.
          # :preserve elements are always left unchanged.
          if match_opts[:_pretty_print_side_active]
            ws_class = WhitespaceSensitivity.classify_text_node(node, opts)
            return true if ws_class == :collapse && node_text(node).start_with?("\n")
          end

          false
        end

        # Check if two nodes are the same type
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @return [Boolean] true if nodes are same type
        def same_node_type?(node1, node2)
          return false if node1.class != node2.class

          case node1
          when Canon::Xml::Node, Nokogiri::XML::Node
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
        def comment_node?(node)
          NodeInspector.comment_node?(node)
        end

        # Check if a node is a text node
        #
        # @param node [Object] Node to check
        # @return [Boolean] true if node is a text node
        def text_node?(node)
          NodeInspector.text_node?(node)
        end

        # Get text content from a node
        #
        # @param node [Object] Node to get text from
        # @return [String] Text content
        def node_text(node)
          NodeInspector.text_content(node)
        end

        # Check if difference between two texts is only whitespace
        #
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

        # Build a human-readable reason for a difference
        #
        # Delegates to DiffNodeBuilder for consistency.
        def build_difference_reason(node1, node2, diff1, diff2, dimension)
          Canon::Comparison::DiffNodeBuilder.build_reason(
            node1, node2, diff1, diff2, dimension
          )
        end

        # Extract text content from a node for diff reason
        #
        # @param node [Object, nil] Node to extract text from
        # @return [String, nil] Text content or nil
        def extract_text_content_from_node(node)
          Canon::Comparison::DiffNodeBuilder.extract_text_content(node)
        end

        # Truncate text for display in reason messages
        def truncate_text(text, max_length = 40)
          Canon::Comparison::DiffNodeBuilder.truncate(text, max_length)
        end

        # Determine the appropriate dimension for a node type
        #
        # Used by ChildComparison to tag per-child orphan diffs with a
        # dimension that matches what the node *is*, so the formatter
        # renders correctly.  An element orphan tagged :text_content
        # would otherwise route through PR #126's one-sided text
        # formatter and render as +text ""+ instead of as the actual
        # element (see lutaml/canon#125 follow-up).
        #
        # @param node [Object] The node to check
        # @return [Symbol] The dimension symbol
        def determine_node_dimension(node)
          case node
          when Canon::Xml::Node
            case node.node_type
            when :element then :element_structure
            when :comment then :comments
            when :text, :cdata then :text_content
            when :processing_instruction then :processing_instructions
            else :text_content
            end
          when Nokogiri::XML::Node
            if node.comment?
              :comments
            elsif node.text? || node.cdata?
              :text_content
            elsif node.processing_instruction?
              :processing_instructions
            elsif node.element?
              :element_structure
            else
              :text_content
            end
          else
            :text_content
          end
        end
      end
    end
  end
end
