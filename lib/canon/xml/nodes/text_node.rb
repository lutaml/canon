# frozen_string_literal: true

require_relative "../node"

module Canon
  module Xml
    module Nodes
      # Text node in the XPath data model
      class TextNode < Node
        attr_reader :value

        def initialize(value:)
          super()
          @value = value
        end

        def node_type
          :text
        end
      end
    end
  end
end
