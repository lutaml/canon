# frozen_string_literal: true

require "canon/version"
require "canon/errors"
require "nokogiri" unless RUBY_ENGINE == "opal"
require "canon/xml_backend"
require "canon/xml_parsing"
require "canon/config"
require "canon/data_model"
require "canon/xml"
require "canon/html"
require "canon/formatters"
require "canon/comparison"
require "canon/diff"
require "canon/tree_diff"
require "canon/validators"
require "canon/pretty_printer"
require "canon/options"
require "canon/commands"

require "canon/rspec_matchers" if defined?(RSpec.configure)

module Canon
  autoload :Cache, "canon/cache"
  autoload :Cli, "canon/cli"
  autoload :ColorDetector, "canon/color_detector"
  autoload :DiffFormatter, "canon/diff_formatter"

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
    next if format == :string # comparison-only format, no formatter

    define_singleton_method("parse_#{format}") do |content|
      parse(content, format)
    end

    define_singleton_method("format_#{format}") do |content|
      format(content, format)
    end
  end
end
