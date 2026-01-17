# frozen_string_literal: true

require_relative "base_dimension"
require_relative "../match_options"

module Canon
  module Comparison
    module Dimensions
      # Structural whitespace dimension
      #
      # Handles comparison of structural whitespace (whitespace between elements).
      # Supports :strict, :normalize, and :ignore behaviors.
      #
      # Behaviors:
      # - :strict - Exact whitespace comparison
      # - :normalize - Collapse whitespace and compare
      # - :ignore - Skip structural whitespace comparison
      class StructuralWhitespaceDimension < BaseDimension
        # Extract structural whitespace from a node
        #
        # Returns whitespace text nodes that are between elements (structural).
        #
        # @param node [Moxml::Node, Nokogiri::XML::Node] Node to extract from
        # @return [Array<String>] Array of structural whitespace strings
        def extract_data(node)
          return [] unless node

          # Handle Moxml nodes
          if node.is_a?(Moxml::Node)
            extract_from_moxml(node)
          # Handle Nokogiri nodes
          elsif node.is_a?(Nokogiri::XML::Node)
            extract_from_nokogiri(node)
          else
            []
          end
        end

        # Strict structural whitespace comparison
        #
        # @param ws1 [Array<String>] First whitespace array
        # @param ws2 [Array<String>] Second whitespace array
        # @return [Boolean] true if structural whitespace is exactly equal
        def compare_strict(ws1, ws2)
          ws1 == ws2
        end

        # Normalized structural whitespace comparison
        #
        # Collapses whitespace in each entry and compares.
        #
        # @param ws1 [Array<String>] First whitespace array
        # @param ws2 [Array<String>] Second whitespace array
        # @return [Boolean] true if normalized structural whitespace is equal
        def compare_normalize(ws1, ws2)
          normalize_whitespace(ws1) == normalize_whitespace(ws2)
        end

        private

        # Extract structural whitespace from Moxml node
        #
        # @param node [Moxml::Node] Moxml node
        # @return [Array<String>] Array of structural whitespace strings
        def extract_from_moxml(node)
          whitespace = []

          node.children.each do |child|
            if child.node_type == :text
              text = child.content.strip
              # Check if this is purely whitespace (structural)
              if text.empty? || child.content =~ /\A\s*\z/
                whitespace << child.content
              end
            end
          end

          whitespace
        end

        # Extract structural whitespace from Nokogiri node
        #
        # @param node [Nokogiri::XML::Node] Nokogiri node
        # @return [Array<String>] Array of structural whitespace strings
        def extract_from_nokogiri(node)
          whitespace = []

          node.children.each do |child|
            if child.node_type == Nokogiri::XML::Node::TEXT_NODE
              text = child.content.strip
              # Check if this is purely whitespace (structural)
              if text.empty? || child.content =~ /\A\s*\z/
                whitespace << child.content
              end
            end
          end

          whitespace
        end

        # Normalize whitespace array
        #
        # @param whitespace [Array<String>] Whitespace strings
        # @return [Array<String>] Normalized whitespace strings
        def normalize_whitespace(whitespace)
          whitespace.map { |ws| normalize_text(ws) }
        end

        # Normalize text
        #
        # @param text [String, nil] Text to normalize
        # @return [String] Normalized text
        def normalize_text(text)
          MatchOptions.normalize_text(text)
        end
      end
    end
  end
end
