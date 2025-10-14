# frozen_string_literal: true

require_relative "html_formatter_base"

module Canon
  module Formatters
    # HTML4 formatter using Nokogiri::HTML parser
    class Html4Formatter < HtmlFormatterBase
      # Parse HTML4 document
      # @param html [String] HTML document to parse
      # @return [Nokogiri::HTML::Document] Parsed HTML4 document
      def self.parse(html)
        Nokogiri::HTML(html)
      end
    end
  end
end
