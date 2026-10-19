# frozen_string_literal: true

module Canon
  module Formatters
    # HTML4 formatter — parsed through the engine WHATWG lane (the
    # #118 html4/html5 unification: one parse serves both flavors).
    class Html4Formatter < HtmlFormatterBase
      # Parse HTML4 document
      # @param html [String] HTML document to parse
      # @return [Moxml::Document] Parsed document
      def self.parse(html)
        Canon::Html::DataModel.engine_html_parse(html)
      end
    end
  end
end
