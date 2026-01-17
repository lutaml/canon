# frozen_string_literal: true

require "paint"

module Canon
  class DiffFormatter
    module DiffDetailFormatterHelpers
      # Color helper for diff formatting
      #
      # Provides consistent colorization for diff output.
      module ColorHelper
        # Colorize text with optional bold formatting
        #
        # @param text [String] Text to colorize
        # @param color [Symbol] Color name
        # @param use_color [Boolean] Whether to use colors
        # @param bold [Boolean] Whether to make text bold
        # @return [String] Colorized text (or plain text if use_color is false)
        def self.colorize(text, color, use_color, bold: false)
          return text unless use_color

          args = [color]
          args << :bold if bold

          Paint[text, *args]
        end
      end
    end
  end
end
