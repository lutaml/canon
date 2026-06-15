# frozen_string_literal: true

module Canon
  module TreeDiff
    # Core tree-diff primitives: TreeNode, matching, signatures, weights,
    # attribute comparison, and XML entity decoding. Children are
    # autoloaded — never `require_relative` them.
    module Core
      autoload :AttributeComparator, "canon/tree_diff/core/attribute_comparator"
      autoload :Matching, "canon/tree_diff/core/matching"
      autoload :NodeSignature, "canon/tree_diff/core/node_signature"
      autoload :NodeWeight, "canon/tree_diff/core/node_weight"
      autoload :TreeNode, "canon/tree_diff/core/tree_node"
      autoload :XmlEntityDecoder, "canon/tree_diff/core/xml_entity_decoder"
    end
  end
end
