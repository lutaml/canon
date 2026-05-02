# frozen_string_literal: true

require "spec_helper"
require "canon/pretty_printer/xml_normalized"

RSpec.describe Canon::PrettyPrinter::XmlNormalized do
  let(:vis_map) do
    { "\n" => "↵", " " => "░", "\t" => "→" }
  end

  # Default printer: no element lists → all whitespace insensitive (dropped).
  let(:printer) do
    described_class.new(indent: 2, visualization_map: vis_map)
  end

  # Normalize printer: <p> and <formattedref> in collapse_whitespace_elements.
  # Whitespace in these elements is collapsed to a single visualized character.
  # Descendants (e.g. <a> inside <p>) inherit the setting via ancestor lookup —
  # no need to list <a> separately.
  let(:printer_normalize) do
    described_class.new(indent: 2, visualization_map: vis_map,
                        collapse_whitespace_elements: %w[p formattedref])
  end

  # Strict printer: <p> in strict_whitespace_elements.
  # Whitespace preserved verbatim with every character individually visualized.
  let(:printer_strict) do
    described_class.new(indent: 2, visualization_map: vis_map,
                        preserve_whitespace_elements: %w[p])
  end

  # Returns the full formatted output as a single string, stripping the XML
  # declaration line and normalizing trailing whitespace.
  def pretty(printer_obj, xml)
    printer_obj.format(xml).lines
      .grep_v(/\A<\?xml/)
      .join.chomp
  end

  # ─── Element-only content ─────────────────────────────────────────────────

  describe "element-only content" do
    it "renders each child element on its own indented line" do
      xml = "<root><a/><b/></root>"
      expect(pretty(printer, xml)).to eq(<<~EXPECTED.chomp)
        <root>
          <a/>
          <b/>
        </root>
      EXPECTED
    end

    it "renders a self-closing element with no children as a single tag" do
      xml = "<root><item/></root>"
      expect(pretty(printer, xml)).to eq(<<~EXPECTED.chomp)
        <root>
          <item/>
        </root>
      EXPECTED
    end

    it "renders an element with text-only content on a line within its tags" do
      xml = "<root><title>Hello World</title></root>"
      expect(pretty(printer, xml)).to eq(<<~EXPECTED.chomp)
        <root>
          <title>Hello World</title>
        </root>
      EXPECTED
    end

    it "renders nested element-only content with progressive indentation" do
      xml = "<root><outer><inner/></outer></root>"
      expect(pretty(printer, xml)).to eq(<<~EXPECTED.chomp)
        <root>
          <outer>
            <inner/>
          </outer>
        </root>
      EXPECTED
    end
  end

  # ─── Mixed content ────────────────────────────────────────────────────────
  #
  # Mixed content (elements that contain both text runs and inline elements)
  # is handled differently depending on the whitespace sensitivity setting.
  # The DEFAULT printer drops all whitespace; the NORMALIZE and STRICT printers
  # visualize it.

  describe "mixed content" do
    describe "default (insensitive) mode" do
      # Whitespace between text and inline elements is dropped entirely.
      # The text node "See " loses its trailing space.

      it "renders compact mixed content without whitespace visualization" do
        xml = "<root><p>See <em>content</em></p></root>"
        expect(pretty(printer, xml)).to eq(<<~EXPECTED.chomp)
          <root>
            <p>
              See
              <em>content</em>
            </p>
          </root>
        EXPECTED
      end

      it "renders indented fixture mixed content without whitespace visualization" do
        xml = "<root><p>\n  See\n  <xref/>\n</p></root>"
        expect(pretty(printer, xml)).to eq(<<~EXPECTED.chomp)
          <root>
            <p>
              See
              <xref/>
            </p>
          </root>
        EXPECTED
      end

      it "produces identical output for compact and indented versions of the same element" do
        compact  = "<root><p>See <xref/></p></root>"
        indented = "<root><p>\n  See\n  <xref/>\n</p></root>"
        # Both produce the same output since all whitespace is dropped
        expect(pretty(printer, compact)).to eq(pretty(printer, indented))
      end
    end

    describe "normalize mode" do
      # Whitespace is preserved but collapsed to a single visualized character.
      # A space becomes ░; a newline+indent sequence becomes a single ░ too
      # (the sequence contains a newline so it is a structural separator, but
      # in normalize mode it is still shown rather than dropped).

      it "visualizes trailing space before an inline element" do
        xml = "<root><p>See <em>content</em></p></root>"
        expect(pretty(printer_normalize, xml)).to eq(<<~EXPECTED.chomp)
          <root>
            <p>
              See░
              <em>content</em>
            </p>
          </root>
        EXPECTED
      end

      it "visualizes boundary whitespace from indented fixture formatting" do
        # The \n  after <p> open, after See, and after <xref/> are all
        # normalized to single ░ characters appended to the preceding line.
        xml = "<root><p>\n  See\n  <xref/>\n</p></root>"
        expect(pretty(printer_normalize, xml)).to eq(<<~EXPECTED.chomp)
          <root>
            <p>░
              See░
              <xref/>░
            </p>
          </root>
        EXPECTED
      end

      it "places the See line before the inline element line" do
        xml = "<root><p>See <xref target='M'/></p></root>"
        lines = pretty(printer_normalize, xml).lines.map(&:chomp)
        see_idx  = lines.index { |l| l.strip.start_with?("See") }
        xref_idx = lines.index { |l| l.include?("<xref") }
        expect(see_idx).not_to be_nil
        expect(xref_idx).not_to be_nil
        expect(see_idx).to be < xref_idx
      end
    end

    describe "strict mode" do
      # Whitespace preserved verbatim — every character individually visualized.

      it "visualizes trailing single space before an inline element" do
        xml = "<root><p>See <em>content</em></p></root>"
        expect(pretty(printer_strict, xml)).to eq(<<~EXPECTED.chomp)
          <root>
            <p>
              See░
              <em>content</em>
            </p>
          </root>
        EXPECTED
      end

      it "visualizes every character in newline+indent sequences" do
        # \n  (newline + 2 spaces) → ↵░░ for each occurrence
        xml = "<root><p>\n  See\n  <xref/>\n</p></root>"
        expect(pretty(printer_strict, xml)).to eq(<<~EXPECTED.chomp)
          <root>
            <p>↵░░
              See↵░░
              <xref/>↵
            </p>
          </root>
        EXPECTED
      end
    end
  end

  # ─── Attributes and namespaces ────────────────────────────────────────────

  describe "attribute handling" do
    it "preserves all attributes on element tags" do
      xml = '<root><elem id="1" class="foo" data-x="bar"/></root>'
      result = pretty(printer, xml)
      expect(result).to include('id="1"')
      expect(result).to include('class="foo"')
      expect(result).to include('data-x="bar"')
    end

    it "escapes special characters in attribute values" do
      xml = '<root><elem title="a &amp; b"/></root>'
      result = pretty(printer, xml)
      # Nokogiri parses &amp; to '&', our serializer re-escapes it
      expect(result).to include("a &amp; b")
    end
  end

  describe "namespace handling" do
    it "preserves namespace declarations" do
      xml = '<root xmlns:foo="http://example.com"><foo:bar/></root>'
      result = pretty(printer, xml)
      expect(result).to include('xmlns:foo="http://example.com"')
    end
  end

  # ─── Whitespace-only inter-element text nodes ─────────────────────────────

  describe "whitespace-only text nodes in element-only content" do
    it "ignores whitespace-only text nodes and still renders one element per line" do
      xml = "<root>\n  <a/>\n  <b/>\n</root>"
      expect(pretty(printer, xml)).to eq(<<~EXPECTED.chomp)
        <root>
          <a/>
          <b/>
        </root>
      EXPECTED
    end
  end

  # ─── Whitespace sensitivity classification ───────────────────────────────
  #
  # Three-way classification: strict / normalize / insensitive (drop).
  # The classification is inherited by descendants via ancestor lookup:
  # if <p> is in collapse_whitespace_elements, a descendant <a> also uses
  # normalize without needing to appear in any list itself.

  describe "whitespace sensitivity classification" do
    # ── Ancestor inheritance ────────────────────────────────────────────────
    #
    # <a> is always a child of <p> in these fixtures.  With only "p" listed in
    # collapse_whitespace_elements, <a> inherits normalize through ancestor
    # lookup — confirming that elements do not need to be listed individually.

    it "inherits normalize setting from ancestor <p> to descendant <a>" do
      printer_p_only = described_class.new(
        indent: 2,
        visualization_map: vis_map,
        collapse_whitespace_elements: %w[p],
      )
      # <a> is inside <p> — it inherits normalize.  Spaces around "link" are ░.
      xml = '<root><p>See <a href="#">link</a> text</p></root>'
      expect(pretty(printer_p_only, xml)).to eq(<<~EXPECTED.chomp)
        <root>
          <p>
            See░
            <a href="#">link</a>░
            text
          </p>
        </root>
      EXPECTED
    end

    it "inherits strict setting from ancestor <p> to descendant <a>" do
      # <p> strict → <a> inside inherits strict → spaces preserved as ░
      xml = '<root><p>See <a href="#">link</a> text</p></root>'
      expect(pretty(printer_strict, xml)).to eq(<<~EXPECTED.chomp)
        <root>
          <p>
            See░
            <a href="#">link</a>░
            text
          </p>
        </root>
      EXPECTED
    end

    it "drops whitespace in <a> inside <p> when no lists configured (insensitive)" do
      xml = '<root><p>See <a href="#">link</a> text</p></root>'
      expect(pretty(printer, xml)).to eq(<<~EXPECTED.chomp)
        <root>
          <p>
            See
            <a href="#">link</a>
            text
          </p>
        </root>
      EXPECTED
    end

    # ── Compact vs indented output equality ─────────────────────────────────
    #
    # Key goal: comparing compact Metanorma XML against hand-indented fixture
    # XML should not produce spurious whitespace-only diff lines.
    #
    # For elements where inline content space IS significant (<p>See <xref/>),
    # normalize mode reduces noise: "See░" matches on both sides.
    # The only remaining differences are the structural boundary ░ marks.
    #
    # For purely structural containers (<formattedref>) where all whitespace is
    # formatting, the default INSENSITIVE mode equalizes compact and indented.

    it "default (insensitive) produces identical output for compact and indented <formattedref>" do
      compact  = "<root><formattedref><em>Cereals</em>.</formattedref></root>"
      indented = "<root><formattedref>\n   <em>Cereals</em>\n   .\n</formattedref></root>"

      # Both produce the same output since all whitespace is dropped
      expect(pretty(printer, compact)).to eq(pretty(printer, indented))
      expect(pretty(printer, compact)).to eq(<<~EXPECTED.chomp)
        <root>
          <formattedref>
            <em>Cereals</em>
            .
          </formattedref>
        </root>
      EXPECTED
    end

    it "normalize mode shows boundary ░ differences for compact vs indented <formattedref>" do
      # Normalize is NOT the right mode for purely structural containers:
      # the compact version has no whitespace nodes at all, the indented
      # version has \n+spaces that collapse to ░, producing visible differences.
      compact  = "<root><formattedref><em>Cereals</em>.</formattedref></root>"
      indented = "<root><formattedref>\n   <em>Cereals</em>\n   .\n</formattedref></root>"

      expect(pretty(printer_normalize, compact)).to eq(<<~EXPECTED.chomp)
        <root>
          <formattedref>
            <em>Cereals</em>
            .
          </formattedref>
        </root>
      EXPECTED

      expect(pretty(printer_normalize, indented)).to eq(<<~EXPECTED.chomp)
        <root>
          <formattedref>░
            <em>Cereals</em>░
            .░
          </formattedref>
        </root>
      EXPECTED

      # Therefore compact != indented under normalize — use insensitive instead
      expect(pretty(printer_normalize,
                    compact)).not_to eq(pretty(printer_normalize, indented))
    end

    it "normalize mode equalizes the significant text line in compact vs indented <p>" do
      # For inline mixed content, the space in "See " (compact) and the
      # \n+indent around "See" (indented) both normalize to ░ on the See line.
      compact  = "<root><p>See <xref target='M'/></p></root>"
      indented = "<root><p>\n   See\n   <xref target='M'/>\n</p></root>"

      compact_lines  = pretty(printer_normalize, compact).lines.map(&:chomp)
      indented_lines = pretty(printer_normalize, indented).lines.map(&:chomp)

      # The "See░" line is identical on both sides
      expect(compact_lines.map(&:strip)).to include("See░")
      expect(indented_lines.map(&:strip)).to include("See░")

      # The <xref> line appears on its own line in both
      # (indented side has trailing ░ from the \n before </p>, hence start_with?)
      expect(compact_lines.map(&:strip)).to include('<xref target="M"/>')
      expect(indented_lines.map(&:strip).any? do |l|
        l.start_with?('<xref target="M"/>')
      end).to be true
    end

    # ── Three-mode comparison on the same fixture ────────────────────────────
    #
    # Running the same fixture through all three modes shows distinct output,
    # demonstrating the classification contract.

    it "produces different visualization across strict / normalize / default on same fixture" do
      fixture = "<root><p>See\n  <xref/>\n</p></root>"

      strict_out      = pretty(printer_strict, fixture)
      normalize_out   = pretty(printer_normalize, fixture)
      insensitive_out = pretty(printer, fixture)

      # Strict: \n  → ↵░░ character-by-character
      expect(strict_out).to eq(<<~EXPECTED.chomp)
        <root>
          <p>
            See↵░░
            <xref/>↵
          </p>
        </root>
      EXPECTED

      # Normalize: \n  → single ░ (boundary collapsed)
      expect(normalize_out).to eq(<<~EXPECTED.chomp)
        <root>
          <p>
            See░
            <xref/>░
          </p>
        </root>
      EXPECTED

      # Default (insensitive): all whitespace dropped
      expect(insensitive_out).to eq(<<~EXPECTED.chomp)
        <root>
          <p>
            See
            <xref/>
          </p>
        </root>
      EXPECTED

      # All three outputs are distinct
      expect(strict_out).not_to eq(normalize_out)
      expect(normalize_out).not_to eq(insensitive_out)
      expect(strict_out).not_to eq(insensitive_out)
    end
  end

  # ─── pretty_printed mode ──────────────────────────────────────────────────
  #
  # When pretty_printed: true, whitespace-only text nodes that start with "\n"
  # are treated as structural indentation in :normalize elements and silently
  # dropped.  This mirrors the comparison-side behaviour controlled by the
  # pretty_printed_expected / pretty_printed_received match options.

  describe "pretty_printed: true (structural newline suppression)" do
    let(:printer_pp_normalize) do
      described_class.new(
        indent: 2,
        visualization_map: vis_map,
        collapse_whitespace_elements: %w[p],
        pretty_printed: true,
      )
    end

    let(:printer_pp_strict) do
      described_class.new(
        indent: 2,
        visualization_map: vis_map,
        preserve_whitespace_elements: %w[p],
        pretty_printed: true,
      )
    end

    it "drops \\n-leading whitespace-only text nodes in :normalize elements" do
      # Pretty-printed fixture where "\n  " appear between element children
      xml = "<root><p>\n  <em>text</em>\n</p></root>"
      out = pretty(printer_pp_normalize, xml)

      # The "\n  " and "\n" nodes should be dropped, not rendered as ░
      expect(out).not_to include("░")
      expect(out).to include("<p>")
      expect(out).to include("<em>text</em>")
    end

    it "still renders space-only nodes in :normalize elements as ░" do
      # A space (no newline) is inline content, not structural indentation
      xml = "<root><p> <em>text</em></p></root>"
      out = pretty(printer_pp_normalize, xml)

      expect(out).to include("░")
    end

    it "preserves all whitespace in :strict elements even with pretty_printed: true" do
      xml = "<root><p>\n  <em>text</em>\n</p></root>"
      out = pretty(printer_pp_strict, xml)

      # :strict means every whitespace char is visualized
      expect(out).to include("↵")
    end

    it "does NOT drop \\n-leading nodes when pretty_printed: false (default)" do
      xml = "<root><p>\n  <em>text</em>\n</p></root>"
      # printer_normalize has pretty_printed: false (the default)
      out = pretty(printer_normalize, xml)

      # Without pretty_printed, the \n-leading whitespace-only node renders as ░
      expect(out).to include("░")
    end

    it "produces the same output for compact and indented input in :normalize context" do
      compact_xml = "<root><p><em>text</em></p></root>"
      indented_xml = "<root><p>\n  <em>text</em>\n</p></root>"

      compact_out  = pretty(printer_pp_normalize, compact_xml)
      indented_out = pretty(printer_pp_normalize, indented_xml)

      expect(indented_out).to eq(compact_out)
    end

    it "does NOT affect :insensitive elements (already dropped)" do
      # default printer has no whitespace lists → all insensitive
      printer_pp_default = described_class.new(
        indent: 2,
        visualization_map: vis_map,
        pretty_printed: true,
      )
      xml = "<root><item>\n  <child/>\n</item></root>"
      out = pretty(printer_pp_default, xml)

      # whitespace already dropped in insensitive mode — no ░
      expect(out).not_to include("░")
    end
  end

  describe "sort_attributes: true" do
    let(:printer_sorted) do
      described_class.new(indent: 2, visualization_map: vis_map,
                          sort_attributes: true)
    end

    it "sorts attributes alphabetically by local name" do
      xml = '<root><item zebra="1" alpha="2"/></root>'
      expect(pretty(printer_sorted, xml)).to eq(<<~EXPECTED.chomp)
        <root>
          <item alpha="2" zebra="1"/>
        </root>
      EXPECTED
    end

    it "preserves document order when sort_attributes is false (default)" do
      xml = '<root><item zebra="1" alpha="2"/></root>'
      expect(pretty(printer, xml)).to eq(<<~EXPECTED.chomp)
        <root>
          <item zebra="1" alpha="2"/>
        </root>
      EXPECTED
    end

    it "sorts namespaced attributes by namespace URI then local name" do
      xml = '<root xmlns:b="http://b" xmlns:a="http://a"><item b:x="1" a:y="2" c="3"/></root>'
      result = pretty(printer_sorted, xml)
      # "" < "http://a" < "http://b" → c, a:y, b:x
      expect(result).to include('c="3" a:y="2" b:x="1"')
    end
  end

  describe "html_mode (regression #135)" do
    let(:html_printer) { described_class.new(indent: 2, html_mode: true) }

    it "writes empty non-void elements as <tag></tag>" do
      html = '<div><a href="x"></a><span></span></div>'
      result = html_printer.format(html)
      expect(result).to include('<a href="x"></a>')
      expect(result).to include("<span></span>")
      expect(result).not_to match(%r{<a [^>]*/>})
      expect(result).not_to include("<span/>")
    end

    it "self-closes void elements (XHTML shape) without nesting siblings" do
      html = '<div><br><img src="y"><p>after</p></div>'
      result = html_printer.format(html)
      expect(result).to include("<br/>")
      expect(result).to include('<img src="y"/>')
      expect(result).not_to include("</br>")
      expect(result).not_to include("</img>")
      expect(result).to include("<p>")
    end

    it "leaves XML mode (html_mode: false) behaviour unchanged" do
      xml = "<root><empty/></root>"
      expect(printer.format(xml)).to include("<empty/>")
    end
  end
end
