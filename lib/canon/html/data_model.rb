# frozen_string_literal: true

require "nokogiri" unless RUBY_ENGINE == "opal"

module Canon
  module Html
    # Builds XPath data model from HTML
    # HTML-specific parsing with lowercase element/attribute names,
    # whitespace-sensitive element handling, and fragment parsing
    class DataModel < Canon::DataModel
      # Build XPath data model from HTML string
      #
      # @param html_string [String] HTML content to parse
      # @param version [Symbol] HTML version (:html4 or :html5)
      # @return [Canon::Xml::Nodes::RootNode] Root of the data model tree
      def self.from_html(html_string, version: :html4)
        # Detect if this is a full document (has <html> tag) or fragment
        # Full documents should use document parser to preserve structure
        # Fragments should use fragment parser to avoid adding implicit wrappers
        is_full_document = html_string.match?(%r{<html[\s>]}i)

        # Parse with Nokogiri using appropriate parser
        doc = if is_full_document
                # CRITICAL FIX: For full HTML documents, parse as document first
                # and extract the body element. This avoids Nokogiri::HTML.fragment()
                # incorrectly moving head elements (like meta) to the body.
                # Parse as full document to get proper structure
                full_doc = if version == :html5
                             Nokogiri::HTML5(html_string)
                           else
                             Nokogiri::HTML4(html_string)
                           end
                # Extract body element and create fragment from it
                body = full_doc.at_css("body")
                if body
                  # Create a fragment and copy body children to it
                  # This preserves the body structure without head elements
                  frag = if version == :html5
                           Nokogiri::HTML5::DocumentFragment.new(full_doc)
                         else
                           Nokogiri::HTML4::DocumentFragment.new(full_doc)
                         end
                  body.children.each do |child|
                    frag.add_child(child.dup)
                  end
                  frag
                elsif version == :html5
                  # No body found, fall back to fragment parsing
                  Nokogiri::HTML5.fragment(html_string)
                else
                  Nokogiri::HTML4.fragment(html_string)
                end
              elsif version == :html5
                # Fragment - use fragment parser to avoid implicit wrappers
                Nokogiri::HTML5.fragment(html_string)
              else
                Nokogiri::HTML4.fragment(html_string)
              end

        # HTML doesn't have strict namespace requirements like XML,
        # so skip the relative namespace URI check

        # Convert to XPath data model (reuse XML infrastructure)
        build_from_nokogiri(doc)
      end

      # Alias for compatibility
      def self.parse(html_string, version: :html4)
        from_html(html_string, version: version)
      end

      # Serialize HTML node to string
      def self.serialize(node)
        # HTML nodes use the same serialization as XML
        # Delegate to XML serialization implementation
        Canon::Xml::DataModel.serialize(node)
      end

      # Build XPath data model from a Nokogiri HTML document or
      # fragment — a TreeBuilder walk like the XML extractors, with the
      # HTML whitespace policy and xmlns-free attributes.
      def self.build_from_nokogiri(nokogiri_doc)
        builder = Canon::Xml::TreeBuilder.new
        root = Canon::Xml::Nodes::RootNode.new
        skip_types = defined?(Nokogiri) ? [Nokogiri::XML::DTD] : []

        if nokogiri_doc.is_a?(Nokogiri::XML::Document) && nokogiri_doc.root
          root.add_child(walk(builder, nokogiri_doc.root))
          builder.add_document_children(root, nokogiri_doc.children,
                                        nokogiri_doc.root, skip_types) do |child|
            walk(builder, child)
          end
        else
          builder.add_document_children(root, nokogiri_doc.children,
                                        nil, skip_types) do |child|
            walk(builder, child)
          end
        end

        root
      end

      def self.walk(builder, node, inherited_namespaces: nil)
        case node
        when Nokogiri::XML::Element
          scope = builder.merge_namespace_scope(
            inherited_namespaces,
            node.namespace_definitions.map { |ns| [ns.prefix, ns.href] },
          )
          element = builder.element(
            name: node.name,
            prefix: node.namespace&.prefix,
            namespace_uri: node.namespace&.href,
            # HTML attributes are namespace-free; xmlns declarations are
            # not reported as attributes.
            attributes: node.attribute_nodes.filter_map do |attr|
              next if attr.name.start_with?("xmlns")

              [attr.name, attr.value, nil, nil]
            end,
            namespace_scope: scope,
          )
          node.children.each do |child|
            built = walk(builder, child, inherited_namespaces: scope)
            element.add_child(built) if built
          end
          element
        when Nokogiri::XML::Text
          builder.text(
            node.content,
            keep: Canon::Xml::WhitespacePolicy.keep_html_text?(
              node.content,
              parent_name: node.parent.is_a?(Nokogiri::XML::Element) ? node.parent.name : nil,
              inline_significant:
                Canon::Comparison::WhitespaceSensitivity.inline_whitespace_significant?(node),
            ),
          )
        when Nokogiri::XML::Comment
          builder.comment(node.content)
        when Nokogiri::XML::ProcessingInstruction
          builder.processing_instruction(node.name, node.content)
        end
      end

      class << self
        private :build_from_nokogiri, :walk
      end
    end
  end
end
