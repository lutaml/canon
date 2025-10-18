# frozen_string_literal: true

require_relative "base_formatter"

module Canon
  class DiffFormatter
    module ByObject
      # JSON tree formatter for by-object diffs
      # Handles Ruby object differences (hashes and arrays)
      class JsonFormatter < BaseFormatter
        # Render a diff node for JSON/Ruby object differences
        #
        # @param key [String] Hash key or array index
        # @param diff [Hash] Difference information
        # @param prefix [String] Tree prefix for indentation
        # @param connector [String] Box-drawing connector character
        # @return [String] Formatted diff node
        def render_diff_node(key, diff, prefix, connector)
          output = []

          # Show full path if available (path in cyan, no color on tree structure)
          path_display = if diff[:path] && !diff[:path].empty?
                           colorize(diff[:path].to_s, :cyan, :bold)
                         else
                           colorize(key.to_s, :cyan)
                         end

          output << "#{prefix}#{connector}#{path_display}:"

          # Determine continuation for nested values
          continuation = connector.start_with?("├") ? "│   " : "    "
          value_prefix = prefix + continuation

          diff_code = diff[:diff_code] || diff[:diff1]

          case diff_code
          when Comparison::MISSING_HASH_KEY
            render_missing_key(diff, value_prefix, output)
          when Comparison::UNEQUAL_PRIMITIVES
            render_unequal_primitives(diff, value_prefix, output)
          when Comparison::UNEQUAL_HASH_VALUES
            render_unequal_hash_values(diff, value_prefix, output)
          when Comparison::UNEQUAL_ARRAY_ELEMENTS
            render_unequal_array_elements(diff, value_prefix, output)
          when Comparison::UNEQUAL_ARRAY_LENGTHS
            render_unequal_array_lengths(diff, value_prefix, output)
          when Comparison::UNEQUAL_TYPES
            render_unequal_types(diff, value_prefix, output)
          else
            # Fallback for unknown diff types
            render_fallback(diff, value_prefix, output)
          end

          output.join("\n")
        end

        private

        # Render missing hash key
        def render_missing_key(diff, prefix, output)
          if diff[:value1].nil?
            # Key added in file2
            if diff[:value2].is_a?(Hash) && !diff[:value2].empty?
              output.concat(render_added_hash(diff[:value2], prefix))
            else
              value_str = format_value_for_diff(diff[:value2])
              output << "#{prefix}└── + #{colorize(value_str, :green)}"
            end
          elsif diff[:value1].is_a?(Hash) && !diff[:value1].empty?
            # Key removed in file2
            output.concat(render_removed_hash(diff[:value1], prefix))
          else
            value_str = format_value_for_diff(diff[:value1])
            output << "#{prefix}└── - #{colorize(value_str, :red)}"
          end
        end

        # Render unequal primitives
        def render_unequal_primitives(diff, prefix, output)
          output.concat(render_value_diff(diff[:value1], diff[:value2],
                                          prefix))
        end

        # Render unequal hash values
        def render_unequal_hash_values(diff, prefix, output)
          output.concat(render_value_diff(diff[:value1], diff[:value2],
                                          prefix))
        end

        # Render unequal array elements
        def render_unequal_array_elements(diff, prefix, output)
          output.concat(render_value_diff(diff[:value1], diff[:value2],
                                          prefix))
        end

        # Render unequal array lengths
        def render_unequal_array_lengths(diff, prefix, output)
          output.concat(render_value_diff(diff[:value1], diff[:value2],
                                          prefix))
        end

        # Render unequal types
        def render_unequal_types(diff, prefix, output)
          output << "#{prefix}├── - #{colorize(
            "#{diff[:value1].class.name}: #{format_value_for_diff(diff[:value1])}",
            :red
          )}"
          output << "#{prefix}└── + #{colorize(
            "#{diff[:value2].class.name}: #{format_value_for_diff(diff[:value2])}",
            :green
          )}"
        end

        # Render fallback for unknown diff types
        def render_fallback(diff, prefix, output)
          if diff[:value1] && diff[:value2]
            output.concat(render_value_diff(diff[:value1], diff[:value2],
                                            prefix))
          elsif diff[:value1]
            value_str = format_value_for_diff(diff[:value1])
            output << "#{prefix}└── - #{colorize(value_str, :red)}"
          elsif diff[:value2]
            value_str = format_value_for_diff(diff[:value2])
            output << "#{prefix}└── + #{colorize(value_str, :green)}"
          else
            output << "#{prefix}└── [UNKNOWN CHANGE]"
          end
        end

        # Render an added hash with nested structure
        def render_added_hash(hash, prefix)
          output = []
          sorted_keys = hash.keys.sort_by(&:to_s)

          sorted_keys.each_with_index do |key, index|
            is_last = (index == sorted_keys.length - 1)
            connector = is_last ? "└──" : "├──"
            continuation = is_last ? "    " : "│   "

            value = hash[key]
            if value.is_a?(Hash) && !value.empty?
              # Nested hash - recurse
              output << "#{prefix}#{connector} + #{colorize(key.to_s, :green)}:"
              output.concat(render_added_hash(value, prefix + continuation))
            else
              # Leaf value
              value_str = format_value_for_diff(value)
              output << "#{prefix}#{connector} + #{colorize(key.to_s, :green)}: #{colorize(value_str, :green)}"
            end
          end

          output
        end

        # Render a removed hash with nested structure
        def render_removed_hash(hash, prefix)
          output = []
          sorted_keys = hash.keys.sort_by(&:to_s)

          sorted_keys.each_with_index do |key, index|
            is_last = (index == sorted_keys.length - 1)
            connector = is_last ? "└──" : "├──"
            continuation = is_last ? "    " : "│   "

            value = hash[key]
            if value.is_a?(Hash) && !value.empty?
              # Nested hash - recurse
              output << "#{prefix}#{connector} - #{colorize(key.to_s, :red)}:"
              output.concat(render_removed_hash(value, prefix + continuation))
            else
              # Leaf value
              value_str = format_value_for_diff(value)
              output << "#{prefix}#{connector} - #{colorize(key.to_s, :red)}: #{colorize(value_str, :red)}"
            end
          end

          output
        end

        # Render a detailed diff for two values
        def render_value_diff(val1, val2, prefix)
          output = []

          # Handle arrays - show element-by-element comparison
          if val1.is_a?(Array) && val2.is_a?(Array)
            output.concat(render_array_diff(val1, val2, prefix))
          elsif val1.is_a?(Hash) && val2.is_a?(Hash)
            # For hashes, show summary (detailed comparison happens recursively)
            val1_str = format_value_for_diff(val1)
            val2_str = format_value_for_diff(val2)
            output << "#{prefix}├── - #{colorize(val1_str, :red)}"
            output << "#{prefix}└── + #{colorize(val2_str, :green)}"
          else
            # Primitives - show actual values
            val1_str = format_value_for_diff(val1)
            val2_str = format_value_for_diff(val2)
            output << "#{prefix}├── - #{colorize(val1_str, :red)}"
            output << "#{prefix}└── + #{colorize(val2_str, :green)}"
          end

          output
        end

        # Render array diff with element-by-element comparison
        def render_array_diff(arr1, arr2, prefix)
          output = []
          max_len = [arr1.length, arr2.length].max
          changes = []

          (0...max_len).each do |i|
            elem1 = i < arr1.length ? arr1[i] : nil
            elem2 = i < arr2.length ? arr2[i] : nil

            if elem1.nil?
              # Element added
              elem_str = format_value_for_diff(elem2)
              changes << { type: :add, index: i, value: elem_str }
            elsif elem2.nil?
              # Element removed
              elem_str = format_value_for_diff(elem1)
              changes << { type: :remove, index: i, value: elem_str }
            elsif elem1 != elem2
              # Element changed
              elem1_str = format_value_for_diff(elem1)
              elem2_str = format_value_for_diff(elem2)
              changes << { type: :change, index: i, old: elem1_str,
                           new: elem2_str }
            end
            # Skip if elements are equal
          end

          # Render changes with proper connectors
          changes.each_with_index do |change, idx|
            is_last = (idx == changes.length - 1)
            connector = is_last ? "└──" : "├──"

            case change[:type]
            when :add
              output << "#{prefix}#{connector} [#{change[:index]}] + #{colorize(change[:value], :green)}"
            when :remove
              output << "#{prefix}#{connector} [#{change[:index]}] - #{colorize(change[:value], :red)}"
            when :change
              output << "#{prefix}├── [#{change[:index]}] - #{colorize(change[:old], :red)}"
              output << if is_last
                          "#{prefix}└── [#{change[:index]}] + #{colorize(change[:new], :green)}"
                        else
                          "#{prefix}├── [#{change[:index]}] + #{colorize(change[:new], :green)}"
                        end
            end
          end

          output
        end

        # Format a value for diff display
        def format_value_for_diff(value)
          case value
          when String
            "\"#{value}\""
          when Numeric, TrueClass, FalseClass
            value.to_s
          when NilClass
            "nil"
          when Array
            if value.empty?
              "[]"
            elsif value.all? do |v|
              v.is_a?(String) || v.is_a?(Numeric) || v.is_a?(TrueClass) || v.is_a?(FalseClass) || v.nil?
            end
              # Simple array - show inline
              "[#{value.map { |v| format_value_for_diff(v) }.join(', ')}]"
            else
              # Complex array - show summary
              "{Array with #{value.length} elements}"
            end
          when Hash
            if value.empty?
              "{}"
            else
              "{Hash with #{value.keys.length} keys: #{value.keys.take(3).map(&:to_s).join(', ')}#{value.keys.length > 3 ? '...' : ''}}"
            end
          else
            value.inspect
          end
        end
      end
    end
  end
end
