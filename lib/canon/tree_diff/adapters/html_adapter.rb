# frozen_string_literal: true

require "nokogiri"

module Canon
  module TreeDiff
    module Adapters
      # HTMLAdapter converts Nokogiri HTML documents to TreeNode structures
      # and back, enabling semantic tree diffing on HTML documents.
      #
      # This adapter:
      # - Converts Nokogiri::HTML::Document to TreeNode tree
      # - Preserves element names, text content, and attributes
      # - Handles HTML-specific elements (script, style, etc.)
      # - Maintains document structure for round-trip conversion
      #
      # @example Convert HTML to TreeNode
      #   html = Nokogiri::HTML("<html><body><p>text</p></body></html>")
      #   adapter = HTMLAdapter.new
      #   tree = adapter.to_tree(html)
      #
      class HTMLAdapter
        attr_reader :match_options

        # Initialize adapter with match options
        #
        # @param match_options [Hash] Match options for text/attribute normalization
        def initialize(match_options: {})
          @match_options = match_options
        end

        # Convert Nokogiri HTML document/element or Canon::Xml::Node to TreeNode
        #
        # @param node [Nokogiri::HTML::Document, Nokogiri::XML::Element, Nokogiri::HTML::DocumentFragment, Canon::Xml::Node] HTML node
        # @return [Core::TreeNode] Root tree node
        def to_tree(node)
          # Handle Canon::Xml::Node types first (same as XML adapter)
          case node
          when Canon::Xml::Nodes::RootNode
            return to_tree_from_canon_root(node)
          when Canon::Xml::Nodes::ElementNode
            return to_tree_from_canon_element(node)
          when Canon::Xml::Nodes::TextNode
            return to_tree_from_canon_text(node)
          when Canon::Xml::Nodes::CommentNode
            return to_tree_from_canon_comment(node)
          end

          # Fallback to Nokogiri (legacy support)
          case node
          when Nokogiri::HTML::Document, Nokogiri::HTML4::Document, Nokogiri::HTML5::Document
            # Start from html element or root element
            root = node.at_css("html") || node.root
            root ? to_tree(root) : nil
          when Nokogiri::HTML4::DocumentFragment, Nokogiri::HTML5::DocumentFragment, Nokogiri::XML::DocumentFragment
            # For DocumentFragment, create a wrapper root node and add all fragment children
            convert_fragment(node)
          when Nokogiri::XML::Element
            convert_element(node)
          else
            raise ArgumentError, "Unsupported node type: #{node.class}"
          end
        end

        # Convert TreeNode back to Nokogiri HTML
        #
        # @param tree_node [Core::TreeNode] Root tree node
        # @param doc [Nokogiri::HTML::Document] Optional document to use
        # @return [Nokogiri::HTML::Document, Nokogiri::XML::Element]
        def from_tree(tree_node, doc = nil)
          doc ||= Nokogiri::HTML::Document.new

          element = build_element(tree_node, doc)

          if doc.root.nil?
            doc.root = element
            doc
          else
            element
          end
        end

        private

        # Convert a DocumentFragment to TreeNode
        # Creates a synthetic root node containing the fragment's children
        #
        # @param fragment [Nokogiri::HTML::DocumentFragment] HTML fragment
        # @return [Core::TreeNode] Root tree node
        def convert_fragment(fragment)
          # Create a synthetic root node for the fragment
          root = Core::TreeNode.new(
            label: "fragment",
            value: nil,
            attributes: {},
            source_node: fragment,
          )

          # Add all fragment children as children of the root
          fragment.element_children.each do |child|
            child_node = convert_element(child)
            root.add_child(child_node)
          end

          root
        end

        # Convert a Nokogiri element to TreeNode
        #
        # @param element [Nokogiri::XML::Element] HTML element
        # @return [Core::TreeNode] Tree node
        def convert_element(element)
          # Get element name (lowercase for HTML)
          label = element.name.downcase

          # Collect attributes (preserve original order for tree diff)
          # The tree diff will detect attribute order differences
          # and classify them as informative when attribute_order: ignore
          #
          # CRITICAL FIX: Filter out xmlns attributes for HTML documents
          # These are typically added by parsers (e.g., MS Word) and aren't
          # semantically significant for HTML comparison. Keeping them causes
          # false mismatches that prevent the entire subtree from matching due
          # to prefix closure constraints.
          attributes = {}
          element.attributes.each do |name, attr|
            # Skip xmlns namespace declarations for HTML (but keep regular attributes)
            # This prevents false mismatches caused by parser-added namespace declarations
            next if name.start_with?("xmlns")

            attributes[name] = attr.value
          end

          # Get text content (only direct text, not from children)
          text_value = extract_text_value(element)

          # Create tree node with source_node reference
          tree_node = Core::TreeNode.new(
            label: label,
            value: text_value,
            attributes: attributes,
            source_node: element,
          )

          # Process child elements
          element.element_children.each do |child|
            child_node = convert_element(child)
            tree_node.add_child(child_node)
          end

          tree_node
        end

        # Extract direct text content from element
        #
        # Preserves original text for proper normalization during comparison.
        # Normalization happens in OperationDetector based on match_options,
        # NOT during tree conversion.
        #
        # For mixed content (text nodes + child elements), joins text nodes
        # with a space to prevent text from running together when elements
        # like <br/> separate the text.
        #
        # @param element [Nokogiri::XML::Element] HTML element
        # @return [String, nil] Text content or nil
        def extract_text_value(element)
          # Get only direct text nodes, not from nested elements
          text_nodes = element.children.select(&:text?)

          # For mixed content (has both text nodes and element children),
          # join text nodes with space to handle implicit whitespace around
          # block-level elements like <br/>
          # Example: "Text<br/>More" should become "Text More" not "TextMore"
          # EXCEPT for whitespace-sensitive elements (<pre>, <code>, etc.)
          # where we must preserve exact whitespace
          separator = if element.element_children.any? && !whitespace_sensitive?(element)
                        " "
                      else
                        ""
                      end
          text = text_nodes.map(&:text).join(separator)

          # CRITICAL FIX: Return original text without stripping
          # Normalization will be applied during comparison based on match_options
          # Only return nil for truly empty text
          text.empty? ? nil : text
        end

        # Check if an element is whitespace-sensitive
        #
        # HTML elements where whitespace is significant: <pre>, <code>, <textarea>, <script>, <style>
        #
        # @param element [Nokogiri::XML::Element] Element to check
        # @return [Boolean] True if element is whitespace-sensitive
        def whitespace_sensitive?(element)
          return false unless element.respond_to?(:name)

          # List of HTML elements where whitespace is semantically significant
          whitespace_sensitive_tags = %w[pre code textarea script style]
          whitespace_sensitive_tags.include?(element.name.downcase)
        end

        # Build Nokogiri element from TreeNode
        #
        # @param tree_node [Core::TreeNode] Tree node
        # @param doc [Nokogiri::HTML::Document] Document
        # @return [Nokogiri::XML::Element] HTML element
        def build_element(tree_node, doc)
          element = Nokogiri::XML::Element.new(tree_node.label, doc)

          # Add attributes
          tree_node.attributes.each do |name, value|
            element[name] = value
          end

          # Add text content if present
          if tree_node.value && !tree_node.value.empty?
            element.content = tree_node.value
          end

          # Add child elements
          tree_node.children.each do |child|
            child_element = build_element(child, doc)
            element.add_child(child_element)
          end

          element
        end

        # Convert Canon::Xml::Nodes::RootNode to TreeNode
        #
        # @param root_node [Canon::Xml::Nodes::RootNode] Root node
        # @return [Core::TreeNode, nil] Tree node for first child (document element)
        def to_tree_from_canon_root(root_node)
          # CRITICAL FIX: RootNode contains all the parsed HTML content (body children)
          # We need to create a TreeNode root and add all children to it
          # Previously, this method only processed the first child, which caused
          # most of the content to be lost during semantic diff
          return nil if root_node.children.empty?

          # Create a root TreeNode
          tree_root = Core::TreeNode.new(
            label: :root,
            value: nil,
            attributes: {},
            children: [],
            source_node: root_node,
          )

          # Add all children of the RootNode to the TreeNode root
          root_node.children.each do |child|
            child_tree = to_tree(child)
            tree_root.add_child(child_tree) if child_tree
          end

          tree_root
        end

        # Convert Canon::Xml::Nodes::ElementNode to TreeNode
        #
        # @param element_node [Canon::Xml::Nodes::ElementNode] Element node
        # @return [Core::TreeNode] Tree node
        def to_tree_from_canon_element(element_node)
          # Create TreeNode from Canon::Xml::Nodes::ElementNode
          tree_node = Core::TreeNode.new(
            label: element_node.name.downcase, # Lowercase for HTML
            value: nil, # Elements don't have values
            attributes: extract_canon_attributes(element_node),
            children: [],
            source_node: element_node, # Preserve reference to Canon node
          )

          # Process children recursively
          element_node.children.each do |child|
            child_tree = to_tree(child)
            tree_node.add_child(child_tree) if child_tree
          end

          tree_node
        end

        # Convert Canon::Xml::Nodes::TextNode to TreeNode
        #
        # @param text_node [Canon::Xml::Nodes::TextNode] Text node
        # @return [Core::TreeNode, nil] Tree node or nil for empty text
        def to_tree_from_canon_text(text_node)
          # Extract text value
          text_value = text_node.value.to_s

          # Return nil for empty text (don't strip for HTML)
          return nil if text_value.empty?

          Core::TreeNode.new(
            label: "text",
            value: text_value,
            attributes: {},
            children: [],
            source_node: text_node,
          )
        end

        # Convert Canon::Xml::Nodes::CommentNode to TreeNode
        #
        # @param comment_node [Canon::Xml::Nodes::CommentNode] Comment node
        # @return [Core::TreeNode] Tree node
        def to_tree_from_canon_comment(comment_node)
          Core::TreeNode.new(
            label: "comment",
            value: comment_node.value,
            attributes: {},
            children: [],
            source_node: comment_node,
          )
        end

        # Extract attributes from Canon::Xml::Nodes::ElementNode
        #
        # @param element_node [Canon::Xml::Nodes::ElementNode] Element node
        # @return [Hash] Attributes hash (preserves order, filters xmlns)
        def extract_canon_attributes(element_node)
          # Canon::Xml::Nodes::ElementNode has attribute_nodes array
          attrs = {}
          element_node.attribute_nodes.each do |attr|
            # Skip xmlns attributes for HTML (like Nokogiri path)
            next if attr.name.start_with?("xmlns")

            attrs[attr.name] = attr.value
          end
          attrs
        end
      end
    end
  end
end
