# frozen_string_literal: true

module Canon
  module TreeDiff
    # Tree diff module for semantic object tree diffing
  end
end

# Load core components
require_relative "tree_diff/core/tree_node"
require_relative "tree_diff/core/node_signature"
require_relative "tree_diff/core/node_weight"
require_relative "tree_diff/core/matching"

# Load matchers
require_relative "tree_diff/matchers/hash_matcher"
require_relative "tree_diff/matchers/similarity_matcher"
require_relative "tree_diff/matchers/structural_propagator"
require_relative "tree_diff/matchers/universal_matcher"

# Load operations
require_relative "tree_diff/operations/operation"
require_relative "tree_diff/operations/operation_detector"
require_relative "tree_diff/operation_converter"

# Load adapters
require_relative "tree_diff/adapters/xml_adapter"
require_relative "tree_diff/adapters/json_adapter"
require_relative "tree_diff/adapters/html_adapter"
require_relative "tree_diff/adapters/yaml_adapter"

# Load integrator
require_relative "tree_diff/tree_diff_integrator"
