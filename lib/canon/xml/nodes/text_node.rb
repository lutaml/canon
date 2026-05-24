# frozen_string_literal: true

require_relative "../node"

module Canon
  module Xml
    module Nodes
      # Text node in the XPath data model
      #
      # Stores both the decoded text value and the original text (with entity
      # references preserved) to enable accurate round-trip serialization.
      class TextNode < Node
        attr_accessor :value
        attr_reader :original

        def original=(value)
          @original = value
        end

        # @param value [String] Decoded text content (entity references resolved)
        # @param original [String, nil] Original text as it appeared in source XML,
        #   with entity references preserved (e.g., "&#x201C;" instead of '"').
        #   If not provided, defaults to value.
        def initialize(value:, original: nil)
          super()
          @value = value
          @original = original || value
        end

        def name
          "#text"
        end

        def node_type
          :text
        end

        def text_content
          @value
        end
      end
    end
  end
end
