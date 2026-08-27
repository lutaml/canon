# frozen_string_literal: true

require "nokogiri" unless RUBY_ENGINE == "opal"

module Canon
  module Xml
    module Sax
      # Nokogiri SAX driver: the builder's protocol already matches
      # Nokogiri::XML::SAX::Document, so every event is a pass-through.
      class NokogiriDriver < Nokogiri::XML::SAX::Document
        def initialize(builder)
          super()
          @builder = builder
        end

        def parse(xml_string)
          Nokogiri::XML::SAX::Parser.new(self).parse(xml_string)
        end

        def error(string)
          @builder.error(string)
        end

        def warning(string)
          @builder.warning(string)
        end

        def start_element(name, attrs = [])
          @builder.start_element(name, attrs)
        end

        def end_element(name)
          @builder.end_element(name)
        end

        def characters(string)
          @builder.characters(string)
        end

        def cdata_block(string)
          @builder.cdata(string)
        end

        def comment(string)
          @builder.comment(string)
        end

        def processing_instruction(name, content)
          @builder.processing_instruction(name, content)
        end
      end
    end
  end
end
