# frozen_string_literal: true

require_relative "../node"

module Canon
  module Xml
    module Nodes
      # Processing Instruction node in the XPath data model
      class ProcessingInstructionNode < Node
        attr_reader :target, :data

        def initialize(target:, data: "")
          super()
          @target = target
          @data = data
        end

        def node_type
          :processing_instruction
        end

        def node_info
          "data: #{data} target: #{target}"
        end
      end
    end
  end
end
