# frozen_string_literal: true

require_relative "../node"

module Canon
  module Xml
    module Nodes
      # Attribute node in the XPath data model
      class AttributeNode < Node
        attr_reader :name, :value, :namespace_uri, :prefix

        def initialize(name:, value:, namespace_uri: nil, prefix: nil)
          super()
          @name = name
          @value = value
          @namespace_uri = namespace_uri
          @prefix = prefix
        end

        def node_type
          :attribute
        end

        def local_name
          name
        end

        def qname
          prefix.nil? || prefix.empty? ? name : "#{prefix}:#{name}"
        end

        # Check if this is an xml:* attribute
        def xml_attribute?
          namespace_uri == "http://www.w3.org/XML/1998/namespace"
        end

        # Check if this is a simple inheritable attribute (xml:lang or xml:space)
        def simple_inheritable?
          xml_attribute? && (name == "lang" || name == "space")
        end

        # Check if this is xml:id
        def xml_id?
          xml_attribute? && name == "id"
        end

        # Check if this is xml:base
        def xml_base?
          xml_attribute? && name == "base"
        end
      end
    end
  end
end
