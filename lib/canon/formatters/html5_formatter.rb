# frozen_string_literal: true

require_relative "html_formatter_base"

module Canon
  module Formatters
    # HTML5 formatter using Nokogiri::HTML5 parser
    class Html5Formatter < HtmlFormatterBase
      # Parse HTML5 document
      # @param html [String] HTML document to parse
      # @return [Nokogiri::HTML5::Document] Parsed HTML5 document
      def self.parse(html)
        Nokogiri::HTML5(html)
      end
    end
  end
end
