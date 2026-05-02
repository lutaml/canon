# frozen_string_literal: true

require "set"

module Canon
  module PrettyPrinter
    # The 14 HTML5 void elements — those whose start tag may stand alone
    # (with no end tag) and which cannot have any content. Every other
    # element with no children must be written as `<tag></tag>` in HTML;
    # writing `<a/>` is illegal HTML and is parsed as `<a>` (start tag only).
    module HtmlVoidElements
      VOID = Set.new(%w[area base br col embed hr img input link meta param
                        source track wbr]).freeze

      def self.void?(name)
        VOID.include?(name.to_s.downcase)
      end
    end
  end
end
