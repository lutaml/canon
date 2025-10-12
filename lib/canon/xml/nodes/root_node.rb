# frozen_string_literal: true

require_relative "../node"

module Canon
  module Xml
    module Nodes
      # Root node representing the document root
      class RootNode < Node
        def initialize
          super
        end

        def node_type
          :root
        end
      end
    end
  end
end
