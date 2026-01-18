# frozen_string_literal: true

module Canon
  module Comparison
    # Public API for XML parsing operations
    # Provides access to parsing functionality without using send()
    class XmlParser
      # Parse an object to Canon::Xml::Node with preprocessing
      #
      # @param obj [String, Object] Object to parse
      # @param preprocessing [Symbol] Preprocessing mode
      # @return [Canon::Xml::Node] Parsed node
      def self.parse_node(obj, preprocessing = :none)
        # Delegate to XmlComparator's private method via public API
        XmlComparator::NodeParser.parse(obj, preprocessing)
      end
    end
  end
end
