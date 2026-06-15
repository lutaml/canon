# frozen_string_literal: true

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

        def name
          "comment"
        end

        def node_type
          :comment
        end

        def text_content
          @value
        end
      end
    end
  end
end
