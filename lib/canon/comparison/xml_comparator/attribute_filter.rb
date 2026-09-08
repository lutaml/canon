# frozen_string_literal: true

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
            # Expanded name (XML Namespaces 1.0 §5.2/§5.3): an
            # unprefixed attribute is in NO namespace — {no-ns}srsName
            # and {uri}srsName are different attributes, and two
            # prefixes bound to the same URI are the same attribute.
            # Local-name keys conflated qualified with unqualified
            # attributes whenever the prefix matched the element's
            # (issue #155).
            name = expanded_attribute_name(attr)
            value = attr.value

            # Skip namespace declarations - they're handled separately
            next if namespace_declaration?(attr.name)

            # Skip if attribute name should be ignored — by local name
            # (user-facing list) or expanded key, so ignore lists keep
            # working against both forms.
            next if ignore_by_name?(attr.name, opts) ||
              ignore_by_name?(name, opts)

            # Skip if attribute content should be ignored
            next if ignore_by_content?(value, opts)

            # Apply match options for attribute values
            behavior = match_opts[:attribute_values] || :strict
            value = MatchOptions.process_attribute_value(value, behavior)

            filtered[name] = value
          end
        end

        # Expanded attribute key: "{namespace-uri}local-name", or the
        # bare local name when the attribute is in no namespace.
        # Prefixed-but-unresolvable attributes (namespace-invalid
        # documents — an undeclared prefix has no expanded name) fall
        # back to the local name: recovery comparison cannot do better.
        def self.expanded_attribute_name(attr)
          case attr
          when Canon::Xml::Nodes::AttributeNode
            uri = attr.namespace_uri
            attr.prefix
          when defined?(Nokogiri) && Nokogiri::XML::Attr
            uri = attr.namespace&.href
            attr.namespace&.prefix
          else
            uri = attr.namespace_uri
            nil
          end
          uri && !uri.empty? ? "{#{uri}}#{attr.name}" : attr.name
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
            name = key
            value = val.is_a?(String) ? val : val.value
          else
            name = key.name
            value = key.value
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

        def self.namespace_declaration?(attr_name)
          Canon::Xml::NamespaceHelper.namespace_declaration?(attr_name)
        end
      end
    end
  end
end
