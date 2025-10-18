# frozen_string_literal: true

require "json"

module Canon
  module PrettyPrinter
    # Pretty printer for JSON with consistent indentation
    class Json
      def initialize(indent: 2, indent_type: "space")
        @indent = indent.to_i
        @indent_type = indent_type
      end

      # Pretty print JSON with consistent indentation
      def format(json_string)
        obj = JSON.parse(json_string)

        # Determine indent string
        indent_str = @indent_type == "tab" ? "\t" : " " * @indent

        JSON.pretty_generate(obj, indent: indent_str)
      end
    end
  end
end
