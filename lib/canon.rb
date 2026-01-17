# frozen_string_literal: true

require_relative "canon/version"
require_relative "canon/errors"
require_relative "canon/config"
require_relative "canon/data_model"
require_relative "canon/html"
require_relative "canon/formatters/xml_formatter"
require_relative "canon/formatters/yaml_formatter"
require_relative "canon/formatters/json_formatter"
require_relative "canon/formatters/html_formatter"
require_relative "canon/formatters/html4_formatter"
require_relative "canon/formatters/html5_formatter"
require_relative "canon/comparison"

# New comparison class hierarchy
require_relative "canon/comparison/comparers/markup_comparer"
require_relative "canon/comparison/comparers/xml_comparer"
require_relative "canon/comparison/comparers/html_comparer"
require_relative "canon/comparison/comparers/structure_comparer"
require_relative "canon/comparison/comparers/json_comparer"
require_relative "canon/comparison/comparers/yaml_comparer"

require_relative "canon/rspec_matchers" if defined?(::RSpec)

module Canon
  SUPPORTED_FORMATS = %i[xml yaml json html html4 html5 string].freeze

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

  # rubocop:disable Metrics/MethodLength
  def self.get_formatter(format)
    case format.to_sym
    when :xml
      Formatters::XmlFormatter
    when :yaml
      Formatters::YamlFormatter
    when :json
      Formatters::JsonFormatter
    when :html
      Formatters::HtmlFormatter
    when :html4
      Formatters::Html4Formatter
    when :html5
      Formatters::Html5Formatter
    else
      raise Error, "Unsupported format: #{format}"
    end
  end
  # rubocop:enable Metrics/MethodLength

  # Define shorthand methods for each supported format
  # Creates parse_{format} and format_{format} methods
  SUPPORTED_FORMATS.each do |format|
    define_singleton_method("parse_#{format}") do |content|
      parse(content, format)
    end

    define_singleton_method("format_#{format}") do |content|
      format(content, format)
    end
  end
end
