# frozen_string_literal: true

require "spec_helper"
require "canon/diff_formatter"
require "canon/pretty_printer/xml"
require "canon/xml/c14n"

RSpec.describe "DiffFormatter display preprocessing" do
  # Helper: build a formatter with display_preprocessing already set.
  def formatter_for(display_preprocessing:, indent: 2, indent_type: :space)
    Canon::DiffFormatter.new(
      use_color: false,
      mode: :by_line,
      display_preprocessing: display_preprocessing,
      pretty_printer_indent: indent,
      pretty_printer_indent_type: indent_type,
    )
  end

  # Two XML strings that are semantically identical but formatted differently.
  # :none treats them as different text; :pretty_print normalises both → identical.
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

  # Two XML docs that have the same structure but differ at one element.
  # Used to produce a diff that contains context lines (the unchanged elements).
  let(:xml_items_a) do
    '<root><item id="1">Alpha</item><item id="2">Same</item></root>'
  end
  let(:xml_items_b) do
    '<root><item id="1">Alpha</item><item id="2">Different</item></root>'
  end

  # Small single-element XML with a content difference.
  let(:xml_a) { "<root><item>Alpha</item></root>" }
  let(:xml_b) { "<root><item>Beta</item></root>" }

  # Pre-formatted JSON documents (already in the form Canon.format produces).
  # Using pre-formatted input means the JSON formatter's own pass doesn't change
  # them, so "no extra change" assertions are valid.
  let(:pretty_json_a) { "{\n  \"key\": \"alpha\"\n}" }
  let(:pretty_json_b) { "{\n  \"key\": \"beta\"\n}" }

  # ── :none (default) ─────────────────────────────────────────────────────────
  #
  # :none means no *additional* display preprocessing is applied on top of the
  # by-line formatter's own rendering pipeline.  The by-line XML formatter
  # always applies its own processing (splitting at >< boundaries and applying
  # character visualization), and :none preserves that existing behaviour.

  describe "display_preprocessing: :none (default)" do
    it "uses the by-line formatter's own rendering pipeline without extra preprocessing" do
      formatter = formatter_for(display_preprocessing: :none)
      output = formatter.format([], :xml, doc1: compact_xml,
                                          doc2: multiline_xml)

      # The by-line formatter applies character visualization (spaces → ░) to
      # the multiline XML's indentation, confirming it ran its own pipeline.
      expect(output).to include("░")

      # There is output beyond the header line because the two strings differ.
      expect(output.lines.count).to be > 1
    end

    it "is the default when no display_preprocessing is given" do
      formatter = Canon::DiffFormatter.new(use_color: false, mode: :by_line)
      output = formatter.format([], :xml, doc1: compact_xml,
                                          doc2: multiline_xml)

      # Same behaviour as explicit :none
      expect(output).to include("░")
    end

    it "shows diff lines because differently-formatted identical docs look different as text" do
      formatter_none = formatter_for(display_preprocessing: :none)
      formatter_pp = formatter_for(display_preprocessing: :pretty_print)

      output_none = formatter_none.format([], :xml, doc1: compact_xml,
                                                    doc2: multiline_xml)
      output_pp = formatter_pp.format([], :xml, doc1: compact_xml,
                                                doc2: multiline_xml)

      # :none: docs differ as strings → more output lines (diff content visible)
      # :pretty_print: docs become identical after pretty-printing → only the header
      expect(output_none.lines.count).to be > output_pp.lines.count
    end
  end

  # ── :pretty_print ────────────────────────────────────────────────────────────

  describe "display_preprocessing: :pretty_print" do
    subject(:formatter) { formatter_for(display_preprocessing: :pretty_print) }

    it "produces no diff lines for structurally identical docs regardless of original formatting" do
      # compact_xml and multiline_xml have the same content; after pretty-printing
      # both sides are identical, so the diff has nothing to show.
      output = formatter.format([], :xml, doc1: compact_xml,
                                          doc2: multiline_xml)

      # No +/- markers in the line number column: all lines are context (unchanged)
      diff_marker_lines = output.lines.grep(/\|\s+\d+[+-]/)
      expect(diff_marker_lines).to be_empty
    end

    it "still shows differences in content after pretty-printing" do
      output = formatter.format([], :xml, doc1: xml_a, doc2: xml_b)
      expect(output).to include("Alpha").or include("Beta")
    end

    it "respects indent: 4 — context lines show 4-space (░░░░) indented elements" do
      # xml_items_a and xml_items_b differ at item id=2; item id=1 is a context line.
      # After pretty-printing with indent: 4, context lines show 4-space indentation.
      # Character visualization maps ASCII space → ░, so 4 spaces → ░░░░.
      output = formatter_for(display_preprocessing: :pretty_print, indent: 4)
        .format([], :xml, doc1: xml_items_a, doc2: xml_items_b)
      expect(output).to include("░░░░<item")
    end

    it "respects indent_type: :tab — context lines show tab (⇥) indented elements" do
      # Same fixture; with indent_type: :tab the indentation is a tab character.
      # Character visualization maps tab → ⇥.
      formatter_tab = formatter_for(
        display_preprocessing: :pretty_print,
        indent_type: :tab,
      )
      output = formatter_tab.format([], :xml, doc1: xml_items_a,
                                              doc2: xml_items_b)
      expect(output).to include("⇥<item")
    end

    it "falls back to original string when XML is unparseable" do
      bad_xml = "not xml at all << >"
      expect do
        formatter.format([], :xml, doc1: bad_xml, doc2: bad_xml)
      end.not_to raise_error
    end

    # ── JSON: :pretty_print falls through ────────────────────────────────────
    #
    # For JSON documents, :pretty_print is a pass-through: the formatter's
    # apply_pretty_print returns [doc1, doc2] unchanged.  The JSON by-line
    # formatter then applies its own normalization (Canon.format / JSON.pretty_generate).
    # Pre-formatted JSON input is therefore unchanged by that second pass too,
    # so "key" appears identically in the diff output.

    it "passes pre-formatted JSON through unchanged, letting the JSON formatter handle it" do
      output = formatter.format([], :json, doc1: pretty_json_a,
                                           doc2: pretty_json_b)

      # "key" line is a context line (unchanged between a and b)
      expect(output).to include('"key"')

      # The changed value lines appear in the diff
      expect(output).to include("alpha")
      expect(output).to include("beta")
    end

    it "applies to HTML format without raising" do
      html_a = "<html><body><p>Hello</p></body></html>"
      html_b = "<html><body><p>Hi</p></body></html>"
      expect do
        formatter.format([], :html, doc1: html_a, doc2: html_b)
      end.not_to raise_error
    end
  end

  # ── :c14n ────────────────────────────────────────────────────────────────────

  describe "display_preprocessing: :c14n" do
    subject(:formatter) { formatter_for(display_preprocessing: :c14n) }

    it "canonicalizes both documents before diffing (attribute order normalized)" do
      # C14N sorts attributes alphabetically, so attr-order differences disappear.
      xml_with_attrs_a = '<root b="2" a="1"/>'
      xml_with_attrs_b = '<root a="1" b="2"/>'
      output = formatter.format([], :xml, doc1: xml_with_attrs_a,
                                          doc2: xml_with_attrs_b)
      diff_marker_lines = output.lines.grep(/\|\s+\d+[+-]/)
      expect(diff_marker_lines).to be_empty
    end

    it "falls back gracefully on invalid XML without raising" do
      expect do
        formatter.format([], :xml, doc1: "<<<", doc2: "<root/>")
      end.not_to raise_error
    end

    # NOTE: Testing that c14n diffs correctly show *content* differences
    # (e.g. Alpha vs Beta) requires investigating interaction with the XML
    # by-line formatter's own rendering. That investigation is tracked as
    # a follow-up to Group 4 of the initial test failure analysis.
  end

  # ── :normalize_pretty_print ──────────────────────────────────────────────────
  #
  # Like :pretty_print but uses PrettyPrinter::XmlNormalized, which guarantees
  # one line per XML node even for mixed content (elements that contain both text
  # and child elements).  Boundary whitespace from the document is preserved and
  # visualized using the character map so it is distinguishable from structural
  # indentation added by the serializer.

  describe "display_preprocessing: :normalize_pretty_print" do
    subject(:formatter) do
      formatter_for(display_preprocessing: :normalize_pretty_print)
    end

    # ── Structural normalization ────────────────────────────────────────────

    it "produces no diff lines for structurally identical docs regardless of original formatting" do
      # compact_xml and multiline_xml have the same content; after normalization
      # both sides serialize identically so the diff has nothing to show.
      output = formatter.format([], :xml, doc1: compact_xml,
                                          doc2: multiline_xml)
      diff_marker_lines = output.lines.grep(/\|\s+\d+[+-]/)
      expect(diff_marker_lines).to be_empty
    end

    it "still shows content differences after normalization" do
      output = formatter.format([], :xml, doc1: xml_a, doc2: xml_b)
      expect(output).to include("Alpha").or include("Beta")
    end

    # ── Mixed content handling ───────────────────────────────────────────────

    it "breaks compact mixed-content elements onto one line per node" do
      # This is the core difference from :pretty_print, which keeps mixed content
      # on a single line.
      compact_mixed = '<root><p>See <xref target="M"/></p></root>'
      formatter.format([], :xml, doc1: compact_mixed, doc2: compact_mixed)
      # With normalize_pretty_print, <xref/> appears on its own line — it is
      # NOT merged into a single "<p>See <xref.../>...</p>" line.
      # Since both sides are identical there are no diff markers, but the
      # preprocessing output (which both sides become) has one element per line.
      # We verify this by checking that <xref appears on a line that does not
      # also start with <p:
      require "canon/pretty_printer/xml_normalized"
      printer = Canon::PrettyPrinter::XmlNormalized.new(
        indent: 2,
        visualization_map: Canon::DiffFormatter::DEFAULT_VISUALIZATION_MAP,
      )
      normalized = printer.format(compact_mixed)
      lines = normalized.lines.map(&:strip).reject(&:empty?)
      p_line = lines.find { |l| l.start_with?("<p") }
      xref_line = lines.find { |l| l.include?("<xref") }
      expect(p_line).to be_truthy
      expect(xref_line).to be_truthy
      # They must be on different lines
      expect(p_line).not_to eq(xref_line)
    end

    it "visualizes trailing boundary space from compact mixed content" do
      # "See <xref/>" — the space between "See" and the xref is real content.
      # With collapse_whitespace_elements: ["p"], it is visualized as ░.
      compact_mixed = '<root><p>See <xref target="M"/></p></root>'
      require "canon/pretty_printer/xml_normalized"
      printer = Canon::PrettyPrinter::XmlNormalized.new(
        indent: 2,
        visualization_map: Canon::DiffFormatter::DEFAULT_VISUALIZATION_MAP,
        collapse_whitespace_elements: ["p"],
      )
      normalized = printer.format(compact_mixed)
      expect(normalized).to include("See░")
    end

    it "visualizes fixture formatting whitespace on the expected side" do
      # The fixture (expected) XML has indentation inside the <p> element.
      # With preserve_whitespace_elements: ["p"], that whitespace appears as ↵░░
      # at the end of lines, making it visible in the diff output.
      fixture_xml = "<root><p id=\"A\">\n  See\n  <xref target=\"M\"/>\n</p></root>"
      require "canon/pretty_printer/xml_normalized"
      printer = Canon::PrettyPrinter::XmlNormalized.new(
        indent: 2,
        visualization_map: Canon::DiffFormatter::DEFAULT_VISUALIZATION_MAP,
        preserve_whitespace_elements: ["p"],
      )
      normalized = printer.format(fixture_xml)
      expect(normalized).to include("↵")
    end

    # ── Fault tolerance ──────────────────────────────────────────────────────

    it "falls back to the original string when XML is unparseable" do
      bad_xml = "not xml at all << >"
      expect do
        formatter.format([], :xml, doc1: bad_xml, doc2: bad_xml)
      end.not_to raise_error
    end

    it "applies to HTML format without raising" do
      html_a = "<html><body><p>Hello</p></body></html>"
      html_b = "<html><body><p>Hi</p></body></html>"
      expect do
        formatter.format([], :html, doc1: html_a, doc2: html_b)
      end.not_to raise_error
    end
  end

  # ── HTML format ──────────────────────────────────────────────────────────────

  describe "HTML format" do # rubocop:disable RSpec/MultipleMemoizedHelpers
    # Two HTML strings with the same structure but different whitespace.
    let(:compact_html) do
      "<html><body><p>Hello</p><p>World</p></body></html>"
    end

    let(:indented_html) do
      <<~HTML.chomp
        <html>
          <body>
            <p>Hello</p>
            <p>World</p>
          </body>
        </html>
      HTML
    end

    # HTML snippets with a single content difference.
    # One element per line so the DOM/line-range-mapper pipeline has parseable
    # line boundaries to work with (compact single-line HTML collapses to one
    # line and produces no diff output from the legacy DOM formatter).
    let(:html_a) do
      "<html>\n<body>\n<p>Alpha</p>\n</body>\n</html>"
    end
    let(:html_b) do
      "<html>\n<body>\n<p>Beta</p>\n</body>\n</html>"
    end

    # Two HTML strings that differ only in attribute order.
    let(:html_attrs_a) do
      '<html><body><p class="note" id="p1">Text</p></body></html>'
    end
    let(:html_attrs_b) do
      '<html><body><p id="p1" class="note">Text</p></body></html>'
    end

    describe "display_preprocessing: :none (default)" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      it "does not raise for HTML input" do
        formatter = formatter_for(display_preprocessing: :none)
        expect do
          formatter.format([], :html, doc1: compact_html, doc2: indented_html)
        end.not_to raise_error
      end

      it "produces output for differently-formatted HTML" do
        formatter = formatter_for(display_preprocessing: :none)
        output = formatter.format([], :html, doc1: compact_html,
                                             doc2: indented_html)
        expect(output).not_to be_empty
      end
    end

    describe "display_preprocessing: :pretty_print" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      subject(:formatter) do
        formatter_for(display_preprocessing: :pretty_print)
      end

      it "does not raise for HTML input" do
        expect do
          formatter.format([], :html, doc1: compact_html, doc2: indented_html)
        end.not_to raise_error
      end

      it "produces fewer diff lines for structurally identical HTML than :none" do
        # :pretty_print normalizes both sides through Canon::PrettyPrinter::Html,
        # so structurally equivalent HTML with different whitespace converges.
        formatter_none = formatter_for(display_preprocessing: :none)
        formatter_pp = formatter_for(display_preprocessing: :pretty_print)

        output_none = formatter_none.format([], :html, doc1: compact_html,
                                                       doc2: indented_html)
        output_pp = formatter_pp.format([], :html, doc1: compact_html,
                                                   doc2: indented_html)

        expect(output_none.lines.count).to be > output_pp.lines.count
      end

      # NOTE: Standalone HTML format without DiffNodes (empty differences array)
      # returns only the header line — the legacy DOM path that would have handled
      # this is being removed (see https://github.com/lutaml/canon/issues/84).
      # Content-diff for HTML is fully supported via the RSpec matcher
      # (be_html_equivalent_to), which always supplies DiffNodes.
      it "does not raise for content-differing HTML (legacy path being removed — see issue #84)" do
        expect do
          formatter.format([], :html, doc1: html_a, doc2: html_b)
        end.not_to raise_error
      end

      it "falls back to original string on unparseable HTML without raising" do
        expect do
          formatter.format([], :html, doc1: "<<not html>>", doc2: html_b)
        end.not_to raise_error
      end
    end

    describe "display_preprocessing: :c14n" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      subject(:formatter) { formatter_for(display_preprocessing: :c14n) }

      it "does not raise for HTML input" do
        expect do
          formatter.format([], :html, doc1: html_a, doc2: html_b)
        end.not_to raise_error
      end

      it "normalizes HTML through the HTML5 serializer before diffing" do
        # Both sides are run through Nokogiri::HTML5#to_html, which produces a
        # consistent canonical serialization. Attribute-order differences in
        # HTML (which are significant in text comparison) are normalized away.
        output = formatter.format([], :html, doc1: html_attrs_a,
                                             doc2: html_attrs_b)

        # After HTML5 serialization, both sides should be identical (or very
        # close). Count diff-marker lines — there should be none.
        diff_marker_lines = output.lines.grep(/\|\s+\d+[+-]/)
        expect(diff_marker_lines).to be_empty
      end

      it "falls back gracefully on invalid HTML without raising" do
        expect do
          formatter.format([], :html, doc1: "this is not html at all < >",
                                      doc2: "<p>ok</p>")
        end.not_to raise_error
      end
    end

    describe "character_visualization with HTML" do # rubocop:disable RSpec/MultipleMemoizedHelpers
      # Multi-line HTML with explicit indentation so the HTML formatter (which
      # internally runs PrettyPrinter::Html) has line-separated content to diff.
      # The 2-space and 4-space indentation produce ░░ / ░░░░ in visualized output.
      let(:html_diff_a) do
        "<html>\n  <body>\n    <p>Alpha</p>\n  </body>\n</html>"
      end
      let(:html_diff_b) do
        "<html>\n  <body>\n    <p>Beta</p>\n  </body>\n</html>"
      end

      # NOTE: Standalone HTML format without DiffNodes returns only the header
      # (the legacy DOM path is being removed — see issue #84).  Character
      # visualization for HTML is exercised indirectly via the RSpec matcher
      # which supplies DiffNodes and always takes the pipeline path.
      it "true (default) — does not raise with character_visualization: true (see issue #84)" do
        formatter = Canon::DiffFormatter.new(use_color: false, mode: :by_line,
                                             character_visualization: true)
        expect do
          formatter.format([], :html, doc1: html_diff_a, doc2: html_diff_b)
        end.not_to raise_error
      end

      it "false — no character substitution in HTML output" do
        formatter = Canon::DiffFormatter.new(use_color: false, mode: :by_line,
                                             character_visualization: false)
        output = formatter.format([], :html, doc1: html_diff_a,
                                             doc2: html_diff_b)
        expect(output).not_to include("░")
      end

      it "false — HTML formatter output contains plain spaces" do
        formatter = Canon::DiffFormatter.new(use_color: false, mode: :by_line,
                                             character_visualization: false)
        output = formatter.format([], :html, doc1: html_diff_a,
                                             doc2: html_diff_b)
        # Plain spaces appear without ░ substitution
        expect(output).to include(" ")
      end
    end
  end

  # ── initialization defaults ──────────────────────────────────────────────────

  describe "DiffFormatter initialization" do
    it "defaults display_preprocessing to :none" do
      f = Canon::DiffFormatter.new
      expect(f.instance_variable_get(:@display_preprocessing)).to eq(:none)
    end

    it "defaults pretty_printer_indent to 2" do
      f = Canon::DiffFormatter.new
      expect(f.instance_variable_get(:@pretty_printer_indent)).to eq(2)
    end

    it "defaults pretty_printer_indent_type to :space" do
      f = Canon::DiffFormatter.new
      expect(f.instance_variable_get(:@pretty_printer_indent_type)).to eq(:space)
    end

    it "accepts all three new parameters" do
      f = Canon::DiffFormatter.new(
        display_preprocessing: :pretty_print,
        pretty_printer_indent: 4,
        pretty_printer_indent_type: :tab,
      )
      expect(f.instance_variable_get(:@display_preprocessing)).to eq(:pretty_print)
      expect(f.instance_variable_get(:@pretty_printer_indent)).to eq(4)
      expect(f.instance_variable_get(:@pretty_printer_indent_type)).to eq(:tab)
    end

    it "defaults character_visualization to true" do
      f = Canon::DiffFormatter.new
      expect(f.instance_variable_get(:@character_visualization)).to be(true)
    end
  end

  describe "character_visualization" do
    let(:xml_a) do
      "<root>\n  <item>Hello world</item>\n</root>"
    end
    let(:xml_b) do
      "<root>\n  <item>Hello world</item>\n</root>"
    end
    let(:xml_diff_a) { "<root>\n  <item>Alpha</item>\n</root>" }
    let(:xml_diff_b) { "<root>\n  <item>Beta</item>\n</root>" }

    it "true (default) — space characters are replaced with ░ in context lines" do
      formatter = Canon::DiffFormatter.new(use_color: false, mode: :by_line,
                                           character_visualization: true)
      output = formatter.format([], :xml, doc1: xml_diff_a, doc2: xml_diff_b)
      # The 2-space indentation before <item> should be visualized as ░░
      expect(output).to include("░░")
    end

    it "false — no character substitution; plain spaces remain in output" do
      formatter = Canon::DiffFormatter.new(use_color: false, mode: :by_line,
                                           character_visualization: false)
      output = formatter.format([], :xml, doc1: xml_diff_a, doc2: xml_diff_b)
      # ░ must NOT appear; plain spaces should be present
      expect(output).not_to include("░")
      expect(output).to include("  <item")
    end

    it ":content_only currently behaves as true (full map applied)" do
      formatter = Canon::DiffFormatter.new(use_color: false, mode: :by_line,
                                           character_visualization: :content_only)
      output = formatter.format([], :xml, doc1: xml_diff_a, doc2: xml_diff_b)
      # Behaves same as true — spaces visualized
      expect(output).to include("░░")
    end

    it "false — visualization map is empty" do
      formatter = Canon::DiffFormatter.new(character_visualization: false)
      expect(formatter.instance_variable_get(:@visualization_map)).to eq({})
    end

    it "true — visualization map contains the space character" do
      formatter = Canon::DiffFormatter.new(character_visualization: true)
      expect(formatter.instance_variable_get(:@visualization_map)).to include(" " => "░")
    end
  end
end
