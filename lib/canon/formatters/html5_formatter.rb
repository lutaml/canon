# frozen_string_literal: true

module Canon
  module Formatters
    # HTML5 formatter — parsed through the engine WHATWG lane.
    class Html5Formatter < HtmlFormatterBase
      # Parse HTML5 document
      # @param html [String] HTML document to parse
      # @return [Moxml::Document] Parsed document
      def self.parse(html)
        Canon::Html::DataModel.engine_html_parse(html)
      end
    end
  end
end
