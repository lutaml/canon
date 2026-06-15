# frozen_string_literal: true

module Canon
  # Semantic tree-diff algorithm — distinct from the DOM positional
  # diff in {Canon::Comparison}.
  #
  # This module computes signature-based tree matches and produces
  # INSERT/DELETE/UPDATE/MOVE operations. Sub-namespaces:
  #
  # * Core — TreeNode, Matching, NodeSignature, NodeWeight,
  #   AttributeComparator, XmlEntityDecoder
  # * Matchers — HashMatcher, SimilarityMatcher, StructuralPropagator,
  #   UniversalMatcher
  # * Operations — Operation, OperationDetector
  # * Adapters — format-specific tree adapters (XML, JSON, HTML, YAML)
  # * OperationConverterHelpers — MetadataEnricher, ReasonBuilder,
  #   PostProcessor, UpdateChangeHandler
  #
  # Top-level entry points: OperationConverter and TreeDiffIntegrator.
  #
  # All children are autoloaded — never `require_relative` them.
  module TreeDiff
    autoload :Adapters, "canon/tree_diff/adapters"
    autoload :Core, "canon/tree_diff/core"
    autoload :Matchers, "canon/tree_diff/matchers"
    autoload :OperationConverter, "canon/tree_diff/operation_converter"
    autoload :OperationConverterHelpers,
             "canon/tree_diff/operation_converter_helpers"
    autoload :Operations, "canon/tree_diff/operations"
    autoload :TreeDiffIntegrator, "canon/tree_diff/tree_diff_integrator"
  end
end
