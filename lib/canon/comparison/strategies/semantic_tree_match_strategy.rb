# frozen_string_literal: true

require_relative "base_match_strategy"
require_relative "../../tree_diff/tree_diff_integrator"
require_relative "../../tree_diff/operation_converter"

module Canon
  module Comparison
    module Strategies
      # Semantic tree matching strategy
      #
      # Uses TreeDiffIntegrator for intelligent structure-aware matching.
      # This strategy:
      # 1. Converts documents to tree representation
      # 2. Performs semantic matching via TreeDiffIntegrator
      # 3. Converts Operations to DiffNodes via OperationConverter
      # 4. Returns DiffNodes that flow through standard rendering pipeline
      #
      # Key difference from DOM matching: Uses tree-based structural
      # similarity and edit distance for matching instead of simple
      # node-by-node comparison.
      #
      # @example Use semantic tree matching
      #   strategy = SemanticTreeMatchStrategy.new(:xml, match_options)
      #   diff_nodes = strategy.match(doc1, doc2)
      #
      class SemanticTreeMatchStrategy < BaseMatchStrategy
        # Perform semantic tree matching
        #
        # @param doc1 [Object] First document (Nokogiri node, Hash, etc.)
        # @param doc2 [Object] Second document
        # @return [Array<Canon::Diff::DiffNode>] Array of differences
        def match(doc1, doc2)
          # Create integrator with format-specific adapter
          integrator = create_integrator

          # Perform tree diff - returns Operations
          result = integrator.diff(doc1, doc2)

          # Store statistics for metadata
          @statistics = result[:statistics]

          # Convert Operations to DiffNodes using OperationConverter
          # This is the KEY FIX - ensures we use proper DiffNodes
          convert_operations_to_diff_nodes(result[:operations])
        end

        # Preprocess documents for display
        #
        # IMPORTANT: This must use the SAME format as DomMatchStrategy
        # to ensure consistent diff rendering.
        #
        # @param doc1 [Object] First document
        # @param doc2 [Object] Second document
        # @return [Array<String>] Preprocessed [doc1_string, doc2_string]
        def preprocess_for_display(doc1, doc2)
          case @format
          when :xml
            preprocess_xml(doc1, doc2)
          when :html, :html4, :html5
            preprocess_html(doc1, doc2)
          when :json
            preprocess_json(doc1, doc2)
          when :yaml
            preprocess_yaml(doc1, doc2)
          else
            raise ArgumentError, "Unsupported format: #{@format}"
          end
        end

        # Include tree diff statistics in metadata
        #
        # @return [Hash] Metadata including statistics
        def metadata
          {
            tree_diff_statistics: @statistics,
            tree_diff_enabled: true,
          }
        end

        private

        # Create TreeDiffIntegrator with options
        #
        # @return [Canon::TreeDiff::TreeDiffIntegrator] Configured integrator
        def create_integrator
          Canon::TreeDiff::TreeDiffIntegrator.new(
            format: @format,
            options: {
              similarity_threshold: @match_options[:similarity_threshold] || 0.95,
              hash_matching: @match_options.fetch(:hash_matching, true),
              similarity_matching: @match_options.fetch(:similarity_matching,
                                                          true),
              propagation: @match_options.fetch(:propagation, true),
              attribute_order: @match_options[:attribute_order] || :strict,
            },
          )
        end

        # Convert Operations to DiffNodes using OperationConverter
        #
        # This is crucial - it ensures we produce proper DiffNodes with:
        # - Correct dimension mapping
        # - Normative/informative classification
        # - Proper node extraction from TreeNodes
        #
        # @param operations [Array<Operation>] Operations from tree diff
        # @return [Array<Canon::Diff::DiffNode>] Converted DiffNodes
        def convert_operations_to_diff_nodes(operations)
          converter = Canon::TreeDiff::OperationConverter.new(
            format: @format,
            match_options: @match_options,
          )

          converter.convert(operations)
        end

        # Preprocess XML documents
        #
        # Uses simple line break insertion (same as DOM diff)
        # NOT Canon.format() which adds full indentation
        #
        # @param doc1 [Object] First XML document
        # @param doc2 [Object] Second XML document
        # @return [Array<String>] Preprocessed strings
        def preprocess_xml(doc1, doc2)
          # Serialize XML to string
          xml1 = doc1.respond_to?(:to_xml) ? doc1.to_xml : doc1.to_s
          xml2 = doc2.respond_to?(:to_xml) ? doc2.to_xml : doc2.to_s

          # MUST match DOM diff preprocessing EXACTLY (xml_comparator.rb:106-109)
          # Simple pattern: add newline between adjacent tags
          [
            xml1.gsub(/></, ">\n<"),
            xml2.gsub(/></, ">\n<")
          ]
        end

        # Preprocess HTML documents
        #
        # Uses native HTML serialization with line break insertion
        # (same as DOM diff) to ensure proper line-by-line display
        #
        # @param doc1 [Object] First HTML document
        # @param doc2 [Object] Second HTML document
        # @return [Array<String>] Preprocessed strings
        def preprocess_html(doc1, doc2)
          html1 = doc1.respond_to?(:to_html) ? doc1.to_html : doc1.to_s
          html2 = doc2.respond_to?(:to_html) ? doc2.to_html : doc2.to_s

          # KEY FIX: Use simple gsub, NOT Canon.format
          # This ensures proper line-by-line display matching DOM diff format
          [html1.gsub(/></, ">\n<"), html2.gsub(/></, ">\n<")]
        end

        # Preprocess JSON documents
        #
        # Uses Canon formatter for consistent formatting
        #
        # @param doc1 [Object] First JSON document
        # @param doc2 [Object] Second JSON document
        # @return [Array<String>] Preprocessed strings
        def preprocess_json(doc1, doc2)
          require_relative "../../formatters/json_formatter"
          [Canon.format(doc1, :json), Canon.format(doc2, :json)]
        end

        # Preprocess YAML documents
        #
        # Uses Canon formatter for consistent formatting
        #
        # @param doc1 [Object] First YAML document
        # @param doc2 [Object] Second YAML document
        # @return [Array<String>] Preprocessed strings
        def preprocess_yaml(doc1, doc2)
          require_relative "../../formatters/yaml_formatter"
          [Canon.format(doc1, :yaml), Canon.format(doc2, :yaml)]
        end
      end
    end
  end
end
