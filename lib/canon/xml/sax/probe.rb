# frozen_string_literal: true

module Canon
  module Xml
    module Sax
      # Tree-free scan stand-in for the builder protocol. Records
      # recover errors and accumulates an attribute-name-order
      # signature (element open/close tokens plus each non-xmlns
      # attribute name in document order); content itself is ignored —
      # the digest gate covers it. The verbose lane compares the two
      # sides' signatures to prove the absence of the two
      # digest-invisible report entries: informative attribute-order
      # DiffNodes and the SAX-lane parse-error banner (issue #130).
      class Probe
        attr_reader :signature

        def initialize
          @saw_error = false
          @signature = +""
        end

        def saw_error?
          @saw_error
        end

        def error(_string)
          @saw_error = true
        end

        def warning(_string); end

        def start_element(name, attrs = [])
          @signature << "/" << name << "\0"
          attrs.each do |attr|
            attr_name = attr[0].to_s
            next if attr_name == "xmlns" || attr_name.start_with?("xmlns:")

            @signature << "@" << attr_name << "\0"
          end
        end

        def end_element(_name)
          @signature << "\\"
        end

        def characters(_string); end

        def cdata_block(_string); end

        def comment(_string); end

        def processing_instruction(_name, _content); end
      end
    end
  end
end
