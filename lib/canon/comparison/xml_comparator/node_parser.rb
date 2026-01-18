# frozen_string_literal: true

require_relative "../../xml/c14n"

module Canon
  module Comparison
    module XmlComparatorHelpers
      # Node parser with preprocessing support
      # Handles conversion of strings and various node types to Canon::Xml::Node
      class NodeParser
        # Parse a node from string or return as-is
        # Applies preprocessing transformation before parsing if specified
        #
        # @param node [String, Object] Node to parse
        # @param preprocessing [Symbol] Preprocessing mode (:none, :normalize, :c14n, :format)
        # @return [Canon::Xml::Node] Parsed node
        def self.parse(node, preprocessing = :none)
          # If already a Canon::Xml::Node, return as-is
          return node if node.is_a?(Canon::Xml::Node)

          # If it's a Nokogiri or Moxml node, convert to DataModel
          unless node.is_a?(String)
            return convert_from_node(node)
          end

          # Apply preprocessing to XML string before parsing
          xml_string = apply_preprocessing(node, preprocessing)

          # Use Canon::Xml::DataModel for parsing to get Canon::Xml::Node instances
          Canon::Xml::DataModel.from_xml(xml_string)
        end

        # Apply preprocessing transformation to XML string
        #
        # @param xml_string [String] XML string to preprocess
        # @param preprocessing [Symbol] Preprocessing mode
        # @return [String] Preprocessed XML string
        def self.apply_preprocessing(xml_string, preprocessing)
          case preprocessing
          when :normalize
            # Normalize whitespace: collapse runs, trim lines
            xml_string.lines.map(&:strip).reject(&:empty?).join("\n")
          when :c14n
            # Canonicalize the XML
            Canon::Xml::C14n.canonicalize(xml_string, with_comments: false)
          when :format
            # Pretty format the XML
            Canon.format(xml_string, :xml)
          else
            # :none or unrecognized - use as-is
            xml_string
          end
        end

        # Convert from Nokogiri/Moxml node to Canon::Xml::Node
        #
        # @param node [Object] Nokogiri or Moxml node
        # @return [Canon::Xml::Node] Converted node
        def self.convert_from_node(node)
          # Convert to XML string then parse through DataModel
          xml_str = if node.respond_to?(:to_xml)
                      node.to_xml
                    elsif node.respond_to?(:to_s)
                      node.to_s
                    else
                      raise Canon::Error,
                            "Unable to convert node to string: #{node.class}"
                    end
          Canon::Xml::DataModel.from_xml(xml_str)
        end
      end
    end
  end
end
