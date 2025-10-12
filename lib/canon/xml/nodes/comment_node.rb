# frozen_string_literal: true

require_relative "../node"

module Canon
  module Xml
    module Nodes
      # Comment node in the XPath data model
      class CommentNode < Node
        attr_reader :value

        def initialize(value:)
          super()
          @value = value
        end

        def node_type
          :comment
        end
      end
    end
  end
end
