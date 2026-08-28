# frozen_string_literal: true

module Canon
  module Html
    # Nokogiri node utilities for the HTML pipeline.
    #
    # HTML parsing is Nokogiri's job on every CRuby runtime regardless of
    # the XML engine (XmlBackend): moxml has no HTML adapter and leptris no
    # HTML parser. Under Opal Nokogiri is unavailable and these helpers
    # degrade the same way the moxml backend always did (false / nil /
    # raise), which keeps HTML comparison unsupported there.
    module NokogiriSupport
      class << self
        # Whether the node is a document fragment (any variant).
        def document_fragment?(node)
          return false unless defined?(Nokogiri)

          node.is_a?(Nokogiri::XML::DocumentFragment) ||
            node.is_a?(Nokogiri::HTML4::DocumentFragment) ||
            node.is_a?(Nokogiri::HTML5::DocumentFragment)
        end

        # Whether the node is an HTML document (any variant).
        def html_document?(node)
          return false unless defined?(Nokogiri)

          node.is_a?(Nokogiri::HTML::Document) ||
            node.is_a?(Nokogiri::HTML4::Document) ||
            node.is_a?(Nokogiri::HTML5::Document)
        end

        # Detect HTML version from a Nokogiri node.
        # Returns :html5 or :html4. Defaults to :html5 for non-Nokogiri nodes.
        def html_version_from_node(node)
          return :html5 unless defined?(Nokogiri)

          if node.is_a?(Nokogiri::HTML5::Document) ||
              node.is_a?(Nokogiri::HTML5::DocumentFragment)
            :html5
          elsif node.is_a?(Nokogiri::HTML4::Document) ||
              node.is_a?(Nokogiri::HTML4::DocumentFragment)
            :html4
          else
            :html5
          end
        end

        # Parse an HTML string into an XML fragment for the XML comparator.
        def xml_fragment(html_string)
          unless defined?(Nokogiri)
            raise Canon::Error,
                  "HTML fragment parsing requires Nokogiri"
          end

          Nokogiri::XML.fragment(html_string)
        end
      end
    end
  end
end
