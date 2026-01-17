# frozen_string_literal: true

module Canon
  module Comparison
    # Public API for HTML parsing operations
    # Provides access to parsing functionality without using send()
    class HtmlParser
      # Parse an object to Canon::Xml::Node with preprocessing for semantic diff
      #
      # @param obj [String, Object] Object to parse
      # @param preprocessing [Symbol] Preprocessing mode
      # @return [Canon::Xml::Node] Parsed node
      def self.parse_node_for_semantic(obj, preprocessing = :none)
        # Delegate to HtmlComparator's private method via public API
        require_relative "html_comparator"
        HtmlComparator.parse_node_for_semantic(obj, preprocessing)
      end
    end
  end
end
