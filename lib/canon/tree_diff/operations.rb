# frozen_string_literal: true

module Canon
  module TreeDiff
    # Tree-diff operations: Operation (INSERT/DELETE/UPDATE/MOVE) and
    # the OperationDetector that emits them.
    module Operations
      autoload :Operation, "canon/tree_diff/operations/operation"
      autoload :OperationDetector,
               "canon/tree_diff/operations/operation_detector"
    end
  end
end
