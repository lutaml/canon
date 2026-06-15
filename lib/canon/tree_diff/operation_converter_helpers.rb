# frozen_string_literal: true

module Canon
  module TreeDiff
    # Helper modules consumed by OperationConverter when converting
    # tree operations into DiffNodes.
    module OperationConverterHelpers
      autoload :MetadataEnricher,
               "canon/tree_diff/operation_converter_helpers/metadata_enricher"
      autoload :PostProcessor,
               "canon/tree_diff/operation_converter_helpers/post_processor"
      autoload :ReasonBuilder,
               "canon/tree_diff/operation_converter_helpers/reason_builder"
      autoload :UpdateChangeHandler,
               "canon/tree_diff/operation_converter_helpers/update_change_handler"
    end
  end
end
