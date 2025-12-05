# frozen_string_literal: true

module Canon
  # Abstract base class for format-specific data models
  # Provides common interface for parsing and serializing documents
  class DataModel
    class << self
      # Parse input into data model
      # Must be implemented by subclasses
      #
      # @param input [String] Input content to parse
      # @return [Object] Parsed data model representation
      # @raise [NotImplementedError] if not implemented by subclass
      def parse(input)
        raise NotImplementedError, "#{self} must implement #parse"
      end

      # Serialize data model node
      # Must be implemented by subclasses
      #
      # @param node [Object] Node to serialize
      # @return [String] Serialized representation
      # @raise [NotImplementedError] if not implemented by subclass
      def serialize(node)
        raise NotImplementedError, "#{self} must implement #serialize"
      end
    end
  end
end
