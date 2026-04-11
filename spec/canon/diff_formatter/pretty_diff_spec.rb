# frozen_string_literal: true

require "spec_helper"
require "canon/diff_formatter"

# Tests for mode: :pretty_diff — the text-LCS workaround for issue #85.
#
# :pretty_diff bypasses DiffNodeMapper entirely.  It applies display_preprocessing
# to both sides and runs Diff::LCS.sdiff on the resulting plain-text lines.
# This makes every text-level change visible regardless of whether DiffNodeMapper
# can correlate DOM addresses to post-preprocessing line numbers.
RSpec.describe "DiffFormatter mode: :pretty_diff" do
  # Build a formatter with :pretty_diff mode.
  # display_preprocessing defaults to :none unless overridden.
  def formatter_for(**opts)
    Canon::DiffFormatter.new(
      use_color: false,
      mode: :pretty_diff,
      **opts,
    )
  end

  # ── XML fixtures ─────────────────────────────────────────────────────────────

  let(:xml_a) { "<root><item>Alpha</item></root>" }
  let(:xml_b) { "<root><item>Beta</item></root>" }

  # Two XML docs that are semantically identical but formatted differently.
  let(:compact_xml) do
    '<root><child id="1">Hello</child><child id="2">World</child></root>'
  end
  let(:multiline_xml) do
    <<~XML.chomp
      <root>
        <child id="1">Hello</child>
        <child id="2">World</child>
      </root>
    XML
  end

  # Issue #85 regression fixture:
  # A normative change buried alongside structural noise in a larger document.
  # In :by_line mode with display_preprocessing: :pretty_print the change can
  # be invisible because DiffNodeMapper addresses do not align with the
  # pretty-printed line numbers.  :pretty_diff shows it unconditionally.
  let(:xml_normative_before) do
    <<~XML.chomp
      <section>
        <title>Introduction</title>
        <para>This document describes the <strong>old</strong> behaviour.</para>
        <note>See also: Appendix A.</note>
      </section>
    XML
  end

  let(:xml_normative_after) do
    <<~XML.chomp
      <section>
        <title>Introduction</title>
        <para>This document describes the <strong>new</strong> behaviour.</para>
        <note>See also: Appendix A.</note>
      </section>
    XML
  end

  # ── Header ───────────────────────────────────────────────────────────────────

  describe "output header" do
    it "includes 'Pretty diff' and the uppercased format name" do
      formatter = formatter_for
      output = formatter.format([], :xml, doc1: xml_a, doc2: xml_b)
      expect(output).to include("Pretty diff (XML mode):")
    end

    it "uses the correct format name for HTML" do
      formatter = formatter_for
      html_a = "<p>Hello</p>"
      html_b = "<p>World</p>"
      output = formatter.format([], :html, doc1: html_a, doc2: html_b)
      expect(output).to include("Pretty diff (HTML mode):")
    end
  end

  # ── Identical documents ───────────────────────────────────────────────────────

  describe "identical documents" do
    it "reports no differences when both sides are the same" do
      formatter = formatter_for
      output = formatter.format([], :xml, doc1: xml_a, doc2: xml_a)
      expect(output).to include("(no differences)")
    end

    it "reports no differences for semantically identical, differently formatted XML " \
       "when display_preprocessing: :pretty_print normalises both sides" do
      formatter = formatter_for(display_preprocessing: :pretty_print)
      output = formatter.format([], :xml, doc1: compact_xml, doc2: multiline_xml)
      expect(output).to include("(no differences)")
    end
  end

  # ── Diff markers ─────────────────────────────────────────────────────────────

  describe "diff markers" do
    it "marks deleted lines with '-'" do
      formatter = formatter_for
      output = formatter.format([], :xml, doc1: xml_a, doc2: xml_b)
      expect(output).to include("- ")
    end

    it "marks added lines with '+'" do
      formatter = formatter_for
      output = formatter.format([], :xml, doc1: xml_a, doc2: xml_b)
      expect(output).to include("+ ")
    end

    it "shows the old content on '-' lines" do
      formatter = formatter_for(display_preprocessing: :pretty_print)
      output = formatter.format([], :xml, doc1: xml_a, doc2: xml_b)
      expect(output).to include("Alpha")
    end

    it "shows the new content on '+' lines" do
      formatter = formatter_for(display_preprocessing: :pretty_print)
      output = formatter.format([], :xml, doc1: xml_a, doc2: xml_b)
      expect(output).to include("Beta")
    end
  end

  # ── Issue #85 regression ─────────────────────────────────────────────────────

  describe "issue #85 regression: normative change not hidden by structural noise" do
    it "shows the normative text change ('old' → 'new') that :by_line can miss" do
      # :by_line + display_preprocessing: :pretty_print is the configuration
      # that exhibited the regression.  :pretty_diff must expose the change
      # because it never consults DiffNodeMapper.
      formatter = formatter_for(display_preprocessing: :pretty_print)
      output = formatter.format([], :xml,
                                doc1: xml_normative_before,
                                doc2: xml_normative_after)
      expect(output).to include("old")
      expect(output).to include("new")
      expect(output).not_to include("(no differences)")
    end

    it "shows '-' marker for the before line" do
      formatter = formatter_for(display_preprocessing: :pretty_print)
      output = formatter.format([], :xml,
                                doc1: xml_normative_before,
                                doc2: xml_normative_after)
      lines = output.lines.map(&:strip)
      expect(lines.any? { |l| l.start_with?("- ") && l.include?("old") }).to be true
    end

    it "shows '+' marker for the after line" do
      formatter = formatter_for(display_preprocessing: :pretty_print)
      output = formatter.format([], :xml,
                                doc1: xml_normative_before,
                                doc2: xml_normative_after)
      lines = output.lines.map(&:strip)
      expect(lines.any? { |l| l.start_with?("+ ") && l.include?("new") }).to be true
    end
  end

  # ── Context lines ─────────────────────────────────────────────────────────────

  describe "context lines" do
    it "shows unchanged context lines around the change" do
      formatter = formatter_for(context_lines: 2, display_preprocessing: :pretty_print)
      output = formatter.format([], :xml,
                                doc1: xml_normative_before,
                                doc2: xml_normative_after)
      # The title line is adjacent to the change and should appear as context
      expect(output).to include("Introduction")
    end

    it "emits a separator between non-adjacent change blocks" do
      # Build a doc with two separate changes far apart so that context
      # windows don't merge; a '--- ---' separator should appear between them.
      doc1 = (["<root>"] +
               Array.new(10) { |i| "  <item id=\"#{i}\">Same #{i}</item>" } +
               ["  <item id=\"10\">OldA</item>"] +
               Array.new(10) { |i| "  <item id=\"#{i + 11}\">Same #{i + 11}</item>" } +
               ["  <item id=\"21\">OldB</item>"] +
               ["</root>"]).join("\n")
      doc2 = (["<root>"] +
               Array.new(10) { |i| "  <item id=\"#{i}\">Same #{i}</item>" } +
               ["  <item id=\"10\">NewA</item>"] +
               Array.new(10) { |i| "  <item id=\"#{i + 11}\">Same #{i + 11}</item>" } +
               ["  <item id=\"21\">NewB</item>"] +
               ["</root>"]).join("\n")

      formatter = formatter_for(context_lines: 1)
      output = formatter.format([], :xml, doc1: doc1, doc2: doc2)
      expect(output).to include("--- ---")
    end

    it "respects context_lines: 0 (change lines only, no surrounding context)" do
      formatter = formatter_for(context_lines: 0, display_preprocessing: :pretty_print)
      output = formatter.format([], :xml,
                                doc1: xml_normative_before,
                                doc2: xml_normative_after)
      # With context_lines: 0, only the changed lines should appear (no "Same" context)
      # The title line should NOT appear because it's pure context
      lines = output.lines.map(&:strip).reject(&:empty?)
        .reject { |l| l.start_with?("Pretty diff", "--- ---") }
      expect(lines.all? { |l| l.start_with?("- ", "+ ") }).to be true
    end
  end

  # ── Preprocessing combinations ────────────────────────────────────────────────

  describe "display_preprocessing combinations" do
    it "works with display_preprocessing: :none (raw line diff)" do
      formatter = formatter_for(display_preprocessing: :none)
      output = formatter.format([], :xml, doc1: xml_a, doc2: xml_b)
      expect(output).to include("Pretty diff (XML mode):")
      expect(output).to include("Alpha").or include("- ")
    end

    it "works with display_preprocessing: :c14n" do
      formatter = formatter_for(display_preprocessing: :c14n)
      output = formatter.format([], :xml, doc1: xml_a, doc2: xml_b)
      expect(output).to include("- ").or include("+ ")
    end

    it "works with display_preprocessing: :pretty_print" do
      formatter = formatter_for(display_preprocessing: :pretty_print)
      output = formatter.format([], :xml, doc1: xml_a, doc2: xml_b)
      expect(output).to include("- ").or include("+ ")
    end
  end

  # ── Nil document handling ─────────────────────────────────────────────────────

  describe "nil document handling" do
    it "returns just the header when doc1 is nil" do
      formatter = formatter_for
      output = formatter.format([], :xml, doc1: nil, doc2: xml_b)
      expect(output).to include("Pretty diff (XML mode):")
      expect(output).not_to include("- ")
    end

    it "returns just the header when doc2 is nil" do
      formatter = formatter_for
      output = formatter.format([], :xml, doc1: xml_a, doc2: nil)
      expect(output).to include("Pretty diff (XML mode):")
      expect(output).not_to include("+ ")
    end
  end

  # ── normalize_pretty_print_ignore_structural_newlines ─────────────────────────
  #
  # These tests cover the isodoc scenario reported in lutaml/canon#86:
  # compact Metanorma XML compared against a hand-formatted (indented) fixture
  # heredoc.  Without the flag, spurious `↵░░░` markers on the A-side cause
  # false diffs for lines that differ only in structural indentation whitespace.
  # With the flag, those whitespace-only newline nodes are dropped on both sides,
  # producing identical serialized lines and therefore no diff.

  describe "normalize_pretty_print_ignore_structural_newlines" do
    # The fixture models the actual isodoc failing test:
    # compact actual XML  vs  indented expected heredoc.
    let(:compact_formattedref) do
      '<root><bibitem id="ISO712"><formattedref>' \
        "<em>Cereals and cereal products</em>." \
        "</formattedref></bibitem></root>"
    end

    let(:indented_formattedref) do
      <<~XML.chomp
        <root><bibitem id="ISO712"><formattedref>
          <em>Cereals and cereal products</em>
          .
        </formattedref></bibitem></root>
      XML
    end

    context "without collapse_whitespace_elements (default: insensitive)" do
      it "produces no spurious diffs from structural newline whitespace" do
        # Default (insensitive) mode drops all inter-element whitespace.
        # compact and indented formattedref are therefore identical after
        # preprocessing — no diff markers appear.
        formatter = formatter_for(display_preprocessing: :normalize_pretty_print)
        output = formatter.format([], :xml,
                                  doc1: compact_formattedref,
                                  doc2: indented_formattedref)
        diff_marker_lines = output.lines.grep(/\|\s+\d+[+-]/)
        expect(diff_marker_lines).to be_empty
      end
    end

    context "with collapse_whitespace_elements" do
      it "detects content-space difference between <a> <b> and <a><b> using collapse_whitespace_elements" do
        # A single space between inline elements is real content.
        # With collapse_whitespace_elements: ["p"], the trailing space in
        # "text " is visualized as ░ — making it distinguishable from "text"
        # (no space), so the diff correctly shows a changed line.
        compact_with_space = "<root><p>text <em>bold</em> rest</p></root>"
        compact_no_space   = "<root><p>text<em>bold</em> rest</p></root>"

        formatter = formatter_for(
          display_preprocessing: :normalize_pretty_print,
          collapse_whitespace_elements: ["p"],
        )
        output = formatter.format([], :xml,
                                  doc1: compact_with_space,
                                  doc2: compact_no_space)
        # The space before <em> is visualized as ░ on the with-space side
        # but absent on the no-space side → must appear as changed lines.
        expect(output).to include("- ")
        expect(output).to include("+ ")
      end
    end

    context "via Canon::Config (collapse_whitespace_elements)" do
      around do |example|
        Canon::Config.reset!
        example.run
        Canon::Config.reset!
      end

      it "reads collapse_whitespace_elements from config" do
        Canon::Config.configure do |cfg|
          cfg.xml.diff.mode = :pretty_diff
          cfg.xml.diff.display_preprocessing = :normalize_pretty_print
          cfg.xml.diff.collapse_whitespace_elements = %w[p formattedref]
        end

        diff_config = Canon::Config.instance.xml.diff
        expect(diff_config.collapse_whitespace_elements).to include("p")
        expect(diff_config.collapse_whitespace_elements).to include("formattedref")
      end

      it "defaults collapse_whitespace_elements to an empty array" do
        diff_config = Canon::Config.instance.xml.diff
        expect(diff_config.collapse_whitespace_elements).to eq([])
      end
    end
  end

  # ── pretty_printed_expected / pretty_printed_received ──────────────────────
  #
  # When either flag is set on the DiffFormatter, `apply_normalize_pretty_print`
  # creates side-specific XmlNormalized printers with the corresponding
  # `pretty_printed:` flag.  The result is that structural "\n\s+" indentation
  # in :normalize elements is suppressed on only the flagged side.

  describe "pretty_printed_expected / pretty_printed_received flags" do
    # Indented (fixture) vs compact (received) in a :normalize element
    let(:fixture_indented) do
      "<root><fmt-title>\n  <semx>Foreword</semx>\n</fmt-title></root>"
    end
    let(:received_compact) do
      "<root><fmt-title><semx>Foreword</semx></fmt-title></root>"
    end

    def formatter_pp(expected:, received:)
      Canon::DiffFormatter.new(
        use_color: false,
        mode: :pretty_diff,
        display_preprocessing: :normalize_pretty_print,
        collapse_whitespace_elements: %w[fmt-title semx],
        pretty_printed_expected: expected,
        pretty_printed_received: received,
      )
    end

    it "shows no structural differences when pretty_printed_expected: true" do
      f = formatter_pp(expected: true, received: false)
      out = f.format([], :xml, doc1: fixture_indented, doc2: received_compact)
      # No diff lines (only the "no differences" indicator or header)
      expect(out).not_to include("- ")
      expect(out).not_to include("+ ")
    end

    it "shows structural differences when neither flag is set (default)" do
      f = formatter_pp(expected: false, received: false)
      out = f.format([], :xml, doc1: fixture_indented, doc2: received_compact)
      # The extra ░ nodes from the indented fixture appear as deleted lines
      expect(out).to include("- ") | include("+ ")
    end

    it "Config defaults both flags to false" do
      Canon::Config.reset!
      diff_config = Canon::Config.instance.xml.diff
      expect(diff_config.pretty_printed_expected).to be false
      expect(diff_config.pretty_printed_received).to be false
      Canon::Config.reset!
    end

    context "via Canon::Config" do
      around do |example|
        Canon::Config.reset!
        example.run
        Canon::Config.reset!
      end

      it "reads pretty_printed_expected from config and passes it to the formatter" do
        Canon::Config.configure do |cfg|
          cfg.xml.diff.display_preprocessing = :normalize_pretty_print
          cfg.xml.diff.collapse_whitespace_elements = %w[fmt-title semx]
          cfg.xml.diff.pretty_printed_expected = true
          cfg.xml.diff.pretty_printed_received = false
        end

        diff_config = Canon::Config.instance.xml.diff
        expect(diff_config.pretty_printed_expected).to be true
        expect(diff_config.pretty_printed_received).to be false
      end

      it "reads pretty_printed_received from config" do
        Canon::Config.configure do |cfg|
          cfg.xml.diff.pretty_printed_expected = false
          cfg.xml.diff.pretty_printed_received = true
        end

        diff_config = Canon::Config.instance.xml.diff
        expect(diff_config.pretty_printed_expected).to be false
        expect(diff_config.pretty_printed_received).to be true
      end
    end
  end
end
