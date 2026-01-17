# frozen_string_literal: true

require "json"
require_relative "match_options"
require_relative "comparison_result"

module Canon
  module Comparison
    # JSON comparison class
    # Handles comparison of JSON objects with various options
    class JsonComparator
      # Default comparison options for JSON
      DEFAULT_OPTS = {
        # Output options
        verbose: false,

        # Match system options
        match_profile: nil,
        match: nil,
        preprocessing: nil,
        global_profile: nil,
        global_options: nil,

        # Diff display options
        diff: nil,
      }.freeze

      class << self
        # Compare two JSON objects for equivalence
        #
        # @param json1 [String, Hash, Array] First JSON
        # @param json2 [String, Hash, Array] Second JSON
        # @param opts [Hash] Comparison options
        # @return [Boolean, ComparisonResult] true if equivalent, or ComparisonResult if verbose
        def equivalent?(json1, json2, opts = {})
          opts = DEFAULT_OPTS.merge(opts)

          # Resolve match options with format-specific defaults
          match_opts_hash = MatchOptions::Json.resolve(
            format: :json,
            match_profile: opts[:match_profile],
            match: opts[:match],
            preprocessing: opts[:preprocessing],
            global_profile: opts[:global_profile],
            global_options: opts[:global_options],
          )

          # Wrap in ResolvedMatchOptions for consistency with XML/HTML
          Canon::Comparison::ResolvedMatchOptions.new(
            match_opts_hash,
            format: :json,
          )

          # Store resolved match options for use in comparison logic
          opts[:match_opts] = match_opts_hash

          # Parse JSON if strings
          obj1 = parse_json(json1)
          obj2 = parse_json(json2)

          differences = []
          result = compare_ruby_objects(obj1, obj2, opts, differences, "")

          if opts[:verbose]
            # Format JSON for display
            json_str1 = obj1.is_a?(String) ? obj1 : JSON.pretty_generate(obj1)
            json_str2 = obj2.is_a?(String) ? obj2 : JSON.pretty_generate(obj2)

            ComparisonResult.new(
              differences: differences,
              preprocessed_strings: [json_str1, json_str2],
              format: :json,
              match_options: match_opts_hash,
            )
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

          # Sort keys if order should be ignored (based on match options)
          match_opts = opts[:match_opts]
          if match_opts[:key_order] != :strict
            keys1 = keys1.sort_by(&:to_s)
            keys2 = keys2.sort_by(&:to_s)
          elsif keys1 != keys2
            # Strict mode: key order matters
            # Check if keys are in same order
            # Keys are different or in different order
            # First check if it's just ordering (same keys, different order)
            if keys1.sort_by(&:to_s) == keys2.sort_by(&:to_s)
              # Same keys, different order - this is a key_order difference
              key_path = path.empty? ? "(key order)" : "#{path}.(key order)"
              add_ruby_difference(key_path, keys1, keys2,
                                  Comparison::UNEQUAL_HASH_KEY_ORDER, opts, differences)
              return Comparison::UNEQUAL_HASH_KEY_ORDER
            end
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
