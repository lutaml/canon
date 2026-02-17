# frozen_string_literal: true

require "spec_helper"
require "canon/comparison"
require "canon/rspec_matchers"

# Attribute dimensions used for filtering differences
ATTRIBUTE_DIMS = %i[attribute_presence attribute_values].freeze

RSpec.describe "HTML4 Table Class Attribute Comparison Bug" do
  # Bug: When comparing two HTML snippets where only the table class attribute differs
  # (e.g., MsoISOTableBig vs MsoISOTable), the comparison incorrectly reports a
  # text_content difference at the body level instead of an attribute difference.
  #
  # The 4 layers that need to work correctly:
  # Layer 1: Preprocessing (none, c14n, normalize, format, rendered)
  # Layer 2: Algorithm Selection (dom, semantic)
  # Layer 3: Match Options (dimensions and profiles)
  # Layer 4: Diff Formatting (by_line, by_object)

  let(:html_with_big_table_class) do
    <<~HTML
      <body>
      <style></style>
      <div class="WordSection1"><p> </p></div>
      <p class="section-break"><br clear="all" class="section"/></p>
      <div class="WordSection2">
      <p class="page-break"><br clear="all" style="mso-special-character:line-break;page-break-before:always"/></p>
      <div>
      <h1 class="ForewordTitle">Foreword</h1>
      <p class="TableTitle" style="text-align:center;">Repeatability and reproducibility of<i>husked</i>rice yield</p>
      <div align="center" class="table_container"><table id="tableD-1" class="MsoISOTableBig" style="mso-table-anchor-horizontal:column;mso-table-overlap:never;border-spacing:0;border-width:1px;page-break-after: avoid;page-break-inside: avoid;" title="tool tip" summary="long desc" width="70%"><thead><tr>
      <td style="border-top:solid windowtext 1.5pt;mso-border-top-alt:solid windowtext 1.5pt;border-bottom:solid windowtext 1.5pt;mso-border-bottom-alt:solid windowtext 1.5pt;page-break-after:avoid;">Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description</td>
      <td style="border-top:solid windowtext 1.5pt;mso-border-top-alt:solid windowtext 1.5pt;border-bottom:solid windowtext 1.5pt;mso-border-bottom-alt:solid windowtext 1.5pt;page-break-after:avoid;">Rice sample</td>
      </tr></thead></table></div>
      </div>
      <p> </p>
      </div>
      <p class="section-break"><br clear="all" class="section"/></p>
      <div class="WordSection3"></div>
      </body>
    HTML
  end

  let(:html_with_normal_table_class) do
    <<~HTML
      <body>
      <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
      <style></style>
      <div class="WordSection1"><p> </p></div>
      <p class="section-break"><br clear="all" class="section"/></p>
      <div class="WordSection2">
      <p class="page-break"><br clear="all" style="mso-special-character:line-break;page-break-before:always"/></p>
      <div>
      <h1 class="ForewordTitle">Foreword</h1>
      <p class="TableTitle" style="text-align:center;">Repeatability and reproducibility of<i>husked</i>rice yield</p>
      <div align="center" class="table_container"><table id="tableD-1" class="MsoISOTable" style="mso-table-anchor-horizontal:column;mso-table-overlap:never;border-spacing:0;border-width:1px;page-break-after: avoid;page-break-inside: avoid;" title="tool tip" summary="long desc" width="70%"><thead><tr>
      <td style="border-top:solid windowtext 1.5pt;mso-border-top-alt:solid windowtext 1.5pt;border-bottom:solid windowtext 1.5pt;mso-border-bottom-alt:solid windowtext 1.5pt;page-break-after:avoid;">Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description Description</td>
      <td style="border-top:solid windowtext 1.5pt;mso-border-top-alt:solid windowtext 1.5pt;border-bottom:solid windowtext 1.5pt;mso-border-bottom-alt:solid windowtext 1.5pt;page-break-after:avoid;">Rice sample</td>
      </tr></thead></table></div>
      </div>
      <p> </p>
      </div>
      <p class="section-break"><br clear="all" class="section"/></p>
      <div class="WordSection3"></div>
      </body>
    HTML
  end

  # Layer 1: Preprocessing modes
  describe "Layer 1: Preprocessing" do
    context "with :none preprocessing" do
      it "correctly identifies attribute difference, not text_content difference" do
        result = Canon::Comparison.equivalent?(
          html_with_big_table_class,
          html_with_normal_table_class,
          preprocessing: :none,
          verbose: true,
        )

        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result).not_to be_equivalent

        # The difference should be in attribute_presence or attribute_values, not text_content
        text_content_diffs = result.differences.select do |d|
          d.dimension == :text_content
        end
        attribute_diffs = result.differences.select do |d|
          ATTRIBUTE_DIMS.include?(d.dimension)
        end

        # This is the bug: currently text_content diffs are reported instead of attribute diffs
        # After fix: attribute_diffs should not be empty
        # For now, let's document the bug behavior
        pending "Bug: attribute differences are not being detected"
        expect(attribute_diffs).not_to be_empty
        expect(text_content_diffs).to be_empty
      end
    end

    context "with :rendered preprocessing" do
      it "correctly identifies attribute difference with rendered preprocessing" do
        result = Canon::Comparison.equivalent?(
          html_with_big_table_class,
          html_with_normal_table_class,
          preprocessing: :rendered,
          verbose: true,
        )

        expect(result).not_to be_equivalent

        attribute_diffs = result.differences.select do |d|
          ATTRIBUTE_DIMS.include?(d.dimension)
        end

        pending "Bug: attribute differences are not being detected"
        expect(attribute_diffs).not_to be_empty
      end
    end
  end

  # Layer 2: Algorithm Selection
  describe "Layer 2: Algorithm Selection" do
    context "with DOM DIFF algorithm (default)" do
      it "correctly reports attribute differences" do
        result = Canon::Comparison.equivalent?(
          html_with_big_table_class,
          html_with_normal_table_class,
          diff_algorithm: :dom,
          verbose: true,
        )

        expect(result).not_to be_equivalent
        expect(result.algorithm).to eq(:dom)

        attribute_diffs = result.differences.select do |d|
          ATTRIBUTE_DIMS.include?(d.dimension)
        end

        pending "Bug: attribute differences are not being detected"
        expect(attribute_diffs).not_to be_empty
      end
    end

    context "with semantic tree diff algorithm" do
      it "correctly reports attribute differences" do
        result = Canon::Comparison.equivalent?(
          html_with_big_table_class,
          html_with_normal_table_class,
          diff_algorithm: :semantic,
          verbose: true,
        )

        expect(result).not_to be_equivalent
        expect(result.algorithm).to eq(:semantic)

        attribute_diffs = result.differences.select do |d|
          ATTRIBUTE_DIMS.include?(d.dimension)
        end

        expect(attribute_diffs).not_to be_empty
      end
    end
  end

  # Layer 3: Match Options (dimensions and profiles)
  describe "Layer 3: Match Options" do
    context "with strict attribute_presence" do
      it "detects class attribute difference" do
        result = Canon::Comparison.equivalent?(
          html_with_big_table_class,
          html_with_normal_table_class,
          match: { attribute_presence: :strict },
          verbose: true,
        )

        expect(result).not_to be_equivalent

        # Find the attribute difference
        class_diff = result.differences.find do |d|
          d.dimension == :attribute_presence &&
            d.reason&.include?("class")
        end

        pending "Bug: class attribute difference is not being detected"
        expect(class_diff).not_to be_nil
      end
    end

    context "with rendered profile" do
      it "correctly handles attribute differences in rendered mode" do
        result = Canon::Comparison.equivalent?(
          html_with_big_table_class,
          html_with_normal_table_class,
          match_profile: :rendered,
          verbose: true,
        )

        expect(result).not_to be_equivalent

        attribute_diffs = result.differences.select do |d|
          ATTRIBUTE_DIMS.include?(d.dimension)
        end

        expect(attribute_diffs).not_to be_empty
      end
    end

    context "with html4 profile" do
      it "correctly handles HTML4-specific attribute comparison" do
        result = Canon::Comparison.equivalent?(
          html_with_big_table_class,
          html_with_normal_table_class,
          match_profile: :html4,
          verbose: true,
        )

        expect(result).not_to be_equivalent

        attribute_diffs = result.differences.select do |d|
          ATTRIBUTE_DIMS.include?(d.dimension)
        end

        expect(attribute_diffs).not_to be_empty
      end
    end
  end

  # Layer 4: Diff Formatting
  describe "Layer 4: Diff Formatting" do
    context "with by_line formatter" do
      it "formats attribute differences correctly" do
        result = Canon::Comparison.equivalent?(
          html_with_big_table_class,
          html_with_normal_table_class,
          verbose: true,
        )

        formatter = Canon::DiffFormatter.new(
          mode: :by_line,
          use_color: false,
          context_lines: 3,
        )

        output = formatter.format_comparison_result(
          result,
          html_with_big_table_class,
          html_with_normal_table_class,
        )

        pending "Bug: attribute differences should be shown in formatted output"
        # After fix, the output should show the class attribute difference
        expect(output).to include("class")
        expect(output).to include("MsoISOTableBig")
        expect(output).to include("MsoISOTable")
      end
    end

    context "with by_object formatter" do
      it "formats attribute differences in tree view" do
        result = Canon::Comparison.equivalent?(
          html_with_big_table_class,
          html_with_normal_table_class,
          verbose: true,
        )

        formatter = Canon::DiffFormatter.new(
          mode: :by_object,
          use_color: false,
        )

        output = formatter.format_comparison_result(
          result,
          html_with_big_table_class,
          html_with_normal_table_class,
        )

        pending "Bug: attribute differences should be shown in tree view"
        # After fix, the tree view should show attribute differences
        expect(output).to include("attribute")
      end
    end
  end

  # RSpec matcher integration
  describe "RSpec Matchers" do
    it "correctly uses be_html4_equivalent_to matcher" do
      expect(html_with_normal_table_class).not_to be_html4_equivalent_to(html_with_big_table_class)

      # After fix, the failure message should clearly indicate attribute difference
      # expect {
      #   expect(html_with_normal_table_class).to be_html4_equivalent_to(html_with_big_table_class)
      # }.to raise_error(/class.*attribute/i)
    end
  end

  # Minimal test case to isolate the bug
  describe "Minimal reproduction" do
    let(:simple_html_big) do
      '<table class="MsoISOTableBig"><td>Text</td></table>'
    end
    let(:simple_html_normal) do
      '<table class="MsoISOTable"><td>Text</td></table>'
    end
    let(:simple_html_big_with_body) do
      '<body><table class="MsoISOTableBig"><td>Text</td></table></body>'
    end
    let(:simple_html_normal_with_body) do
      '<body><table class="MsoISOTable"><td>Text</td></table></body>'
    end

    it "detects attribute difference in simple case (without body)" do
      result = Canon::Comparison.equivalent?(
        simple_html_big,
        simple_html_normal,
        verbose: true,
      )

      expect(result).not_to be_equivalent

      attribute_diffs = result.differences.select do |d|
        ATTRIBUTE_DIMS.include?(d.dimension)
      end

      expect(attribute_diffs).not_to be_empty
      expect(attribute_diffs.first.dimension).to eq(:attribute_values)
    end

    it "detects attribute difference with body wrapper" do
      result = Canon::Comparison.equivalent?(
        simple_html_big_with_body,
        simple_html_normal_with_body,
        verbose: true,
      )

      expect(result).not_to be_equivalent

      attribute_diffs = result.differences.select do |d|
        ATTRIBUTE_DIMS.include?(d.dimension)
      end

      expect(attribute_diffs).not_to be_empty
      expect(attribute_diffs.first.dimension).to eq(:attribute_values)
    end

    it "detects attribute difference when only attribute values differ (same structure)" do
      result = Canon::Comparison.equivalent?(
        simple_html_big_with_body,
        simple_html_normal_with_body,
        diff_algorithm: :semantic,
        verbose: true,
      )

      expect(result).not_to be_equivalent

      attribute_diffs = result.differences.select do |d|
        ATTRIBUTE_DIMS.include?(d.dimension)
      end

      expect(attribute_diffs).not_to be_empty
      expect(attribute_diffs.first.dimension).to eq(:attribute_values)
    end
  end

  # Structural comparison bug - DOM DIFF position-based comparison
  describe "Structural comparison bug: insertion causes misalignment" do
    # Bug: When comparing two trees where one has an insertion, DOM DIFF
    # compares position-by-position and gets misaligned.
    #
    # Example:
    #   Tree1: <hi><ho he='1'>hello</ho></hi>
    #   Tree2: <hi><hd>hi</hd><ho he='2'>hello</ho></hi>
    #
    # DOM DIFF should recognize <hd>hi</hd> as an INSERTION and still
    # match <ho he='1'>hello</ho> with <ho he='2'>hello</ho> (as an
    # UPDATE for the attribute value).
    #
    # Instead, it compares:
    #   Position 0: <hi> = <hi> ✓
    #   Position 1: <ho he='1'> ≠ <hd> ✗ (WRONG - should recognize insertion)
    #   Position 2: hello ≠ <ho he='2'> ✗ (WRONG - shifted comparison)
    #
    # This causes cascading false differences.

    context "with simple insertion case" do
      let(:html_without_insertion) { '<hi><ho he="1">hello</ho></hi>' }
      let(:html_with_insertion) { '<hi><hd>hi</hd><ho he="2">hello</ho></hi>' }

      it "DOM DIFF recognizes insertion and matches subsequent elements" do
        result = Canon::Comparison.equivalent?(
          html_without_insertion,
          html_with_insertion,
          diff_algorithm: :dom,
          verbose: true,
        )

        expect(result).not_to be_equivalent

        # We expect:
        # 1. One INSERT difference for <hd>hi</hd> (node1 is nil)
        # 2. One UPDATE difference for attribute he='1' vs he='2'
        # NOT cascading position mismatches
        insert_diffs = result.differences.select do |d|
          d.node1.nil? && !d.node2.nil?
        end
        delete_diffs = result.differences.select do |d|
          !d.node1.nil? && d.node2.nil?
        end
        attribute_diffs = result.differences.select do |d|
          ATTRIBUTE_DIMS.include?(d.dimension)
        end

        expect(insert_diffs.size).to eq(1)
        expect(delete_diffs.size).to eq(0)
        expect(attribute_diffs.size).to eq(1)
      end

      it "semantic DIFF recognizes insertion and matches subsequent elements" do
        result = Canon::Comparison.equivalent?(
          html_without_insertion,
          html_with_insertion,
          diff_algorithm: :semantic,
          verbose: true,
        )

        expect(result).not_to be_equivalent

        # Semantic diff should handle this better
        # It should recognize <hd> as INSERT and <ho> as UPDATE
        # We check the dimensions to infer the operation type
        element_diffs = result.differences.select do |d|
          d.dimension == :element_structure
        end
        attribute_diffs = result.differences.select do |d|
          ATTRIBUTE_DIMS.include?(d.dimension)
        end

        pending "Bug: Semantic DIFF also struggles with insertions"
        # Should have 1 element_structure (insert) and 1 attribute diff
        expect(element_diffs.size).to eq(1)
        expect(attribute_diffs.size).to eq(1)
      end
    end

    context "with meta tag insertion (isodoc case)" do
      # This is a simplified case - the actual isodoc case uses full HTML documents
      # where the meta tag is filtered out during parsing.
      # For HTML fragments (without <html> tag), the meta tag is NOT filtered out.

      let(:html_without_meta) do
        <<~HTML
          <body>
          <style></style>
          <div class="WordSection1"><p> </p></div>
          </body>
        HTML
      end

      let(:html_with_meta) do
        <<~HTML
          <body>
          <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
          <style></style>
          <div class="WordSection1"><p> </p></div>
          </body>
        HTML
      end

      it "DOM DIFF recognizes meta as insertion and matches subsequent elements" do
        result = Canon::Comparison.equivalent?(
          html_without_meta,
          html_with_meta,
          diff_algorithm: :dom,
          verbose: true,
        )

        # For HTML fragments, the meta tag is NOT filtered out
        # (filtering only applies to full HTML documents with <html> tag)
        # So the fragments should NOT be equivalent
        expect(result).not_to be_equivalent

        # Currently, DOM DIFF compares elements position-by-position when signatures don't match
        # This causes style to be compared with meta, which is incorrect.
        # TODO: Improve semantic matching to recognize insertions when signatures don't match
        pending "TODO: Improve semantic matching for incompatible nodes (e.g., style vs meta)"

        # We expect the meta tag to be reported as an insertion (node1 is nil)
        # and the rest of the elements to be matched correctly
        insert_diffs = result.differences.select do |d|
          d.node1.nil? && !d.node2.nil?
        end
        result.differences.select { |d| !d.node1.nil? && d.node2.nil? }

        # The meta tag should be an insertion
        expect(insert_diffs.size).to be >= 1
        # Check that the inserted element is a meta tag
        meta_insert = insert_diffs.find do |d|
          d.node2.respond_to?(:name) && d.node2.name == "meta"
        end
        expect(meta_insert).not_to be_nil
      end
    end
  end
end
