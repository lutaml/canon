# frozen_string_literal: true

module Canon
  module Diff
    # Classifies DiffNodes as normative (affects equivalence) or informative (doesn't affect equivalence)
    # based on the match options in effect
    class DiffClassifier
      attr_reader :match_options

      # @param match_options [Canon::Comparison::ResolvedMatchOptions] The match options
      def initialize(match_options)
        @match_options = match_options
      end

      # Classify a single DiffNode as normative or informative
      # @param diff_node [DiffNode] The diff node to classify
      # @return [DiffNode] The same diff node with normative attribute set
      def classify(diff_node)
        diff_node.normative = normative_for_dimension?(diff_node.dimension)
        diff_node
      end

      # Classify multiple DiffNodes
      # @param diff_nodes [Array<DiffNode>] The diff nodes to classify
      # @return [Array<DiffNode>] The same diff nodes with normative attributes set
      def classify_all(diff_nodes)
        diff_nodes.each { |node| classify(node) }
      end

      private

      # Determine if a difference in a given dimension is normative
      # @param dimension [Symbol] The match dimension
      # @return [Boolean] true if differences in this dimension are normative
      def normative_for_dimension?(dimension)
        behavior = match_options.behavior_for(dimension)

        # :ignore → informative (difference doesn't matter)
        # :strict or :normalize → normative (difference persisted through matching)
        # Note: If a DiffNode exists, it means the comparison FAILED even after
        # applying normalization, so it's a real (normative) difference
        behavior != :ignore
      end
    end
  end
end
