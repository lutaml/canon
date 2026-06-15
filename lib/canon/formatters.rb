# frozen_string_literal: true

module Canon
  # Format-specific canonicalizers and parsers for the top-level
  # `Canon.format` / `Canon.parse` API. Distinct from {DiffFormatter},
  # which renders comparison output.
  module Formatters
    autoload :Html4Formatter, "canon/formatters/html4_formatter"
    autoload :Html5Formatter, "canon/formatters/html5_formatter"
    autoload :HtmlFormatter, "canon/formatters/html_formatter"
    autoload :HtmlFormatterBase, "canon/formatters/html_formatter_base"
    autoload :JsonFormatter, "canon/formatters/json_formatter"
    autoload :XmlFormatter, "canon/formatters/xml_formatter"
    autoload :YamlFormatter, "canon/formatters/yaml_formatter"
  end
end
