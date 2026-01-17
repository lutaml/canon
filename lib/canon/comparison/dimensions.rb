# frozen_string_literal: true

# Comparison dimensions
#
# Provides dimension classes for comparing specific aspects of documents.
# Each dimension knows how to extract and compare data according to different behaviors.
#
# == Architecture
#
# Dimensions represent "WHAT to compare" - specific aspects of a document that can be compared:
# - Text content
# - Comments
# - Attribute values
# - Attribute presence
# - Attribute order
# - Element position
# - Structural whitespace
#
# == Behaviors
#
# Each dimension supports comparison behaviors:
# - :strict - Exact comparison
# - :normalize - Normalized comparison (e.g., collapse whitespace)
# - :ignore - Skip comparison
#
# == Usage
#
#   # Get a dimension instance
#   dimension = Canon::Comparison::Dimensions::Registry.get(:text_content)
#
#   # Compare two nodes
#   dimension.equivalent?(node1, node2, :normalize)
#
#   # Or use the registry directly
#   Canon::Comparison::Dimensions::Registry.compare(:text_content, node1, node2, :normalize)

require_relative "dimensions/base_dimension"
require_relative "dimensions/registry"
require_relative "dimensions/text_content_dimension"
require_relative "dimensions/comments_dimension"
require_relative "dimensions/attribute_values_dimension"
require_relative "dimensions/attribute_presence_dimension"
require_relative "dimensions/attribute_order_dimension"
require_relative "dimensions/element_position_dimension"
require_relative "dimensions/structural_whitespace_dimension"

module Canon
  module Comparison
    module Dimensions
      # Version constant for the dimensions module
      VERSION = "1.0.0"
    end
  end
end
