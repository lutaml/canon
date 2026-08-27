# frozen_string_literal: true

module Canon
  module Xml
    module Sax
      # moxml SAX driver (rexml adapter under Opal). moxml splits namespace
      # declarations out of the attribute hash and reports them separately,
      # so this driver recombines them as inline "xmlns"/"xmlns:prefix"
      # pairs to match the builder's engine-neutral protocol.
      class MoxmlDriver < Moxml::SAX::Handler
        def initialize(builder)
          super()
          @builder = builder
        end

        def parse(xml_string)
          Canon::XmlParsing.moxml_context.sax_parse(xml_string, self)
        end

        def on_start_element(name, attributes = {}, namespaces = {})
          attrs = attributes.to_a
          namespaces.each do |prefix, uri|
            attrs << if prefix.nil? || prefix.empty?
                       ["xmlns", uri]
                     else
                       ["xmlns:#{prefix}", uri]
                     end
          end
          @builder.start_element(name, attrs)
        end

        def on_end_element(name)
          @builder.end_element(name)
        end

        def on_characters(text)
          @builder.characters(text)
        end

        def on_cdata(text)
          @builder.cdata(text)
        end

        def on_comment(text)
          @builder.comment(text)
        end

        def on_processing_instruction(name, content)
          @builder.processing_instruction(name, content || "")
        end

        def on_error(error)
          @builder.error(error.message.to_s)
        end
      end
    end
  end
end
