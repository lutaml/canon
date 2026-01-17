# frozen_string_literal: true

require_relative "../match_options"

module Canon
  module Comparison
    module XmlComparatorHelpers
      # Attribute filtering logic
      # Handles filtering of attributes based on options and match settings
      class AttributeFilter
        # Filter attributes based on options
        #
        # @param attributes [Array, Hash] Raw attributes
        # @param opts [Hash] Comparison options
        # @return [Hash] Filtered attributes
        def self.filter(attributes, opts)
          filtered = {}
          match_opts = opts[:match_opts]

          # Handle Canon::Xml::Node attribute format (array of AttributeNode)
          if attributes.is_a?(Array)
            filter_array_attributes(attributes, opts, match_opts, filtered)
          else
            # Handle Nokogiri and Moxml attribute formats (Hash-like)
            filter_hash_attributes(attributes, opts, match_opts, filtered)
          end

          filtered
        end

        # Filter array-format attributes (Canon::Xml::Node)
        #
        # @param attributes [Array] Array of AttributeNode objects
        # @param opts [Hash] Comparison options
        # @param match_opts [Hash] Resolved match options
        # @param filtered [Hash] Output hash to populate
        def self.filter_array_attributes(attributes, opts, match_opts, filtered)
          attributes.each do |attr|
            name = attr.name
            value = attr.value

            # Skip namespace declarations - they're handled separately
            next if namespace_declaration?(name)

            # Skip if attribute name should be ignored
            next if ignore_by_name?(name, opts)

            # Skip if attribute content should be ignored
            next if ignore_by_content?(value, opts)

            # Apply match options for attribute values
            behavior = match_opts[:attribute_values] || :strict
            value = MatchOptions.process_attribute_value(value, behavior)

            filtered[name] = value
          end
        end

        # Filter hash-format attributes (Nokogiri/Moxml)
        #
        # @param attributes [Hash] Hash-like attributes
        # @param opts [Hash] Comparison options
        # @param match_opts [Hash] Resolved match options
        # @param filtered [Hash] Output hash to populate
        def self.filter_hash_attributes(attributes, opts, match_opts, filtered)
          attributes.each do |key, val|
            # Normalize key and value
            name, value = normalize_attribute_pair(key, val)

            # Skip namespace declarations - they're handled separately
            next if namespace_declaration?(name)

            # Skip if attribute name should be ignored
            next if ignore_by_name?(name, opts)

            # Skip if attribute content should be ignored
            next if ignore_by_content?(value, opts)

            # Apply match options for attribute values
            behavior = match_opts[:attribute_values] || :strict
            value = MatchOptions.process_attribute_value(value, behavior)

            filtered[name] = value
          end
        end

        # Normalize attribute key-value pair from different formats
        #
        # @param key [Object] Attribute key (String or Attribute object)
        # @param val [Object] Attribute value
        # @return [Array<String, String>] Normalized [name, value] pair
        def self.normalize_attribute_pair(key, val)
          if key.is_a?(String)
            # Nokogiri format: key=name (String), val=attr object
            name = key
            value = val.respond_to?(:value) ? val.value : val.to_s
          else
            # Moxml format: key=attr object, val=nil
            name = key.respond_to?(:name) ? key.name : key.to_s
            value = key.respond_to?(:value) ? key.value : key.to_s
          end

          [name, value]
        end

        # Check if attribute should be ignored by name
        #
        # @param name [String] Attribute name
        # @param opts [Hash] Comparison options
        # @return [Boolean] true if should ignore
        def self.ignore_by_name?(name, opts)
          opts[:ignore_attrs_by_name].any? { |pattern| name.include?(pattern) }
        end

        # Check if attribute should be ignored by content
        #
        # @param value [String] Attribute value
        # @param opts [Hash] Comparison options
        # @return [Boolean] true if should ignore
        def self.ignore_by_content?(value, opts)
          opts[:ignore_attr_content].any? do |pattern|
            value.to_s.include?(pattern)
          end
        end

        # Check if an attribute name is a namespace declaration
        #
        # @param attr_name [String] Attribute name
        # @return [Boolean] true if it's a namespace declaration
        def self.namespace_declaration?(attr_name)
          attr_name == "xmlns" || attr_name.start_with?("xmlns:")
        end
      end
    end
  end
end
