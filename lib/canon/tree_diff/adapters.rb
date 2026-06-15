# frozen_string_literal: true

module Canon
  module TreeDiff
    # Format-specific tree adapters that wrap parsed documents into
    # Canon::TreeDiff::Core::TreeNode trees for the matcher.
    module Adapters
      autoload :HTMLAdapter, "canon/tree_diff/adapters/html_adapter"
      autoload :JSONAdapter, "canon/tree_diff/adapters/json_adapter"
      autoload :XMLAdapter, "canon/tree_diff/adapters/xml_adapter"
      autoload :YAMLAdapter, "canon/tree_diff/adapters/yaml_adapter"
    end
  end
end
