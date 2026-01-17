# frozen_string_literal: true

module Canon
  class DiffFormatter
    module DiffDetailFormatterHelpers
      # Text utility methods for diff formatting
      #
      # Provides helper methods for text manipulation and visualization.
      module TextUtils
        # Truncate text to a maximum length with ellipsis
        #
        # @param text [String] Text to truncate
        # @param max_length [Integer] Maximum length
        # @return [String] Truncated text
        def self.truncate_text(text, max_length)
          return "" if text.nil?

          text.length > max_length ? "#{text[0...max_length]}..." : text
        end

        # Visualize whitespace characters in text
        #
        # Shows spaces as ·, tabs as →, newlines as ¬
        #
        # @param text [String] Text to visualize
        # @return [String] Text with visible whitespace
        def self.visualize_whitespace(text)
          return "" if text.nil?

          text
            .gsub(" ", "·")
            .gsub("\t", "→")
            .gsub("\n", "¬")
        end

        # Extract a content preview from a node
        #
        # @param node [Object] Node to extract from
        # @param max_length [Integer] Maximum length of preview
        # @return [String] Content preview
        def self.extract_content_preview(node, max_length = 50)
          return "" unless node

          text = if node.respond_to?(:text)
                   node.text
                 elsif node.respond_to?(:content)
                   node.content
                 else
                   node.to_s
                 end

          return "" if text.nil? || text.empty?

          # Clean up whitespace
          text = text.strip.gsub(/\s+/, " ")
          truncate_text(text, max_length)
        end
      end
    end
  end
end
