# frozen_string_literal: true

module Canon
  # Native XML data model, parsing, and DOM utilities.
  #
  # This namespace holds Canon's own XML representation (independent of
  # Nokogiri/Moxml), including:
  # * the XPath data model nodes (Canon::Xml::Node and Canon::Xml::Nodes::*)
  # * the SAX builder that produces them
  # * element matching, line-range mapping, xpath, C14N, processors
  # * canonicalization (C14n) and serialization helpers
  #
  # All children are autoloaded from this file. The nested Nodes namespace
  # is itself a sibling and is autoloaded on first reference to
  # Canon::Xml::Nodes.
  module Xml
    autoload :AttributeHandler, "canon/xml/attribute_handler"
    autoload :C14n, "canon/xml/c14n"
    autoload :CharacterEncoder, "canon/xml/character_encoder"
    autoload :DataModel, "canon/xml/data_model"
    autoload :ElementMatcher, "canon/xml/element_matcher"
    autoload :LineRangeMapper, "canon/xml/line_range_mapper"
    autoload :NamespaceHandler, "canon/xml/namespace_handler"
    autoload :NamespaceHelper, "canon/xml/namespace_helper"
    autoload :Node, "canon/xml/node"
    autoload :Nodes, "canon/xml/nodes"
    autoload :Processor, "canon/xml/processor"
    autoload :SaxBuilder, "canon/xml/sax_builder"
    autoload :WhitespaceNormalizer, "canon/xml/whitespace_normalizer"
    autoload :XmlBaseHandler, "canon/xml/xml_base_handler"
    autoload :XPathEngine, "canon/xml/xpath_engine"
  end
end
