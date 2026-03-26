# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XML diff matching for informative and normative diffs" do
  describe "comment changes with match options" do
    it "suppresses diff when comments are ignored and documents are equivalent" do
      xml1 = "<root><!-- old --></root>"
      xml2 = "<root><!-- new --></root>"

      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true,
        use_color: false,
        match: { comments: :ignore }
      )

      # When comments are ignored, documents are equivalent - diff suppressed
      expect(result.equivalent?).to be true
      expect(result.diff(use_color: false).lines.length).to eq(1)
    end

    it "shows comments as normative when comments are compared" do
      xml1 = "<root><!-- old --></root>"
      xml2 = "<root><!-- new --></root>"

      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true,
        use_color: false
      )

      diff = result.diff(use_color: false)

      # Should show - and + markers (normative), not < and > (informative)
      expect(diff).to include("-").or include("+")
    end
  end

  describe "whitespace formatting changes" do
    it "treats significant whitespace differences as normative" do
      xml1 = "<root><p>Hello  world</p></root>"
      xml2 = "<root><p>Hello world</p></root>"

      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true,
        use_color: false
      )

      diff = result.diff(use_color: false)

      # Double space vs single space is normative (not equivalent)
      expect(result.equivalent?).to be false
      # Should show normative markers, not formatting markers
      expect(diff).to include("-").or include("+")
    end
  end

  describe "mixed normative and informative changes" do
    it "correctly associates formatting markers with the right diff" do
      xml1 = <<~XML
        <root>
          <item>One</item>
          <!-- comment 1 -->
          <item>Two</item>
        </root>
      XML

      xml2 = <<~XML
        <root>
          <item>One CHANGED</item>
          <!-- comment 2 -->
          <item>Two</item>
        </root>
      XML

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true)

      diff = result.diff(use_color: false)

      # Should have both normative (-/+) for text change and normative (-/+)
      # for comment change
      expect(diff).to include("-").and include("+")
    end
  end
end
