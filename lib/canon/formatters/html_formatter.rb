# frozen_string_literal: true

module Canon
  module Formatters
    # HTML formatter for HTML 4/5 and XHTML — engine-parsed.
    class HtmlFormatter < HtmlFormatterBase
      # Parse HTML into an engine document
      # @param html [String] HTML document to parse
      # @return [Moxml::Document] Parsed document
      def self.parse(html)
        # Validate before parsing
        Canon::Validators::HtmlValidator.validate!(html)

        if xhtml?(html)
          # XHTML is XML — the recover-and-record parse matches the old
          # non-strict Nokogiri::XML behaviour.
          Canon::XmlParsing.moxml_context.parse(html)
        else
          Canon::Html::DataModel.engine_html_parse(html)
        end
      end

      # XHTML input must serialize XML-shaped (self-closed voids) so
      # the canonical output stays well-formed and re-validates.
      def self.format(html)
        if xhtml?(html)
          doc = parse(html)
          canonicalize(doc, serializer: :xml)
        else
          doc = Canon::Html::DataModel.engine_html_parse(html)
          canonicalize(doc, serializer: :html)
        end
      end

      # Check if HTML is XHTML
      def self.xhtml?(html)
        html.include?("XHTML") ||
          html.include?('xmlns="http://www.w3.org/1999/xhtml"') ||
          html.match?(/xmlns:\w+/)
      end

      private_class_method :xhtml?
    end
  end
end
