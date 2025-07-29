# frozen_string_literal: true

require_relative "canon/version"
require_relative "canon/formatters/xml_formatter"
require_relative "canon/formatters/yaml_formatter"
require_relative "canon/formatters/json_formatter"

require_relative "canon/rspec_matchers" if defined?(::RSpec)

module Canon
  # Format content based on the specified format type
  # @param content [String] The content to format
  # @param format [Symbol] The format type (:xml, :yaml, :json)
  # @return [String] The formatted content
  def self.format(content, format = :xml)
    get_formatter(format).format(content)
  end

  # Parse content based on the specified format type
  # @param content [String] The content to parse
  # @param format [Symbol] The format type (:xml, :yaml, :json)
  # @return [Object] The parsed content
  def self.parse(content, format = :xml)
    get_formatter(format).parse(content)
  end

  def self.get_formatter(format)
    case format.to_sym
    when :xml
      Formatters::XmlFormatter
    when :yaml
      Formatters::YamlFormatter
    when :json
      Formatters::JsonFormatter
    else
      raise Error, "Unsupported format: #{format}"
    end
  end

  class Error < StandardError; end
end
