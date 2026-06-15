# frozen_string_literal: true

module Canon
  class DiffFormatter
    # Helper modules consumed by {DiffDetailFormatter} to format per-dimension
    # difference details. Files live under `diff_detail_formatter/` but the
    # constants live under this namespace.
    #
    # Children are autoloaded — never `require_relative` them.
    module DiffDetailFormatterHelpers
      autoload :ColorHelper,
               "canon/diff_formatter/diff_detail_formatter/color_helper"
      autoload :DimensionFormatter,
               "canon/diff_formatter/diff_detail_formatter/dimension_formatter"
      autoload :LocationExtractor,
               "canon/diff_formatter/diff_detail_formatter/location_extractor"
      autoload :NodeUtils,
               "canon/diff_formatter/diff_detail_formatter/node_utils"
      autoload :TextUtils,
               "canon/diff_formatter/diff_detail_formatter/text_utils"
    end
  end
end
