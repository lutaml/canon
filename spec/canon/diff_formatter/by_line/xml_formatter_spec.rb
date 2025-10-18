# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::DiffFormatter::ByLine::XmlFormatter do
  let(:formatter) do
    described_class.new(
      use_color: false,
      diff_grouping_lines: 10,
      visualization_map: Canon::DiffFormatter::DEFAULT_VISUALIZATION_MAP,
    )
  end

  describe "#format" do
    context "when multi-line content is compressed to single line" do
      it "shows all deleted lines from the multi-line version" do
        # This tests the bug fix where not all lines were shown when
        # multi-line XML content gets compressed into a single line
        xml1 = <<~XML
          <quote id="_">
            <p id="_">This International Standard gives the minimum specifications for rice (<em>Oryza sativa</em> L.) which is subject to international trade.</p>
            <attribution>
              <p>
                —
                <semx element="author" source="_">ISO</semx>
                ,
                <semx element="source" source="_">
                  <fmt-eref type="inline" bibitemid="ISO7301" citeas="ISO 7301:2011">
                    <locality type="clause">
                      <referenceFrom>1</referenceFrom>
                    </locality>
                    ISO 7301:2011, Clause 1
                  </fmt-eref>
                </semx>
              </p>
            </attribution>
          </quote>
        XML

        # Same content but attribution compressed to single line
        xml2 = <<~XML
          <quote id="_">
            <p id="_">This International Standard gives the minimum specifications for rice (<em>Oryza sativa</em> L.) which is subject to international trade.</p>
            <attribution><p>— <semx element="author" source="_">ISO</semx>, <semx element="source" source="_"><fmt-eref type="inline" bibitemid="ISO7301" citeas="ISO 7301:2011"><locality type="clause"><referenceFrom>1</referenceFrom></locality>ISO 7301:2011, Clause 1</fmt-eref></semx></p></attribution>
          </quote>
        XML

        result = formatter.format(xml1, xml2)

        # Should show ALL the deleted lines from the multi-line attribution content
        # The expansion algorithm finds parent elements, showing complete element boundaries
        # Note: Spaces in diff output are visualized as ░ characters
        expect(result).to include("<p>")
        expect(result).to include("—")
        expect(result).to include("<semx")
        expect(result).to include('element="author"')
        expect(result).to include(",")
        expect(result).to include('element="source"')
        expect(result).to include("<fmt-eref")
        expect(result).to include("<locality")
        expect(result).to include("<referenceFrom>")
        expect(result).to include("ISO")
        expect(result).to include("7301:2011")
        expect(result).to include("</fmt-eref>")
        expect(result).to include("</semx>")
        expect(result).to include("</p>")

        # Count deletion markers to ensure many lines are shown as deleted
        deletion_count = result.scan(/\|\s*-\s*\|/).length
        # The multi-line attribution content has 8+ lines
        # Most or all should be marked as deleted
        expect(deletion_count).to be >= 8
      end

      it "shows all added lines when single line expands to multiple lines" do
        # Reverse case: single line expands to multiple lines
        xml1 = <<~XML
          <quote id="_">
            <p id="_">Text content here.</p>
            <attribution><p>— ISO, ISO 7301:2011</p></attribution>
          </quote>
        XML

        xml2 = <<~XML
          <quote id="_">
            <p id="_">Text content here.</p>
            <attribution>
              <p>
                —
                ISO
                ,
                ISO 7301:2011
              </p>
            </attribution>
          </quote>
        XML

        result = formatter.format(xml1, xml2)

        # Should show ALL the added lines from the expanded attribution
        # Note: Spaces in diff output are visualized as ░ characters
        expect(result).to include("<attribution>")
        expect(result).to include("<p>")
        expect(result).to include("—")
        expect(result).to include("ISO")
        expect(result).to include(",")
        expect(result).to include("ISO░7301:2011")
        expect(result).to include("</p>")
        expect(result).to include("</attribution>")

        # Count addition markers - look for the pattern "   |   N+ |"
        addition_count = result.scan(/\|\s+\d+\+\s*\|/).length
        # The expanded attribution has approximately 8 lines
        # All should be marked as added
        expect(addition_count).to be >= 6
      end
    end

    context "with multiple grouped diffs" do
      it "shows differences for both sections" do
        xml1 = <<~XML
          <doc>
            <section id="A">
              <p>First paragraph with some content.</p>
            </section>
            <section id="B">
              <p>Second paragraph with more content.</p>
            </section>
          </doc>
        XML

        xml2 = <<~XML
          <doc>
            <section id="A"><p>First paragraph with changed content.</p></section>
            <section id="B"><p>Second paragraph with different content.</p></section>
          </doc>
        XML

        result = formatter.format(xml1, xml2)

        # Should show both sections with their differences
        expect(result).to include("section")
        expect(result).to include("paragraph")
        expect(result).not_to be_empty
      end
    end

    context "with colorization" do
      it "produces output without ANSI codes when color is disabled" do
        xml1 = <<~XML
          <doc>
            <section id="A">
              <p>old text</p>
            </section>
          </doc>
        XML

        xml2 = <<~XML
          <doc>
            <section id="A">
              <p>new text</p>
            </section>
          </doc>
        XML

        result = formatter.format(xml1, xml2)
        # Should not contain ANSI escape sequences
        expect(result).not_to match(/\e\[/)
        # Should have diff output
        expect(result).to include("old")
        expect(result).to include("new")
      end
    end

    context "with DOM-guided element matching" do
      it "matches elements by structure and attributes" do
        xml1 = <<~XML
          <doc>
            <section id="intro">
              <p>Introduction text</p>
            </section>
          </doc>
        XML

        xml2 = <<~XML
          <doc>
            <section id="intro">
              <p>Updated introduction text</p>
            </section>
          </doc>
        XML

        result = formatter.format(xml1, xml2)

        # Should show the changed text within matched elements
        expect(result).to include("Introduction")
        expect(result).to include("Updated")
      end

      it "identifies deleted elements" do
        xml1 = <<~XML
          <doc>
            <section id="A"><p>Content A</p></section>
            <section id="B"><p>Content B</p></section>
          </doc>
        XML

        xml2 = <<~XML
          <doc>
            <section id="A"><p>Content A</p></section>
          </doc>
        XML

        result = formatter.format(xml1, xml2)

        # Should show the deleted section
        # Note: Spaces in diff output are visualized as ░ characters
        expect(result).to include('id="B"')
        expect(result).to include("Content░B")
      end

      it "identifies inserted elements" do
        xml1 = <<~XML
          <doc>
            <section id="A"><p>Content A</p></section>
          </doc>
        XML

        xml2 = <<~XML
          <doc>
            <section id="A"><p>Content A</p></section>
            <section id="B"><p>Content B</p></section>
          </doc>
        XML

        result = formatter.format(xml1, xml2)

        # Should show the added section
        # Note: Spaces in diff output are visualized as ░ characters
        expect(result).to include('id="B"')
        expect(result).to include("Content░B")
      end
    end
  end
end
