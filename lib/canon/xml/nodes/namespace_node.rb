# frozen_string_literal: true

require_relative "../node"

module Canon
  module Xml
    module Nodes
      # Namespace node in the XPath data model
      class NamespaceNode < Node
        attr_reader :prefix, :uri

        def initialize(prefix:, uri:)
          super()
          @prefix = prefix
          @uri = uri
        end

        def node_type
          :namespace
        end

        # Local name is the prefix (empty string for default namespace)
        def local_name
          prefix.to_s
        end

        def default_namespace?
          prefix.nil? || prefix.empty?
        end

        # Check if this is the xml namespace
        def xml_namespace?
          prefix == "xml" && uri == "http://www.w3.org/XML/1998/namespace"
        end
      end
    end
  end
end
