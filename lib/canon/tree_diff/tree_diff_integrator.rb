# frozen_string_literal: true

module Canon
  module TreeDiff
    # TreeDiffIntegrator provides integration between Canon's DOM diff system
    # and the new semantic tree diff system.
    #
    # This class orchestrates:
    # - Format-specific adapter selection
    # - Tree conversion from parsed documents
    # - Tree matching via UniversalMatcher
    # - Operation detection
    # - Results formatting
    #
    # @example XML tree diff
    #   integrator = TreeDiffIntegrator.new(format: :xml)
    #   result = integrator.diff(doc1, doc2)
    #   result[:operations] # => [Operation(...), ...]
    #
    class TreeDiffIntegrator
      attr_reader :format, :adapter, :matcher

      # Initialize integrator for a specific format
      #
      # @param format [Symbol] Format type (:xml, :json, :html, :yaml)
      # @param options [Hash] Configuration options
      # @option options [Float] :similarity_threshold Threshold for similarity matching (default: 0.95)
      # @option options [Boolean] :hash_matching Enable hash matching phase (default: true)
      # @option options [Boolean] :similarity_matching Enable similarity matching phase (default: true)
      # @option options [Boolean] :propagation Enable propagation phase (default: true)
      def initialize(format:, options: {})
        @format = format
        @options = options

        # Initialize format-specific adapter
        @adapter = create_adapter(format)

        # Initialize matcher with options
        matcher_options = {
          similarity_threshold: options[:similarity_threshold] || 0.95,
          hash_matching: options.fetch(:hash_matching, true),
          similarity_matching: options.fetch(:similarity_matching, true),
          propagation: options.fetch(:propagation, true),
          attribute_order: options[:attribute_order] || :strict,
        }
        @matcher = Matchers::UniversalMatcher.new(matcher_options)
      end

      # Perform tree diff on two documents
      #
      # @param doc1 [Object] First document (format-specific)
      # @param doc2 [Object] Second document (format-specific)
      # @return [Hash] Diff results with :operations, :matching, :statistics
      def diff(doc1, doc2)
        # Convert documents to tree nodes
        tree1 = @adapter.to_tree(doc1)
        tree2 = @adapter.to_tree(doc2)

        # Match trees
        matching = @matcher.match(tree1, tree2)

        # Detect operations (create detector per-diff with proper arguments)
        detector = Operations::OperationDetector.new(tree1, tree2, matching)
        operations = detector.detect

        # Return comprehensive results
        {
          operations: operations,
          matching: matching,
          statistics: @matcher.statistics,
          trees: { tree1: tree1, tree2: tree2 },
        }
      end

      # Check if two documents are semantically equivalent
      #
      # @param doc1 [Object] First document
      # @param doc2 [Object] Second document
      # @return [Boolean] true if no operations detected
      def equivalent?(doc1, doc2)
        result = diff(doc1, doc2)
        result[:operations].empty?
      end

      private

      # Create format-specific adapter
      #
      # @param format [Symbol] Format type
      # @return [Object] Adapter instance
      def create_adapter(format)
        case format
        when :xml
          Adapters::XMLAdapter.new
        when :html, :html4, :html5
          Adapters::HTMLAdapter.new
        when :json
          Adapters::JSONAdapter.new
        when :yaml
          Adapters::YAMLAdapter.new
        else
          raise ArgumentError, "Unsupported format: #{format}. " \
                               "Supported formats: :xml, :html, :html4, :html5, :json, :yaml"
        end
      end
    end
  end
end
