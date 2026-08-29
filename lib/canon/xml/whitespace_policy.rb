# frozen_string_literal: true

module Canon
  module Xml
    # Parse-time whitespace policy: whether a character-data node
    # survives conversion. One home for the keep/strip rules so the
    # DOM/SAX differences are visible here instead of implied by
    # copy-paste across conversion sites.
    module WhitespacePolicy
      module_function

      # DOM conversion rule: whitespace-only text is dropped unless
      # preserving. Non-ASCII whitespace (NBSP, U+3000) survives —
      # String#strip only removes ASCII whitespace.
      #
      # NOTE: CR-only nodes are dropped on this path; the SAX rule keeps
      # them (character references must survive for C14N).
      def keep_dom_text?(content, preserve_whitespace:, element_parent: true)
        return true if preserve_whitespace
        return true unless element_parent

        !content.strip.empty?
      end

      # SAX rule: same shape, plus CR-bearing content is always kept
      # (&#xD; must survive parsing for C14N) — only runs of pure ASCII
      # whitespace (space, tab, CR, LF) are dropped when not preserving.
      def keep_sax_text?(content, preserve_whitespace:, element_parent: true)
        return true if preserve_whitespace
        return true unless element_parent
        return true if content.include?("\r")

        !content.gsub(/[ \t\r\n]/, "").empty?
      end

      # HTML conversion rule: whitespace-only text is dropped except in
      # whitespace-sensitive elements (pre/code/textarea/script/style),
      # between inline siblings (semantically significant), and when it
      # carries NBSP (U+00A0 — never insignificant; strip is ASCII-only
      # so it is checked explicitly).
      HTML_WHITESPACE_SENSITIVE_TAGS = %w[pre code textarea script style].freeze

      def keep_html_text?(content, parent_name:, inline_significant: false)
        return true unless content.strip.empty?
        return true if content.include?("\u00A0")

        parent_name = parent_name.to_s.downcase
        return true if HTML_WHITESPACE_SENSITIVE_TAGS.include?(parent_name)
        return true if inline_significant

        false
      end
    end
  end
end
