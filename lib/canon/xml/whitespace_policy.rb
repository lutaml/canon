# frozen_string_literal: true

module Canon
  module Xml
    # Parse-time whitespace policy: whether a character-data node
    # survives conversion. One home for the keep/strip rules so the
    # DOM/SAX/HTML differences are visible here instead of implied by
    # copy-paste across conversion sites.
    #
    # Document-level character data (outside the root element) can only
    # be whitespace per the XML grammar, and the XPath data model —
    # which canon's tree and C14N follow — has no root text children at
    # all. Every policy therefore drops whitespace-only document-level
    # text; engines that report it (libxml2 does not, libleptris 1.9.38+
    # does) stay byte-compatible through here.
    module WhitespacePolicy
      # Zero-allocation forms of the `content.strip.empty?` /
      # `content.gsub(...).empty?` checks these policies used to run
      # per text node. STRIP_ONLY is exactly String#strip's set
      # (ASCII whitespace plus null); SAX drops space/tab/CR/LF runs.
      STRIP_ONLY = /\A[\0\t\n\v\f\r ]*\z/
      SAX_DROPPED = /\A[ \t\r\n]*\z/

      module_function

      # DOM conversion rule: whitespace-only text is dropped unless
      # preserving. Non-ASCII whitespace (NBSP, U+3000) survives —
      # String#strip only removes ASCII whitespace.
      #
      # NOTE: CR-only nodes are dropped on this path; the SAX rule keeps
      # them (character references must survive for C14N).
      def keep_dom_text?(content, preserve_whitespace:,
element_parent: true)
        # The XPath data model has no root text children — drop
        # whitespace-only document-level text even when preserving
        # (engines that report it stay byte-compatible with libxml2).
        return false if !element_parent && content.match?(STRIP_ONLY)

        return true if preserve_whitespace

        !content.match?(STRIP_ONLY)
      end

      # SAX rule: same shape, plus CR-bearing content is always kept
      # (&#xD; must survive parsing for C14N) — only runs of pure ASCII
      # whitespace (space, tab, CR, LF) are dropped when not preserving.
      def keep_sax_text?(content, preserve_whitespace:,
element_parent: true)
        return false if !element_parent && content.match?(STRIP_ONLY)

        return true if preserve_whitespace
        return true if content.include?("\r")

        !content.match?(SAX_DROPPED)
      end

      # HTML conversion rule: whitespace-only text is dropped except in
      # whitespace-sensitive elements (pre/code/textarea/script/style),
      # between inline siblings (semantically significant), and when it
      # carries NBSP (U+00A0 — never insignificant; strip is ASCII-only
      # so it is checked explicitly).
      HTML_WHITESPACE_SENSITIVE_TAGS = %w[pre code textarea script style].freeze

      def keep_html_text?(content, parent_name:, text_node: nil)
        return true unless content.match?(STRIP_ONLY)
        return true if content.include?(" ")

        parent_name = parent_name.to_s.downcase
        return true if HTML_WHITESPACE_SENSITIVE_TAGS.include?(parent_name)

        # Computed last: the sibling scan is O(siblings), so it must
        # not run for the content-bearing text nodes that fail the
        # whitespace-only check above.
        return true if text_node &&
          Canon::Comparison::WhitespaceSensitivity.inline_whitespace_significant?(text_node)

        false
      end
    end
  end
end
