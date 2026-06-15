# frozen_string_literal: true

require "spec_helper"
require "canon/diff_formatter"

# Issue #130: Canon's XML parser silently drops content on FATAL libxml
# errors (e.g. duplicate-attribute violations).  The diff layer then
# reports against a parse tree that no longer represents the input,
# producing reports that read as nonsense to the user.  This spec
# exercises the parse-error surface that propagates libxml's error list
# all the way to ComparisonResult and the diff banner.
RSpec.describe "parse error surface (issue #130)" do
  let(:formatter) { Canon::DiffFormatter.new(use_color: false) }

  describe "duplicate xml:lang in XML mode" do
    let(:expected) do
      '<body lang="en" xml:lang="en"><div class="x">x</div></body>'
    end
    let(:received) do
      '<body lang="en" xml:lang="en" xml:lang="en"><div class="x">x</div></body>'
    end
    let(:result) do
      Canon::Comparison.equivalent?(expected, received,
                                    format: :xml, verbose: true)
    end

    it "surfaces the libxml FATAL on the received side" do
      expect(result.parse_errors_received).not_to be_empty
      expect(result.parse_errors_received.join("\n"))
        .to include("Attribute xml:lang redefined")
    end

    it "leaves the expected side's parse_errors empty" do
      expect(result.parse_errors_expected).to eq([])
    end

    it "answers parse_errors? truthfully" do
      expect(result.parse_errors?).to be true
    end

    it "renders a banner at the top of the diff report" do
      output = formatter.format_comparison_result(result, expected, received)
      banner_line = output.lines.find { |l| l.include?("⚠️  PARSE ERRORS") }
      expect(banner_line).not_to be_nil
      expect(output).to include("Received side:")
      expect(output).to include("Attribute xml:lang redefined")
      expect(output)
        .to include("describes the parsed tree, not the input")
    end

    it "renders the banner before the semantic diff section" do
      output = formatter.format_comparison_result(result, expected, received)
      banner_idx = output.index("PARSE ERRORS")
      report_idx = output.index("SEMANTIC DIFF REPORT")
      expect(banner_idx).not_to be_nil
      expect(report_idx).not_to be_nil
      expect(banner_idx).to be < report_idx
    end
  end

  describe "valid XML on both sides" do
    let(:expected) { "<root><a>1</a><b>2</b></root>" }
    let(:received) { "<root><a>1</a><b>3</b></root>" }
    let(:result) do
      Canon::Comparison.equivalent?(expected, received,
                                    format: :xml, verbose: true)
    end

    it "leaves both parse_errors arrays empty" do
      expect(result.parse_errors_expected).to eq([])
      expect(result.parse_errors_received).to eq([])
    end

    it "answers parse_errors? false" do
      expect(result.parse_errors?).to be false
    end

    it "does not render a banner" do
      output = formatter.format_comparison_result(result, expected, received)
      expect(output).not_to include("PARSE ERRORS")
    end
  end

  describe "duplicate attribute in HTML5 mode (no error to surface)" do
    let(:expected) do
      '<body lang="en" xml:lang="en"><div>x</div></body>'
    end
    let(:received) do
      '<body lang="en" xml:lang="en" xml:lang="en"><div>x</div></body>'
    end

    it "does not record a parse error (HTML5 dedupes silently per spec)" do
      result = Canon::Comparison.equivalent?(expected, received,
                                             format: :html5, verbose: true)
      expect(result.parse_errors_expected).to eq([])
      expect(result.parse_errors_received).to eq([])
      expect(result.parse_errors?).to be false
    end
  end
end
