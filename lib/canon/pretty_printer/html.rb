# frozen_string_literal: true

require "stringio"

module Canon
  module PrettyPrinter
    # Pretty printer for HTML with consistent indentation.
    #
    # Two modes:
    #
    # 1. Default mode (+fixture_ready: false+): retains the existing
    #    behaviour for callers that use the pretty-printer as a
    #    structural normaliser (the canon round-trip tests, the
    #    diff-pipeline +apply_pretty_print+ stage, etc).  These callers
    #    do not require actual indentation; they require structural
    #    equivalence to the input.
    #
    # 2. Fixture-ready mode (+fixture_ready: true+): emits
    #    actually-indented XHTML-shaped output via libxml's +FORMAT+
    #    save flag.  Used by +DiffFormatter#prettyprint_for_display+
    #    (the +CANON_<FORMAT>_DIFF_SHOW_PRETTYPRINT_RECEIVED+ surface)
    #    so the user can read or paste the formatted output directly
    #    into a fixture heredoc.  Output is XHTML-shaped (void
    #    elements self-closed, non-void paired) via the +AS_XHTML+
    #    save flag; the +NO_DECLARATION+ flag suppresses the
    #    +<?xml ...?>+ prefix.
    #
    # See lutaml/canon#133, lutaml/canon#135.
    class Html
      WHITESPACE_PRESERVING_ELEMENTS = %w[pre textarea script style].freeze

      def initialize(indent: 2, indent_type: "space", fixture_ready: false)
        @indent = indent.to_i
        @indent_type = indent_type
        @fixture_ready = fixture_ready
      end

      def format(html_string)
        # The fixture-ready display lane is engine-served end to end
        # (moxml 0.6.2's XHTML serialization mode — moxml#390): no
        # Nokogiri requirement remains in this mode.
        return format_fixture_ready(html_string) if @fixture_ready

        if xhtml?(html_string)
          format_as_xhtml(html_string)
        else
          format_as_html(html_string)
        end
      end

      private

      def xhtml?(html_string)
        html_string.include?("XHTML") ||
          html_string.include?('xmlns="http://www.w3.org/1999/xhtml"')
      end

      # XHTML is XML: the shared XML pretty-printer lane owns it (the
      # leptris serializer under the default engine — Nokogiri serving
      # only the forced-fallback engine), keeping the XML loud/tolerant
      # parse contract and the engine's byte-faithful serializer.
      #
      # This replaces a direct Nokogiri::XML call whose serializer
      # INJECTED a <meta http-equiv="Content-Type"> element into <head>
      # of XHTML PUBLIC-doctype documents at serialization time — a
      # pretty-printer must never invent content. Intentional byte
      # changes vs the Nokogiri lane: the phantom meta is gone;
      # body-level PIs/comments indent like every other child; void
      # elements self-close without a space (<br/>).
      def format_as_xhtml(html_string)
        out = Canon::PrettyPrinter::Xml.new(
          indent: @indent, indent_type: @indent_type,
        ).format(html_string)

        expand_non_void_self_closing(out)
      end

      # Engine serialization with the #354 indent knobs — the engine's
      # own nested layout (a deliberate byte change vs the Nokogiri
      # lane: synthesis shape differs, e.g. no empty <head></head>).
      def format_as_html(html_string)
        doc = Canon::Html::DataModel.engine_html_parse(html_string)
        if @indent_type == "tab"
          doc.to_html(indent: 1, indent_text: "\t")
        else
          doc.to_html(indent: @indent)
        end
      end

      # Fixture-ready serialisation, engine-served end to end:
      # engine HTML parse + significance-aware strip + moxml 0.6.2's
      # XHTML serialization mode (moxml#390 delivered to_xhtml /
      # to_html(xhtml: true)): void elements self-closed, non-void
      # paired — the AS_XHTML contract, engine-served.
      def format_fixture_ready(html_string)
        doc = Canon::Html::DataModel.engine_html_parse(html_string)
        Canon::Html::DataModel.strip_insignificant_whitespace!(doc.root)
        html = if @indent_type == "tab"
                 doc.to_xhtml(indent: 1, indent_text: "\t")
               else
                 doc.to_xhtml(indent: @indent)
               end
        # The AS_XHTML contract pairs empty NON-void elements (<a .../>)
        # for browser-safe pasting; the engine's to_xhtml self-closes
        # every empty element. The existing transform restores the
        # pairing for non-voids while voids stay self-closed — the
        # #135 regression pins it.
        expand_non_void_self_closing(html)
      end

      # Rewrite +<tag …/>+ into +<tag …></tag>+ for every element name
      # that is not an HTML5 void element. +<a/>+ is illegal HTML;
      # void tags like +<br/>+ and +<img …/>+ pass through unchanged.
      def expand_non_void_self_closing(html)
        html.gsub(%r{<([A-Za-z][A-Za-z0-9:_-]*)((?:\s+[^<>"]*(?:"[^"]*"[^<>"]*)*)?)/>}) do
          name = ::Regexp.last_match(1)
          attrs = ::Regexp.last_match(2)
          if HtmlVoidElements.void?(name)
            "<#{name}#{attrs}/>"
          else
            "<#{name}#{attrs}></#{name}>"
          end
        end
      end
    end
  end
end
