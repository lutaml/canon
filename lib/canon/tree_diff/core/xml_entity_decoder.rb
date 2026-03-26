# frozen_string_literal: true

module Canon
  module TreeDiff
    module Core
      # Decodes XML entity references to Unicode characters.
      #
      # Handles:
      # - Named entities: &amp; &lt; &gt; &quot; &apos;
      # - Decimal numeric entities: &#digits;
      # - Hexadecimal numeric entities: &#xH+;
      module XmlEntityDecoder
        ENTITY_PATTERN = /&(?:amp|lt|gt|quot|apos|#[0-9]+|#[xX][0-9a-fA-F]+);/

        module_function

        def decode_xml_entities(text)
          return text if text.nil? || text.empty?
          return text unless text.include?("&")

          text.gsub(ENTITY_PATTERN) { |match| decode_entity(match) }
        end

        def decode_entity(entity)
          inner = entity[1..-2]

          case inner
          when "amp" then "&"
          when "lt" then "<"
          when "gt" then ">"
          when "quot" then '"'
          when "apos" then "'"
          when /\A#([0-9]+)\z/
            decode_codepoint(Regexp.last_match(1).to_i)
          when /\A#x([0-9a-fA-F]+)\z/, /\A#X([0-9a-fA-F]+)\z/
            decode_codepoint(Regexp.last_match(1).to_i(16))
          else
            entity
          end
        end

        def decode_codepoint(code_point)
          if code_point.positive? && code_point <= 0x10FFFF
            [code_point].pack("U")
          else
            ""
          end
        end
      end
    end
  end
end
