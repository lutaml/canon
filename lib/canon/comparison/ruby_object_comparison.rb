# frozen_string_literal: true

module Canon
  module Comparison
    # Ruby Object Comparison Utilities
    #
    # Provides public comparison methods for Ruby objects (Hash, Array, primitives).
    # This module extracts shared comparison logic that was previously
    # accessed via send() from YamlComparator.
    module RubyObjectComparison
      # Compare Ruby objects (Hash, Array, primitives) for JSON/YAML
      #
      # @param obj1 [Object] First object
      # @param obj2 [Object] Second object
      # @param opts [Hash] Comparison options
      # @param differences [Array] Array to append differences to
      # @param path [String] Current path in the object structure
      # @return [Symbol] Comparison result constant
      def self.compare_objects(obj1, obj2, opts, differences, path)
        # Check for type mismatch
        unless obj1.instance_of?(obj2.class)
          add_difference(path, obj1, obj2, Comparison::UNEQUAL_TYPES,
                         opts, differences)
          return Comparison::UNEQUAL_TYPES
        end

        case obj1
        when Hash
          compare_hashes(obj1, obj2, opts, differences, path)
        when Array
          compare_arrays(obj1, obj2, opts, differences, path)
        when NilClass, TrueClass, FalseClass, Numeric, String, Symbol
          compare_primitives(obj1, obj2, opts, differences, path)
        else
          # Fallback to equality comparison
          if obj1 == obj2
            Comparison::EQUIVALENT
          else
            add_difference(path, obj1, obj2,
                           Comparison::UNEQUAL_PRIMITIVES, opts,
                           differences)
            Comparison::UNEQUAL_PRIMITIVES
          end
        end
      end

      # Compare two hashes
      #
      # @param hash1 [Hash] First hash
      # @param hash2 [Hash] Second hash
      # @param opts [Hash] Comparison options
      # @param differences [Array] Array to append differences to
      # @param path [String] Current path in the object structure
      # @return [Symbol] Comparison result constant
      def self.compare_hashes(hash1, hash2, opts, differences, path)
        keys1 = hash1.keys
        keys2 = hash2.keys

        # Sort keys if order should be ignored (based on match options)
        match_opts = opts[:match_opts]
        if match_opts && match_opts[:key_order] != :strict
          keys1 = keys1.sort_by(&:to_s)
          keys2 = keys2.sort_by(&:to_s)
        elsif match_opts && match_opts[:key_order] == :strict
          # Strict mode: key order matters
          # Check if keys are in same order
          # Keys are different or in different order
          # First check if it's just ordering (same keys, different order)
          if (keys1 != keys2) && (keys1.sort_by(&:to_s) == keys2.sort_by(&:to_s))
            # Same keys, different order - this is a key_order difference
            key_path = path.empty? ? "(key order)" : "#{path}.(key order)"
            add_difference(key_path, keys1, keys2,
                           Comparison::UNEQUAL_HASH_KEY_ORDER, opts, differences)
            return Comparison::UNEQUAL_HASH_KEY_ORDER
          end
        end

        # Check for missing keys
        missing_in_second = keys1 - keys2
        missing_in_first = keys2 - keys1

        missing_in_second.each do |key|
          key_path = path.empty? ? key.to_s : "#{path}.#{key}"
          add_difference(key_path, hash1[key], nil,
                         Comparison::MISSING_HASH_KEY, opts, differences)
        end

        missing_in_first.each do |key|
          key_path = path.empty? ? key.to_s : "#{path}.#{key}"
          add_difference(key_path, nil, hash2[key],
                         Comparison::MISSING_HASH_KEY, opts, differences)
        end

        has_missing_keys = !missing_in_first.empty? || !missing_in_second.empty?

        # Compare common keys
        common_keys = keys1 & keys2
        all_equivalent = true
        common_keys.each do |key|
          key_path = path.empty? ? key.to_s : "#{path}.#{key}"
          result = compare_objects(hash1[key], hash2[key], opts,
                                   differences, key_path)
          all_equivalent = false unless result == Comparison::EQUIVALENT
        end

        # Return appropriate status
        return Comparison::MISSING_HASH_KEY if has_missing_keys && all_equivalent
        return Comparison::UNEQUAL_HASH_VALUES unless all_equivalent

        has_missing_keys ? Comparison::MISSING_HASH_KEY : Comparison::EQUIVALENT
      end

      # Compare two arrays
      #
      # @param arr1 [Array] First array
      # @param arr2 [Array] Second array
      # @param opts [Hash] Comparison options
      # @param differences [Array] Array to append differences to
      # @param path [String] Current path in the object structure
      # @return [Symbol] Comparison result constant
      def self.compare_arrays(arr1, arr2, opts, differences, path)
        unless arr1.length == arr2.length
          add_difference(path, arr1, arr2,
                         Comparison::UNEQUAL_ARRAY_LENGTHS, opts,
                         differences)
          return Comparison::UNEQUAL_ARRAY_LENGTHS
        end

        all_equivalent = true
        arr1.each_with_index do |elem1, index|
          elem2 = arr2[index]
          elem_path = "#{path}[#{index}]"
          result = compare_objects(elem1, elem2, opts, differences,
                                   elem_path)
          all_equivalent = false unless result == Comparison::EQUIVALENT
        end

        all_equivalent ? Comparison::EQUIVALENT : Comparison::UNEQUAL_ARRAY_ELEMENTS
      end

      # Compare primitive values
      #
      # @param val1 [Object] First value
      # @param val2 [Object] Second value
      # @param opts [Hash] Comparison options
      # @param differences [Array] Array to append differences to
      # @param path [String] Current path in the object structure
      # @return [Symbol] Comparison result constant
      def self.compare_primitives(val1, val2, opts, differences, path)
        if val1 == val2
          Comparison::EQUIVALENT
        else
          add_difference(path, val1, val2,
                         Comparison::UNEQUAL_PRIMITIVES, opts,
                         differences)
          Comparison::UNEQUAL_PRIMITIVES
        end
      end

      # Add a Ruby object difference
      #
      # @param path [String] Path to the difference
      # @param obj1 [Object] First object
      # @param obj2 [Object] Second object
      # @param diff_code [Symbol] Difference code
      # @param opts [Hash] Comparison options
      # @param differences [Array] Array to append difference to
      def self.add_difference(path, obj1, obj2, diff_code, opts, differences)
        return unless opts[:verbose]

        differences << {
          path: path,
          value1: obj1,
          value2: obj2,
          difference: diff_code,
        }
      end
    end
  end
end
