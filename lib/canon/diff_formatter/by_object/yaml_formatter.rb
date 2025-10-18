# frozen_string_literal: true

require_relative "json_formatter"

module Canon
  class DiffFormatter
    module ByObject
      # YAML tree formatter for by-object diffs
      # Inherits from JsonFormatter since YAML and JSON share the same
      # Ruby object structure (hashes and arrays)
      class YamlFormatter < JsonFormatter
        # YAML uses the same rendering logic as JSON since both formats
        # represent Ruby objects (hashes and arrays) with the same structure
      end
    end
  end
end
