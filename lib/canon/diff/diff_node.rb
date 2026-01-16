# frozen_string_literal: true

module Canon
  module Diff
    # Represents a semantic difference between two nodes in a comparison tree
    # This is created during the Comparison Layer and carries information about
    # which dimension caused the difference and whether it's normative or informative
    #
    # DiffNode is library-agnostic - it works with data extracted from nodes,
    # not the raw node references themselves. This allows Canon to work with
    # any parsing library (Nokogiri, Moxml, etc.) without being tied to it.
    class DiffNode
      attr_reader :node1, :node2
      attr_accessor :dimension, :reason, :normative, :formatting,
                    # Enriched metadata for Stage 4 rendering
                    :path, # Canonical path with ordinal indices
                    :serialized_before,  # Serialized content for display (before)
                    :serialized_after,   # Serialized content for display (after)
                    :attributes_before,  # Normalized attributes hash (before)
                    :attributes_after    # Normalized attributes hash (after)

      # @param node1 [Object] The first node being compared
      # @param node2 [Object] The second node being compared
      # @param dimension [Symbol] The match dimension that caused this diff
      #   (e.g., :text_content, :attribute_whitespace, :structural_whitespace,
      #   :comments, :key_order)
      # @param reason [String] Human-readable explanation of the difference
      # @param path [String, nil] Optional canonical path with ordinal indices
      # @param serialized_before [String, nil] Optional serialized content for display
      # @param serialized_after [String, nil] Optional serialized content for display
      # @param attributes_before [Hash, nil] Optional normalized attributes hash
      # @param attributes_after [Hash, nil] Optional normalized attributes hash
      def initialize(node1:, node2:, dimension:, reason:,
                     path: nil, serialized_before: nil, serialized_after: nil,
                     attributes_before: nil, attributes_after: nil)
        @node1 = node1
        @node2 = node2
        @dimension = dimension
        @reason = reason
        @normative = nil # Will be set by DiffClassifier
        @formatting = nil # Will be set by DiffClassifier
        # Enriched metadata (optional, populated by PathBuilder and NodeSerializer)
        @path = path
        @serialized_before = serialized_before
        @serialized_after = serialized_after
        @attributes_before = attributes_before
        @attributes_after = attributes_after
      end

      # @return [Boolean] true if this diff is normative (affects equivalence)
      # Formatting-only diffs are never normative
      def normative?
        return false if formatting?

        @normative == true
      end

      # @return [Boolean] true if this diff is informative only (doesn't affect equivalence)
      # Formatting-only diffs are never informative
      def informative?
        return false if formatting?

        @normative == false
      end

      # @return [Boolean] true if this diff is formatting-only (purely cosmetic)
      # Formatting diffs are whitespace/line break differences with no semantic meaning
      def formatting?
        @formatting == true
      end

      def to_h
        {
          node1: node1,
          node2: node2,
          dimension: dimension,
          reason: reason,
          normative: normative,
          formatting: formatting,
          path: path,
          serialized_before: serialized_before,
          serialized_after: serialized_after,
          attributes_before: attributes_before,
          attributes_after: attributes_after,
        }
      end

      def ==(other)
        other.is_a?(DiffNode) &&
          node1 == other.node1 &&
          node2 == other.node2 &&
          dimension == other.dimension &&
          reason == other.reason &&
          normative == other.normative &&
          formatting == other.formatting
        # Note: path and serialized content are not part of equality
        # since they're derived from nodes, not independent properties
      end
    end
  end
end
