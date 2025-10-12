# frozen_string_literal: true

module Canon
  module Xml
    # Character encoder for C14N 1.1
    # Handles UTF-8 encoding and character reference encoding per spec
    class CharacterEncoder
      # Encode text node content
      # Replace: & → &amp;, < → &lt;, > → &gt;, #xD → &#xD;
      def encode_text(text)
        text.gsub(/[&<>\r]/) do |char|
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
        value.gsub(/[&<"\t\n\r]/) do |char|
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
