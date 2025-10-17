# frozen_string_literal: true

require "json"

module Canon
  module Comparison
    # JSON comparison class
    # Handles comparison of JSON objects with various options
    class JsonComparator
      # Default comparison options for JSON
      DEFAULT_OPTS = {
        ignore_attr_order: true,
        verbose: false,
      }.freeze

      class << self
        # Compare two JSON objects for equivalence
        #
        # @param json1 [String, Hash, Array] First JSON
        # @param json2 [String, Hash, Array] Second JSON
        # @param opts [Hash] Comparison options
        # @return [Boolean, Array] true if equivalent, or array of diffs if
        #   verbose
        def equivalent?(json1, json2, opts = {})
          opts = DEFAULT_OPTS.merge(opts)

          # Parse JSON if strings
          obj1 = parse_json(json1)
          obj2 = parse_json(json2)

          differences = []
          result = compare_ruby_objects(obj1, obj2, opts, differences, "")

          if opts[:verbose]
            differences
          else
            result == Comparison::EQUIVALENT
          end
        end

        private

        # Parse JSON from string or return as-is
        def parse_json(obj)
          return obj unless obj.is_a?(String)

          JSON.parse(obj)
        end

        # Compare Ruby objects (Hash, Array, primitives) for JSON/YAML
        def compare_ruby_objects(obj1, obj2, opts, differences, path)
          # Check for type mismatch
          unless obj1.instance_of?(obj2.class)
            add_ruby_difference(path, obj1, obj2, Comparison::UNEQUAL_TYPES,
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
              add_ruby_difference(path, obj1, obj2,
                                  Comparison::UNEQUAL_PRIMITIVES, opts,
                                  differences)
              Comparison::UNEQUAL_PRIMITIVES
            end
          end
        end

        # Compare two hashes
        def compare_hashes(hash1, hash2, opts, differences, path)
          keys1 = hash1.keys
          keys2 = hash2.keys

          # Sort keys if order should be ignored
          if opts[:ignore_attr_order]
            keys1 = keys1.sort_by(&:to_s)
            keys2 = keys2.sort_by(&:to_s)
          end

          # Check for missing keys
          missing_in_2 = keys1 - keys2
          missing_in_1 = keys2 - keys1

          missing_in_2.each do |key|
            key_path = path.empty? ? key.to_s : "#{path}.#{key}"
            add_ruby_difference(key_path, hash1[key], nil,
                                Comparison::MISSING_HASH_KEY, opts, differences)
          end

          missing_in_1.each do |key|
            key_path = path.empty? ? key.to_s : "#{path}.#{key}"
            add_ruby_difference(key_path, nil, hash2[key],
                                Comparison::MISSING_HASH_KEY, opts, differences)
          end

          has_missing_keys = !missing_in_1.empty? || !missing_in_2.empty?

          # Compare common keys
          common_keys = keys1 & keys2
          all_equivalent = true
          common_keys.each do |key|
            key_path = path.empty? ? key.to_s : "#{path}.#{key}"
            result = compare_ruby_objects(hash1[key], hash2[key], opts,
                                          differences, key_path)
            all_equivalent = false unless result == Comparison::EQUIVALENT
          end

          # Return appropriate status
          return Comparison::MISSING_HASH_KEY if has_missing_keys && all_equivalent
          return Comparison::UNEQUAL_HASH_VALUES unless all_equivalent

          has_missing_keys ? Comparison::MISSING_HASH_KEY : Comparison::EQUIVALENT
        end

        # Compare two arrays
        def compare_arrays(arr1, arr2, opts, differences, path)
          unless arr1.length == arr2.length
            add_ruby_difference(path, arr1, arr2,
                                Comparison::UNEQUAL_ARRAY_LENGTHS, opts,
                                differences)
            return Comparison::UNEQUAL_ARRAY_LENGTHS
          end

          all_equivalent = true
          arr1.each_with_index do |elem1, index|
            elem2 = arr2[index]
            elem_path = "#{path}[#{index}]"
            result = compare_ruby_objects(elem1, elem2, opts, differences,
                                          elem_path)
            all_equivalent = false unless result == Comparison::EQUIVALENT
          end

          all_equivalent ? Comparison::EQUIVALENT : Comparison::UNEQUAL_ARRAY_ELEMENTS
        end

        # Compare primitive values
        def compare_primitives(val1, val2, opts, differences, path)
          if val1 == val2
            Comparison::EQUIVALENT
          else
            add_ruby_difference(path, val1, val2,
                                Comparison::UNEQUAL_PRIMITIVES, opts,
                                differences)
            Comparison::UNEQUAL_PRIMITIVES
          end
        end

        # Add a Ruby object difference
        def add_ruby_difference(path, obj1, obj2, diff_code, opts, differences)
          return unless opts[:verbose]

          differences << {
            path: path,
            value1: obj1,
            value2: obj2,
            diff_code: diff_code,
          }
        end
      end
    end
  end
end
