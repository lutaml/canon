# frozen_string_literal: true

require "nokogiri" unless RUBY_ENGINE == "opal"
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

      def format_as_xhtml(html_string)
        doc = Nokogiri::XML(html_string, &:noblanks)

        out = if @indent_type == "tab"
                doc.to_xml(indent: 1, indent_text: "\t", encoding: "UTF-8")
              else
                doc.to_xml(indent: @indent, encoding: "UTF-8")
              end

        expand_non_void_self_closing(out)
      end

      def format_as_html(html_string)
        doc = Nokogiri::HTML5(html_string)

        if @indent_type == "tab"
          doc.to_html(indent: 1, indent_text: "\t", encoding: "UTF-8")
        else
          doc.to_html(indent: @indent, encoding: "UTF-8")
        end
      end

      # Fixture-ready serialisation: parse with Nokogiri::HTML5 (so we
      # get permissive recovery on real-world Word / XHTML5 / HTML5
      # input shapes), then write through libxml's XML writer with
      # +FORMAT+ + +AS_XHTML+ + +NO_DECLARATION+.  +FORMAT+ inserts
      # indentation; +AS_XHTML+ produces well-shaped output (void
      # elements self-closed, non-void paired); +NO_DECLARATION+
      # suppresses the +<?xml ...?>+ prefix.
      def format_fixture_ready(html_string)
        doc = Nokogiri::HTML5(html_string)
        strip_structural_whitespace!(doc)
        io = StringIO.new
        if @indent_type == "tab"
          doc.write_to(io, save_with: fixture_ready_save_options,
                           indent: 1, indent_text: "\t")
        else
          doc.write_to(io, save_with: fixture_ready_save_options,
                           indent: @indent)
        end
        io.string
      end

      # libxml's +FORMAT+ save flag does not insert indentation around
      # the children of any element it sees as mixed content (any
      # non-whitespace-only text node child).  +Nokogiri::HTML5+ does
      # not accept the +noblanks+ option that the XML parser uses to
      # strip these inter-sibling text nodes pre-serialisation, so we
      # do it manually here: drop whitespace-only text nodes whose
      # parent is structural (no real text content) and not a
      # whitespace-preserving element.  Mixed-content runs like
      # +<p>foo <em>bar</em> baz</p>+ are left alone.
      def strip_structural_whitespace!(doc)
        to_remove = []
        doc.traverse do |node|
          next unless node.text?
          next unless node.content.strip.empty?

          parent = node.parent
          next if parent.nil?
          next if WHITESPACE_PRESERVING_ELEMENTS.include?(parent.name)
          next if parent_has_real_text?(parent)

          to_remove << node
        end
        to_remove.each(&:remove)
      end

      def parent_has_real_text?(parent)
        parent.children.any? do |c|
          c.text? && !c.content.strip.empty?
        end
      end

      def fixture_ready_save_options
        Nokogiri::XML::Node::SaveOptions::FORMAT |
          Nokogiri::XML::Node::SaveOptions::AS_XHTML |
          Nokogiri::XML::Node::SaveOptions::NO_DECLARATION
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
