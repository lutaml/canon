# frozen_string_literal: true

module Canon
  module Xml
    # Character encoder for C14N 1.1
    # Handles UTF-8 encoding and character reference encoding per spec
    class CharacterEncoder
      # Most text and attribute values contain nothing to escape —
      # the zero-allocation guard keeps those from paying the gsub
      # copy on every render.
      TEXT_ESCAPABLE = /[&<>\r]/
      ATTRIBUTE_ESCAPABLE = /[&<"\t\n\r]/

      # Encode text node content
      # Replace: & → &amp;, < → &lt;, > → &gt;, #xD → &#xD;
      def encode_text(text)
        return text unless text.match?(TEXT_ESCAPABLE)

        text.gsub(TEXT_ESCAPABLE) do |char|
          case char
          when "&" then "&amp;"
          when "<" then "&lt;"
          when ">" then "&gt;"
          when "\r" then "&#xD;"
          end
        end
      end

      # Encode attribute value
      # Replace: & → &amp;, < → &lt;, " → &quot;,
      #          #x9 → &#x9;, #xA → &#xA;, #xD → &#xD;
      def encode_attribute(value)
        return value unless value.match?(ATTRIBUTE_ESCAPABLE)

        value.gsub(ATTRIBUTE_ESCAPABLE) do |char|
          case char
          when "&" then "&amp;"
          when "<" then "&lt;"
          when '"' then "&quot;"
          when "\t" then "&#x9;"
          when "\n" then "&#xA;"
          when "\r" then "&#xD;"
          end
        end
      end
    end
  end
end
