# frozen_string_literal: true

module Canon
  module XmlBackend
    class << self
      def active
        @active ||= detect
      end

      def nokogiri?
        active == :nokogiri
      end

      def moxml?
        active == :moxml
      end

      def reset!
        @active = nil
      end

      # Whether the node is a document fragment (any variant).
      def document_fragment?(node)
        if nokogiri?
          node.is_a?(Nokogiri::XML::DocumentFragment) ||
            node.is_a?(Nokogiri::HTML4::DocumentFragment) ||
            node.is_a?(Nokogiri::HTML5::DocumentFragment)
        else
          false
        end
      end

      # Whether the node is an HTML document (any variant).
      def html_document?(node)
        if nokogiri?
          node.is_a?(Nokogiri::HTML::Document) ||
            node.is_a?(Nokogiri::HTML4::Document) ||
            node.is_a?(Nokogiri::HTML5::Document)
        else
          false
        end
      end

      # Detect HTML version from a Nokogiri node.
      # Returns :html5 or :html4. Defaults to :html5 for non-Nokogiri nodes.
      def html_version_from_node(node)
        if nokogiri?
          if node.is_a?(Nokogiri::HTML5::Document) ||
              node.is_a?(Nokogiri::HTML5::DocumentFragment)
            :html5
          elsif node.is_a?(Nokogiri::HTML4::Document) ||
              node.is_a?(Nokogiri::HTML4::DocumentFragment)
            :html4
          else
            :html5
          end
        else
          :html5
        end
      end

      # Parse an HTML string into an XML fragment.
      def xml_fragment(html_string)
        if nokogiri?
          Nokogiri::XML.fragment(html_string)
        else
          raise Canon::Error,
                "HTML fragment parsing requires the Nokogiri backend"
        end
      end

      private

      def detect
        if RUBY_ENGINE == "opal"
          :moxml
        elsif defined?(Nokogiri)
          :nokogiri
        else
          :moxml
        end
      end
    end
  end
end
