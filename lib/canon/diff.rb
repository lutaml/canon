# frozen_string_literal: true

module Canon
  # Diff representation and pipeline construction.
  #
  # This namespace holds the structural artifacts produced by the diff
  # pipeline — DiffNode, DiffLine, DiffBlock, DiffContext, DiffReport —
  # plus the builders that assemble them (DiffNodeMapper, DiffLineBuilder,
  # DiffBlockBuilder, DiffContextBuilder, DiffReportBuilder) and the
  # supporting services (PathBuilder, NodeSerializer, DiffClassifier,
  # FormattingDetector, SourceLocator, TextDecomposer, DiffCharRange,
  # DiffNodeEnricher, XmlSerializationFormatter).
  #
  # All children are autoloaded from this file — never `require_relative`
  # them from sibling files. Reference the constant and let autoload
  # resolve it on first use.
  module Diff
    autoload :DiffBlock, "canon/diff/diff_block"
    autoload :DiffBlockBuilder, "canon/diff/diff_block_builder"
    autoload :DiffCharRange, "canon/diff/diff_char_range"
    autoload :DiffClassifier, "canon/diff/diff_classifier"
    autoload :DiffContext, "canon/diff/diff_context"
    autoload :DiffContextBuilder, "canon/diff/diff_context_builder"
    autoload :DiffLine, "canon/diff/diff_line"
    autoload :DiffLineBuilder, "canon/diff/diff_line_builder"
    autoload :DiffNode, "canon/diff/diff_node"
    autoload :DiffNodeEnricher, "canon/diff/diff_node_enricher"
    autoload :DiffNodeMapper, "canon/diff/diff_node_mapper"
    autoload :DiffReport, "canon/diff/diff_report"
    autoload :DiffReportBuilder, "canon/diff/diff_report_builder"
    autoload :FormattingDetector, "canon/diff/formatting_detector"
    autoload :NodeSerializer, "canon/diff/node_serializer"
    autoload :PathBuilder, "canon/diff/path_builder"
    autoload :SourceLocator, "canon/diff/source_locator"
    autoload :TextDecomposer, "canon/diff/text_decomposer"
    autoload :XmlSerializationFormatter,
             "canon/diff/xml_serialization_formatter"
  end
end
