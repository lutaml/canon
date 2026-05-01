# frozen_string_literal: true

require "nokogiri"
require "stringio"

module Canon
  module PrettyPrinter
    # Pretty printer for HTML with consistent indentation
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
    #    elements self-closed, non-void paired) and prefixed with
    #    +<?xml ...?>+; this is a display-only serialisation.
    #
    # See lutaml/canon#133.
    class Html
      def initialize(indent: 2, indent_type: "space", fixture_ready: false)
        @indent = indent.to_i
        @indent_type = indent_type
        @fixture_ready = fixture_ready
      end

      # Pretty print HTML with consistent indentation
      def format(html_string)
        return format_fixture_ready(html_string) if @fixture_ready

        # Detect if this is XHTML or HTML
        if xhtml?(html_string)
          format_as_xhtml(html_string)
        else
          format_as_html(html_string)
        end
      end

      private

      def xhtml?(html_string)
        # Check for XHTML DOCTYPE or xmlns attribute
        html_string.include?("XHTML") ||
          html_string.include?('xmlns="http://www.w3.org/1999/xhtml"')
      end

      def format_as_xhtml(html_string)
        # Parse as XML for XHTML
        doc = Nokogiri::XML(html_string, &:noblanks)

        # Use Nokogiri's built-in pretty printing
        if @indent_type == "tab"
          doc.to_xml(indent: 1, indent_text: "\t", encoding: "UTF-8")
        else
          doc.to_xml(indent: @indent, encoding: "UTF-8")
        end
      end

      def format_as_html(html_string)
        # Parse as HTML5
        doc = Nokogiri::HTML5(html_string)

        # Use Nokogiri's built-in pretty printing
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
      # elements self-closed, non-void paired) which is the format
      # users want to paste into a fixture heredoc.  +NO_DECLARATION+
      # suppresses the +<?xml ...?>+ prefix that libxml otherwise
      # emits in XML-writer mode.
      def format_fixture_ready(html_string)
        doc = Nokogiri::HTML5(html_string)
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

      def fixture_ready_save_options
        Nokogiri::XML::Node::SaveOptions::FORMAT |
          Nokogiri::XML::Node::SaveOptions::AS_XHTML |
          Nokogiri::XML::Node::SaveOptions::NO_DECLARATION
      end
    end
  end
end
