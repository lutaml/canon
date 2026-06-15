# frozen_string_literal: true

module Canon
  # Format-specific validators that raise {Error} on invalid input.
  module Validators
    autoload :BaseValidator, "canon/validators/base_validator"
    autoload :HtmlValidator, "canon/validators/html_validator"
    autoload :JsonValidator, "canon/validators/json_validator"
    autoload :XmlValidator, "canon/validators/xml_validator"
    autoload :YamlValidator, "canon/validators/yaml_validator"
  end
end
