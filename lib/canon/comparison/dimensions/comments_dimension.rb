# frozen_string_literal: true

require_relative "base_dimension"

module Canon
  module Comparison
    module Dimensions
      # Comments dimension
      #
      # Handles comparison of comment nodes.
      # Supports :strict and :ignore behaviors.
      #
      # Behaviors:
      # - :strict - Exact comment comparison including whitespace
      # - :ignore - Skip comment comparison
      class CommentsDimension < BaseDimension
        # Extract comments from a node
        #
        # @param node [Moxml::Node, Nokogiri::XML::Node] Node to extract from
        # @return [Array<String>] Array of comment strings
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

        # Strict comment comparison
        #
        # @param comments1 [Array<String>] First comments array
        # @param comments2 [Array<String>] Second comments array
        # @return [Boolean] true if comments are exactly equal
        def compare_strict(comments1, comments2)
          comments1 == comments2
        end

        # Normalized comment comparison
        #
        # For comments, normalized comparison collapses whitespace in each comment.
        #
        # @param comments1 [Array<String>] First comments array
        # @param comments2 [Array<String>] Second comments array
        # @return [Boolean] true if normalized comments are equal
        def compare_normalize(comments1, comments2)
          normalize_comments(comments1) == normalize_comments(comments2)
        end

        private

        # Extract comments from Moxml node
        #
        # @param node [Moxml::Node] Moxml node
        # @return [Array<String>] Array of comment strings
        def extract_from_moxml(node)
          comments = []

          # If node itself is a comment
          if node.node_type == :comment
            comments << node.content
          end

          # Extract child comments
          node.children.each do |child|
            comments << child.content if child.node_type == :comment
          end

          comments
        end

        # Extract comments from Nokogiri node
        #
        # @param node [Nokogiri::XML::Node] Nokogiri node
        # @return [Array<String>] Array of comment strings
        def extract_from_nokogiri(node)
          comments = []

          # If node itself is a comment
          if node.node_type == Nokogiri::XML::Node::COMMENT_NODE
            comments << node.content
          end

          # Extract child comments
          node.children.each do |child|
            if child.node_type == Nokogiri::XML::Node::COMMENT_NODE
              comments << child.content
            end
          end

          comments
        end

        # Normalize comments by collapsing whitespace
        #
        # @param comments [Array<String>] Comments to normalize
        # @return [Array<String>] Normalized comments
        def normalize_comments(comments)
          comments.map { |c| normalize_text(c) }
        end

        # Normalize text by collapsing whitespace
        #
        # @param text [String, nil] Text to normalize
        # @return [String] Normalized text
        def normalize_text(text)
          return "" if text.nil?

          text.to_s
            .gsub(/[\p{Space}\u00a0]+/, " ")
            .strip
        end
      end
    end
  end
end
