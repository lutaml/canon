# frozen_string_literal: true

module Canon
  module TreeDiff
    module Core
      # AttributeComparator provides order-independent attribute comparison
      #
      # This class encapsulates the logic for comparing node attributes
      # in a way that respects match options, particularly attribute_order.
      #
      # Key responsibilities:
      # - Compare attributes with configurable order sensitivity
      # - Provide hash-based equality for matching algorithms
      # - Support both strict and normalized comparison modes
      #
      # @example
      #   comparator = AttributeComparator.new(attribute_order: :ignore)
      #   attrs1 = {class: "TOC", id: "_"}
      #   attrs2 = {id: "_", class: "TOC"}
      #   comparator.equal?(attrs1, attrs2) # => true
      #
      class AttributeComparator
        attr_reader :attribute_order

        # Initialize comparator with match options
        #
        # @param attribute_order [Symbol] :strict or :ignore/:normalize
        def initialize(attribute_order: :strict)
          @attribute_order = attribute_order
        end

        # Compare two attribute hashes for equality
        #
        # @param attrs1 [Hash] First attribute hash
        # @param attrs2 [Hash] Second attribute hash
        # @return [Boolean] True if attributes are considered equal
        def equal?(attrs1, attrs2)
          # Handle nil/empty cases
          return true if attrs1.nil? && attrs2.nil?
          return false if attrs1.nil? || attrs2.nil?

          attrs1 = attrs1.to_h if attrs1.respond_to?(:to_h)
          attrs2 = attrs2.to_h if attrs2.respond_to?(:to_h)

          if attribute_order == :strict
            # Strict mode: order matters
            attrs1 == attrs2
          else
            # Ignore/normalize mode: sort keys for comparison
            normalize_for_comparison(attrs1) == normalize_for_comparison(attrs2)
          end
        end

        # Generate a comparison hash for attribute matching
        #
        # This is used by hash-based matchers to ensure nodes with
        # equivalent attributes (according to match options) get the
        # same hash value.
        #
        # @param attrs [Hash] Attribute hash
        # @return [Hash] Normalized hash for comparison
        def comparison_hash(attrs)
          return {} if attrs.nil? || attrs.empty?

          if attribute_order == :strict
            attrs
          else
            normalize_for_comparison(attrs)
          end
        end

        private

        # Normalize attributes for order-independent comparison
        #
        # @param attrs [Hash] Attribute hash
        # @return [Hash] Sorted attribute hash
        def normalize_for_comparison(attrs)
          attrs.sort.to_h
        end
      end
    end
  end
end
