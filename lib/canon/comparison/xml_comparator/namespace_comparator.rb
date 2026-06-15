# frozen_string_literal: true

module Canon
  module Comparison
    module XmlComparatorHelpers
      # Namespace declaration comparison logic
      # Handles comparison of xmlns and xmlns:* attributes
      class NamespaceComparator
        # Compare namespace declarations between two nodes
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param opts [Hash] Comparison options
        # @param differences [Array] Array to append differences to
        # @return [Symbol] Comparison result
        def self.compare(node1, node2, opts, differences)
          ns_decls1 = extract_declarations(node1)
          ns_decls2 = extract_declarations(node2)

          # Find missing, extra, and changed namespace declarations
          missing = ns_decls1.keys - ns_decls2.keys  # In node1 but not node2
          extra = ns_decls2.keys - ns_decls1.keys    # In node2 but not node1
          changed = ns_decls1.select do |prefix, uri|
            ns_decls2[prefix] && ns_decls2[prefix] != uri
          end.keys

          # If there are any differences, create a DiffNode
          if missing.any? || extra.any? || changed.any?
            add_namespace_difference(node1, node2, missing, extra, changed,
                                     opts, differences)
            return Comparison::UNEQUAL_ATTRIBUTES
          end

          Comparison::EQUIVALENT
        end

        # Extract namespace declarations from a node
        #
        # @param node [Object] Node to extract namespace declarations from
        # @return [Hash] Hash of prefix => URI mappings
        def self.extract_declarations(node)
          declarations = {}

          if node.is_a?(Canon::Xml::Node)
            if node.namespace_nodes
              return extract_from_namespace_nodes(node.namespace_nodes,
                                                  declarations)
            end

            raw_attrs = node.attribute_nodes
          else
            raw_attrs = node.attributes
          end

          if raw_attrs.is_a?(Array)
            extract_from_array_attributes(raw_attrs, declarations)
          else
            extract_from_hash_attributes(raw_attrs, declarations)
          end

          declarations
        end

        # Extract from Canon::Xml::Node namespace_nodes
        #
        # @param namespace_nodes [Array] Array of NamespaceNode objects
        # @param declarations [Hash] Output hash to populate
        # @return [Hash] Declarations hash
        def self.extract_from_namespace_nodes(namespace_nodes, declarations)
          namespace_nodes.each do |ns|
            # Skip the implicit xml namespace (always present)
            next if ns.prefix == "xml" && ns.uri == "http://www.w3.org/XML/1998/namespace"

            prefix = ns.prefix || ""
            declarations[prefix] = ns.uri
          end

          declarations
        end

        # Extract from array-format attributes
        #
        # @param raw_attrs [Array] Array of AttributeNode objects
        # @param declarations [Hash] Output hash to populate
        # @return [Hash] Declarations hash
        def self.extract_from_array_attributes(raw_attrs, declarations)
          raw_attrs.each do |attr|
            name = attr.name
            value = attr.value

            if namespace_declaration?(name)
              # Extract prefix: "xmlns" -> "", "xmlns:xmi" -> "xmi"
              prefix = name == "xmlns" ? "" : name.split(":", 2)[1]
              declarations[prefix] = value
            end
          end

          declarations
        end

        # Extract from hash-format attributes
        #
        # @param raw_attrs [Hash] Hash-like attributes
        # @param declarations [Hash] Output hash to populate
        # @return [Hash] Declarations hash
        def self.extract_from_hash_attributes(raw_attrs, declarations)
          raw_attrs.each do |key, val|
            name = key.is_a?(String) ? key : key.name

            if namespace_declaration?(name)
              value = val.is_a?(String) ? val : val.value

              prefix = name == "xmlns" ? "" : name.split(":", 2)[1]
              declarations[prefix] = value
            end
          end

          declarations
        end

        def self.namespace_declaration?(attr_name)
          Canon::Xml::NamespaceHelper.namespace_declaration?(attr_name)
        end

        # Add a namespace declaration difference
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param missing [Array] Missing prefixes
        # @param extra [Array] Extra prefixes
        # @param changed [Array] Changed prefixes
        # @param opts [Hash] Options
        # @param differences [Array] Array to append difference to
        def self.add_namespace_difference(node1, node2, missing, extra,
changed, opts, differences)
          # Build a descriptive reason
          reasons = []
          if missing.any?
            reasons << "removed: #{missing.map do |p|
              p.empty? ? 'xmlns' : "xmlns:#{p}"
            end.join(', ')}"
          end
          if extra.any?
            reasons << "added: #{extra.map do |p|
              p.empty? ? 'xmlns' : "xmlns:#{p}"
            end.join(', ')}"
          end
          if changed.any?
            reasons << "changed: #{changed.map do |p|
              p.empty? ? 'xmlns' : "xmlns:#{p}"
            end.join(', ')}"
          end

          diff_node = Canon::Comparison::DiffNodeBuilder.build(
            node1: node1,
            node2: node2,
            diff1: Comparison::UNEQUAL_ATTRIBUTES,
            diff2: Comparison::UNEQUAL_ATTRIBUTES,
            dimension: :namespace_declarations,
            **opts,
          )
          differences << diff_node if diff_node
        end
      end
    end
  end
end
