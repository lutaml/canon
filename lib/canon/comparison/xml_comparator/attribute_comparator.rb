# frozen_string_literal: true

module Canon
  module Comparison
    module XmlComparatorHelpers
      # Attribute comparison logic
      # Handles comparison of attribute sets with filtering and ordering
      class AttributeComparator
        # Compare attribute sets between two nodes
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param opts [Hash] Comparison options
        # @param differences [Array] Array to append differences to
        # @return [Symbol] Comparison result
        def self.compare(node1, node2, opts, differences)
          # Get attributes using the appropriate method for each node type
          raw_attrs1 = node1.respond_to?(:attribute_nodes) ? node1.attribute_nodes : node1.attributes
          raw_attrs2 = node2.respond_to?(:attribute_nodes) ? node2.attribute_nodes : node2.attributes

          attrs1 = XmlComparatorHelpers::AttributeFilter.filter(raw_attrs1, opts)
          attrs2 = XmlComparatorHelpers::AttributeFilter.filter(raw_attrs2, opts)

          match_opts = opts[:match_opts]
          attribute_order_behavior = match_opts[:attribute_order] || :strict

          # Check attribute order if not ignored
          keys1 = attrs1.keys.map(&:to_s)
          keys2 = attrs2.keys.map(&:to_s)

          if attribute_order_behavior == :strict
            compare_strict_order(node1, node2, attrs1, attrs2, keys1, keys2, opts,
                                 differences)
          else
            compare_flexible_order(node1, node2, attrs1, attrs2, keys1, keys2, opts,
                                   differences)
          end
        end

        # Compare with strict attribute ordering
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param attrs1 [Hash] First node's attributes
        # @param attrs2 [Hash] Second node's attributes
        # @param keys1 [Array<String>] First node's attribute keys
        # @param keys2 [Array<String>] Second node's attribute keys
        # @param opts [Hash] Comparison options
        # @param differences [Array] Array to append differences to
        # @return [Symbol] Comparison result
        def self.compare_strict_order(node1, node2, attrs1, attrs2, keys1, keys2, opts,
differences)
          if keys1 != keys2
            # Keys are different or in different order
            if keys1.sort == keys2.sort
              # Same keys, different order - attribute_order difference
              add_attribute_difference(n1: node1, n2: node2,
                                       diff1: Comparison::UNEQUAL_ATTRIBUTES,
                                       diff2: Comparison::UNEQUAL_ATTRIBUTES,
                                       dimension: :attribute_order,
                                       opts: opts,
                                       differences: differences)
              return Comparison::UNEQUAL_ATTRIBUTES
            else
              # Different keys - attribute_presence difference
              add_attribute_difference(n1: node1, n2: node2,
                                       diff1: Comparison::MISSING_ATTRIBUTE,
                                       diff2: Comparison::MISSING_ATTRIBUTE,
                                       dimension: :attribute_presence,
                                       opts: opts,
                                       differences: differences)
              return Comparison::MISSING_ATTRIBUTE
            end
          end

          # Order matches, check values
          compare_attribute_values(node1, node2, attrs1, attrs2, opts, differences)
        end

        # Compare with flexible attribute ordering
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param attrs1 [Hash] First node's attributes
        # @param attrs2 [Hash] Second node's attributes
        # @param keys1 [Array<String>] First node's attribute keys
        # @param keys2 [Array<String>] Second node's attribute keys
        # @param opts [Hash] Comparison options
        # @param differences [Array] Array to append differences to
        # @return [Symbol] Comparison result
        def self.compare_flexible_order(node1, node2, attrs1, attrs2, keys1, keys2, opts,
differences)
          # Check if order differs (but keys are the same) - track as informative
          if keys1 != keys2 && keys1.sort == keys2.sort && opts[:verbose]
            add_attribute_difference(n1: node1, n2: node2,
                                     diff1: Comparison::UNEQUAL_ATTRIBUTES,
                                     diff2: Comparison::UNEQUAL_ATTRIBUTES,
                                     dimension: :attribute_order,
                                     opts: opts,
                                     differences: differences)
          end

          # Sort attributes so order doesn't matter for comparison
          attrs1 = attrs1.sort_by { |k, _v| k.to_s }.to_h
          attrs2 = attrs2.sort_by { |k, _v| k.to_s }.to_h

          unless attrs1.keys.map(&:to_s).sort == attrs2.keys.map(&:to_s).sort
            add_attribute_difference(n1: node1, n2: node2,
                                     diff1: Comparison::MISSING_ATTRIBUTE,
                                     diff2: Comparison::MISSING_ATTRIBUTE,
                                     dimension: :attribute_presence,
                                     opts: opts,
                                     differences: differences)
            return Comparison::MISSING_ATTRIBUTE
          end

          compare_attribute_values(node1, node2, attrs1, attrs2, opts, differences)
        end

        # Compare attribute values
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param attrs1 [Hash] First node's attributes
        # @param attrs2 [Hash] Second node's attributes
        # @param opts [Hash] Comparison options
        # @param differences [Array] Array to append differences to
        # @return [Symbol] Comparison result
        def self.compare_attribute_values(node1, node2, attrs1, attrs2, opts, differences)
          attrs1.each do |name, value|
            unless attrs2[name] == value
              add_attribute_difference(n1: node1, n2: node2,
                                       diff1: Comparison::UNEQUAL_ATTRIBUTES,
                                       diff2: Comparison::UNEQUAL_ATTRIBUTES,
                                       dimension: :attribute_values,
                                       opts: opts,
                                       differences: differences)
              return Comparison::UNEQUAL_ATTRIBUTES
            end
          end

          Comparison::EQUIVALENT
        end

        # Add an attribute difference
        #
        # @param n1 [Object] First node
        # @param n2 [Object] Second node
        # @param diff1 [String] Difference type for node1
        # @param diff2 [String] Difference type for node2
        # @param dimension [Symbol] The match dimension
        # @param opts [Hash] Options
        # @param differences [Array] Array to append difference to
        def self.add_attribute_difference(n1:, n2:, diff1:, diff2:,
dimension:, differences:, **opts)
          # Import DiffNodeBuilder to avoid circular dependency
          require_relative "diff_node_builder"

          diff_node = Canon::Comparison::DiffNodeBuilder.build(
            node1: n1,
            node2: n2,
            diff1: diff1,
            diff2: diff2,
            dimension: dimension,
            **opts,
          )
          differences << diff_node if diff_node
        end
      end
    end
  end
end
