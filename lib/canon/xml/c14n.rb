# frozen_string_literal: true

require_relative "data_model"
require_relative "processor"

module Canon
  module Xml
    # XML Canonicalization 1.1 implementation
    # Per W3C Recommendation: https://www.w3.org/TR/xml-c14n11/
    class C14n
      # Canonicalize an XML document
      # @param xml [String] XML document as string
      # @param with_comments [Boolean] Include comments in canonical form
      # @return [String] Canonical form in UTF-8
      def self.canonicalize(xml, with_comments: false)
        # Build XPath data model
        root_node = DataModel.from_xml(xml)

        # Process to canonical form
        processor = Processor.new(with_comments: with_comments)
        processor.process(root_node)
      end

      # Canonicalize a document subset (for future implementation)
      # @param xml [String] XML document as string
      # @param xpath [String] XPath expression for subset selection
      # @param with_comments [Boolean] Include comments in canonical form
      # @return [String] Canonical form in UTF-8
      def self.canonicalize_subset(xml, _xpath, with_comments: false)
        # TODO: Implement XPath-based subset selection
        # For now, just canonicalize the whole document
        canonicalize(xml, with_comments: with_comments)
      end
    end
  end
end
