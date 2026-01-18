# frozen_string_literal: true

module Canon
  module Comparison
    # Base class for key-value structure comparison (JSON/YAML)
    #
    # Provides common comparison functionality for formats that represent
    # data as key-value structures (Hash, Array, primitives).
    # Subclasses (JsonComparer, YamlComparer) provide format-specific behavior.
    #
    # @abstract Subclass and override format-specific methods
    class StructureComparer
      class << self
        # Compare two data structures
        #
        # @param data1 [String, Hash, Array] First data structure
        # @param data2 [String, Hash, Array] Second data structure
        # @param opts [Hash] Comparison options
        # @return [Boolean, ComparisonResult] Result of comparison
        def compare(data1, data2, opts = {})
          raise NotImplementedError, "Subclass must implement #compare"
        end

        # Parse a data structure from string or return as-is
        #
        # @param data [String, Hash, Array] Data to parse
        # @return [Hash, Array, Object] Parsed data structure
        def parse_data(data)
          raise NotImplementedError, "Subclass must implement #parse_data"
        end

        # Serialize a data structure to string for display
        #
        # @param data [Hash, Array, Object] Data to serialize
        # @return [String] Serialized data
        def serialize_data(data)
          raise NotImplementedError, "Subclass must implement #serialize_data"
        end

        # Compare two data structures (Hash, Array, primitives)
        #
        # This method handles the high-level comparison logic, delegating
        # to specific comparison methods based on data types.
        #
        # @param obj1 [Object] First object
        # @param obj2 [Object] Second object
        # @param opts [Hash] Comparison options
        # @param differences [Array] Array to append differences to
        # @param path [String] Current path in the object structure
        # @return [Symbol] Comparison result constant
        def compare_structures(obj1, obj2, opts, differences, path)
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

        private

        # Compare two hashes
        #
        # @param hash1 [Hash] First hash
        # @param hash2 [Hash] Second hash
        # @param opts [Hash] Comparison options
        # @param differences [Array] Array to append differences to
        # @param path [String] Current path in the object structure
        # @return [Symbol] Comparison result constant
        def compare_hashes(hash1, hash2, opts, differences, path)
          keys1 = hash1.keys
          keys2 = hash2.keys

          # Sort keys if order should be ignored (based on match options)
          match_opts = opts[:match_opts]
          if match_opts && match_opts[:key_order] != :strict
            keys1 = keys1.sort_by(&:to_s)
            keys2 = keys2.sort_by(&:to_s)
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
            result = compare_structures(hash1[key], hash2[key], opts,
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
        def compare_arrays(arr1, arr2, opts, differences, path)
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
            result = compare_structures(elem1, elem2, opts, differences,
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
        def compare_primitives(val1, val2, opts, differences, path)
          if val1 == val2
            Comparison::EQUIVALENT
          else
            add_difference(path, val1, val2,
                           Comparison::UNEQUAL_PRIMITIVES, opts,
                           differences)
            Comparison::UNEQUAL_PRIMITIVES
          end
        end

        # Add a data structure difference
        #
        # @param path [String] Path to the difference
        # @param obj1 [Object] First object
        # @param obj2 [Object] Second object
        # @param diff_code [Symbol] Difference code
        # @param opts [Hash] Comparison options
        # @param differences [Array] Array to append difference to
        def add_difference(path, obj1, obj2, diff_code, opts, differences)
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
end
