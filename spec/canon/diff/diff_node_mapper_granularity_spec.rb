# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Diff::DiffNodeMapper do
  describe "line-level semantic filtering" do
    it "only shows lines with actual semantic differences, not cosmetic ones" do
      # More realistic example: large parent element with:
      # - cosmetic attribute order diff on opening tag
      # - multiple unchanged child elements
      # - ONE semantic child element name diff
      xml1 = <<~XML
        <bibitem id="ref1" type="standard" status="published" language="en">
          <title>Document Title</title>
          <contributor>
            <person>Author Name</person>
          </contributor>
          <date type="published">2024</date>
          <formattedref>ISO 8601</formattedref>
          <edition>1</edition>
        </bibitem>
      XML

      xml2 = <<~XML
        <bibitem type="standard" id="ref1" language="en" status="published">
          <title>Document Title</title>
          <contributor>
            <person>Author Name</person>
          </contributor>
          <date type="published">2024</date>
          <biblio-tag>ISO 8601</biblio-tag>
          <edition>1</edition>
        </bibitem>
      XML

      # Compare with spec_friendly profile (attribute order informative)
      result = Canon::Comparison::XmlComparator.equivalent?(
        xml1,
        xml2,
        verbose: true,
        match_profile: :spec_friendly,
      )

      # Map DiffNodes to DiffLines
      diff_lines = described_class.map(
        result.differences,
        result.preprocessed_strings[0],
        result.preprocessed_strings[1],
      )

      # Filter to normative lines only (spec_friendly filters informative)
      normative_lines = diff_lines.select(&:normative?)

      # Should only have the semantic difference (element name change)
      # NOT the cosmetic attribute order difference
      expect(normative_lines.length).to be > 0

      # The normative lines should be about element name difference
      normative_content = normative_lines.map(&:content).join("\n")
      expect(normative_content).to include("formattedref").or include("biblio-tag")

      # Should NOT show all lines of bibitem element
      # (this is the bug we're fixing)
      expect(normative_lines.length).to be < 6
    end

    it "shows context around semantic differences" do
      xml1 = <<~XML
        <root>
          <item1>unchanged</item1>
          <item2>unchanged</item2>
          <bibitem id="ref1">
            <formattedref>ISO 8601</formattedref>
          </bibitem>
          <item3>unchanged</item3>
          <item4>unchanged</item4>
        </root>
      XML

      xml2 = <<~XML
        <root>
          <item1>unchanged</item1>
          <item2>unchanged</item2>
          <bibitem id="ref1">
            <biblio-tag>ISO 8601</biblio-tag>
          </bibitem>
          <item3>unchanged</item3>
          <item4>unchanged</item4>
        </root>
      XML

      result = Canon::Comparison::XmlComparator.equivalent?(
        xml1,
        xml2,
        verbose: true,
        match_profile: :spec_friendly,
      )

      # Map DiffNodes to DiffLines
      diff_lines = described_class.map(
        result.differences,
        result.preprocessed_strings[0],
        result.preprocessed_strings[1],
      )

      # Should have the semantic diff line
      normative_lines = diff_lines.select(&:normative?)
      expect(normative_lines).not_to be_empty

      # All lines include context
      all_lines_content = diff_lines.map(&:content).join("\n")
      expect(all_lines_content).to include("item2")
      expect(all_lines_content).to include("item3")
    end

    it "handles element name differences with attribute order cosmetic diffs" do
      xml1 = <<~XML
        <parent attr1="value1" attr2="value2">
          <child1>text</child1>
          <old-element id="a" class="b">content</old-element>
        </parent>
      XML

      xml2 = <<~XML
        <parent attr2="value2" attr1="value1">
          <child1>text</child1>
          <new-element class="b" id="a">content</new-element>
        </parent>
      XML

      result = Canon::Comparison::XmlComparator.equivalent?(
        xml1,
        xml2,
        verbose: true,
        match_profile: :spec_friendly,
      )

      # Map DiffNodes to DiffLines
      diff_lines = described_class.map(
        result.differences,
        result.preprocessed_strings[0],
        result.preprocessed_strings[1],
      )

      normative_lines = diff_lines.select(&:normative?)

      # Should show the element name difference
      normative_content = normative_lines.map(&:content).join("\n")
      expect(normative_content).to include("old-element").or include("new-element")

      # Should NOT show parent attribute order diff (cosmetic)
      # Should NOT show child attribute order diff (cosmetic)
      # Element name changes create 2 DiffNodes (deleted + inserted)
      expect(normative_lines.length).to eq(2)
    end
  end
end
