# frozen_string_literal: true

require_relative "base_dimension"
require_relative "../match_options"

module Canon
  module Comparison
    module Dimensions
      # Attribute values dimension
      #
      # Handles comparison of attribute values.
      # Supports :strict, :strip, :compact, :normalize, and :ignore behaviors.
      #
      # Behaviors:
      # - :strict - Exact attribute value comparison
      # - :strip - Compare with leading/trailing whitespace removed
      # - :compact - Compare with internal whitespace collapsed
      # - :normalize - Compare with whitespace stripped and collapsed
      # - :ignore - Skip attribute value comparison
      class AttributeValuesDimension < BaseDimension
        # Extract attribute values from a node
        #
        # Returns a hash of attribute name to value.
        #
        # @param node [Moxml::Node, Nokogiri::XML::Node] Node to extract from
        # @return [Hash] Attribute name to value mapping
        def extract_data(node)
          return {} unless node

          # Handle Moxml nodes
          if node.is_a?(Moxml::Node)
            extract_from_moxml(node)
          # Handle Nokogiri nodes
          elsif node.is_a?(Nokogiri::XML::Node)
            extract_from_nokogiri(node)
          else
            {}
          end
        end

        # Strict attribute value comparison
        #
        # @param attrs1 [Hash] First attributes hash
        # @param attrs2 [Hash] Second attributes hash
        # @return [Boolean] true if all attribute values are exactly equal
        def compare_strict(attrs1, attrs2)
          # Get all unique attribute names
          all_keys = (attrs1.keys | attrs2.keys)

          all_keys.all? do |key|
            attrs1[key].to_s == attrs2[key].to_s
          end
        end

        # Strip comparison
        #
        # Compare with leading/trailing whitespace removed.
        #
        # @param attrs1 [Hash] First attributes hash
        # @param attrs2 [Hash] Second attributes hash
        # @return [Boolean] true if stripped values are equal
        def compare_strip(attrs1, attrs2)
          all_keys = (attrs1.keys | attrs2.keys)

          all_keys.all? do |key|
            attrs1[key].to_s.strip == attrs2[key].to_s.strip
          end
        end

        # Compact comparison
        #
        # Compare with internal whitespace collapsed.
        #
        # @param attrs1 [Hash] First attributes hash
        # @param attrs2 [Hash] Second attributes hash
        # @return [Boolean] true if compacted values are equal
        def compare_compact(attrs1, attrs2)
          all_keys = (attrs1.keys | attrs2.keys)

          all_keys.all? do |key|
            compact_whitespace(attrs1[key].to_s) == compact_whitespace(attrs2[key].to_s)
          end
        end

        # Normalized comparison
        #
        # Compare with whitespace stripped and collapsed.
        #
        # @param attrs1 [Hash] First attributes hash
        # @param attrs2 [Hash] Second attributes hash
        # @return [Boolean] true if normalized values are equal
        def compare_normalize(attrs1, attrs2)
          all_keys = (attrs1.keys | attrs2.keys)

          all_keys.all? do |key|
            normalize_text(attrs1[key].to_s) == normalize_text(attrs2[key].to_s)
          end
        end

        # Compare with custom behavior
        #
        # Supports the extended behaviors for attribute values.
        #
        # @param data1 [Object] First data
        # @param data2 [Object] Second data
        # @param behavior [Symbol] Comparison behavior
        # @return [Boolean] true if data matches according to behavior
        def compare(data1, data2, behavior)
          case behavior
          when :strip
            compare_strip(data1, data2)
          when :compact
            compare_compact(data1, data2)
          else
            super
          end
        end

        private

        # Extract attributes from Moxml node
        #
        # @param node [Moxml::Node] Moxml node
        # @return [Hash] Attribute name to value mapping
        def extract_from_moxml(node)
          return {} unless node.node_type == :element

          attrs = {}
          node.attributes.each do |attr|
            attrs[attr.name] = attr.value
          end
          attrs
        end

        # Extract attributes from Nokogiri node
        #
        # @param node [Nokogiri::XML::Node] Nokogiri node
        # @return [Hash] Attribute name to value mapping
        def extract_from_nokogiri(node)
          return {} unless node.node_type == Nokogiri::XML::Node::ELEMENT_NODE

          attrs = {}
          node.attribute_nodes.each do |attr|
            attrs[attr.name] = attr.value
          end
          attrs
        end

        # Compact whitespace
        #
        # Collapses internal whitespace without trimming.
        #
        # @param text [String] Text to compact
        # @return [String] Compacted text
        def compact_whitespace(text)
          text.gsub(/[\p{Space}\u00a0]+/, " ")
        end

        # Normalize text
        #
        # Collapses and trims whitespace.
        #
        # @param text [String] Text to normalize
        # @return [String] Normalized text
        def normalize_text(text)
          MatchOptions.normalize_text(text)
        end
      end
    end
  end
end
