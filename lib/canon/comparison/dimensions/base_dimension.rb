# frozen_string_literal: true

module Canon
  module Comparison
    module Dimensions
      # Base class for comparison dimensions
      #
      # A dimension represents "WHAT to compare" - a specific aspect of a document
      # that can be compared (e.g., text content, attributes, comments).
      #
      # Each dimension knows how to:
      # - Extract relevant data from a node
      # - Compare data according to a behavior (:strict, :normalize, :ignore)
      #
      # Subclasses must implement:
      # - extract_data(node) - Extract relevant data from a node
      # - compare_strict(data1, data2) - Strict comparison
      # - compare_normalize(data1, data2) - Normalized comparison (optional)
      #
      # @abstract Subclass and implement abstract methods
      class BaseDimension
        # Behavior constants
        STRICT = :strict
        NORMALIZE = :normalize
        IGNORE = :ignore

        # Get the dimension name
        #
        # @return [Symbol] Dimension name
        def dimension_name
          @dimension_name ||= self.class.name.split("::").last.gsub(
            /Dimension$/, ""
          ).downcase.to_sym
        end

        # Compare extracted data according to behavior
        #
        # @param data1 [Object] First data
        # @param data2 [Object] Second data
        # @param behavior [Symbol] Comparison behavior (:strict, :normalize, :ignore)
        # @return [Boolean] true if data matches according to behavior
        def compare(data1, data2, behavior)
          case behavior
          when STRICT
            compare_strict(data1, data2)
          when NORMALIZE
            compare_normalize(data1, data2)
          when IGNORE
            true
          else
            raise Error, "Unknown behavior: #{behavior}"
          end
        end

        # Check if two nodes are equivalent for this dimension
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param behavior [Symbol] Comparison behavior
        # @return [Boolean] true if nodes match for this dimension
        def equivalent?(node1, node2, behavior)
          data1 = extract_data(node1)
          data2 = extract_data(node2)
          compare(data1, data2, behavior)
        end

        # Extract data from a node
        #
        # @param node [Object] Node to extract data from
        # @return [Object] Extracted data
        # @abstract Subclass must implement
        def extract_data(node)
          raise NotImplementedError, "#{self.class} must implement extract_data"
        end

        # Strict comparison
        #
        # @param data1 [Object] First data
        # @param data2 [Object] Second data
        # @return [Boolean] true if data matches strictly
        # @abstract Subclass must implement
        def compare_strict(data1, data2)
          raise NotImplementedError,
                "#{self.class} must implement compare_strict"
        end

        # Normalized comparison
        #
        # @param data1 [Object] First data
        # @param data2 [Object] Second data
        # @return [Boolean] true if data matches after normalization
        def compare_normalize(data1, data2)
          # Default implementation: delegate to strict comparison
          compare_strict(data1, data2)
        end

        # Check if this dimension supports normalization
        #
        # @return [Boolean] true if normalization is supported
        def supports_normalization?
          # Check if compare_normalize is overridden (not the default implementation)
          method(:compare_normalize).owner != BaseDimension
        end
      end
    end
  end
end
