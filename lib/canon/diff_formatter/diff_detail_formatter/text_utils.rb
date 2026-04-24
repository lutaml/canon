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
        # Shows spaces as ·, tabs as →, newlines as ¬, and Unicode whitespace
        # like non-breaking space as <NBSP>, etc.
        #
        # @param text [String] Text to visualize
        # @return [String] Text with visible whitespace
        def self.visualize_whitespace(text)
          return "" if text.nil?

          text
            .gsub(" ", "·")
            .gsub("\t", "→")
            .gsub("\n", "¬")
            .gsub("\u00A0", "<NBSP>") # Non-breaking space
            .gsub("\u2028", "<LSEP>")    # Line separator
            .gsub("\u2029", "<PSEP>")    # Paragraph separator
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

        # Escape non-ASCII and non-printable characters for display
        #
        # Converts characters outside the printable ASCII range (32-126) to
        # their \uXXXX escape sequences. This ensures special characters like
        # non-breaking space (\u00A0) and em-dash (\u2014) are visible in
        # terminal output.
        #
        # @param text [String] Text to escape
        # @return [String] Escaped text safe for terminal display
        def self.escape_for_display(text)
          return "" if text.nil?

          text.chars.map do |c|
            codepoint = c.ord
            if codepoint < 32 || codepoint >= 127 || codepoint == 34 || codepoint == 92
              # Escape control characters, non-ASCII, double-quote, and backslash
              "\\u#{codepoint.to_s(16).upcase.rjust(4, '0')}"
            else
              c
            end
          end.join
        end

        # Whether two text values would be visually indistinguishable when
        # rendered through the standard JSON-quoting path.
        #
        # Covers three cases that collapse to near-identical short strings
        # like +""+ / +" "+ / +":"+ / +":"+:
        #   * both sides empty
        #   * both sides whitespace-only (possibly with different whitespace
        #     that JSON.generate preserves verbatim but a reader cannot tell
        #     apart from plain spaces)
        #   * both sides equal (the comparator reported a diff based on
        #     something the text-only extraction does not surface — e.g. a
        #     sibling text node that exists on one side and not the other)
        #
        # Callers should fall back to rendering parent-element context
        # instead.
        #
        # @param text1 [String, nil]
        # @param text2 [String, nil]
        # @return [Boolean]
        def self.ambiguous_text_pair?(text1, text2)
          blank_or_whitespace = ->(t) { t.nil? || t.empty? || t.match?(/\A\s+\z/) }
          return true if blank_or_whitespace.call(text1) &&
            blank_or_whitespace.call(text2)

          text1 == text2
        end

        # Check if text contains non-ASCII or non-printable characters
        #
        # @param text [String] Text to check
        # @return [Boolean] true if text needs escaping for display
        def self.needs_escaping?(text)
          return false if text.nil?

          text.each_char.any? do |c|
            codepoint = c.ord
            codepoint < 32 || codepoint >= 127 || codepoint == 34 || codepoint == 92
          end
        end
      end
    end
  end
end
