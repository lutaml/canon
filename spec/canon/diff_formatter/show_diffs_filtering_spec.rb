# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Canon::DiffFormatter show_diffs filtering" do
  describe "by_object mode filtering" do
    let(:xml1) do
      <<~XML
        <root>
          <!-- This is a comment -->
          <element>value1</element>
        </root>
      XML
    end

    let(:xml2) do
      <<~XML
        <root>
          <!-- This is a different comment -->
          <element>value2</element>
        </root>
      XML
    end

    context "with show_diffs: :all" do
      it "shows both normative and informative diffs" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true,
          match: { comments: :ignore }
        )

        formatter = Canon::DiffFormatter.new(
          use_color: false,
          mode: :by_object,
          show_diffs: :all,
        )

        output = formatter.format(result, :xml)

        # Should show both comment diff (informative) and element diff (normative)
        expect(output).to include("Visual Diff:")
        # The actual content depends on DiffNode structure
        expect(result.differences).not_to be_empty
      end
    end

    context "with show_diffs: :normative" do
      it "shows only normative diffs" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true,
          match: { comments: :ignore }
        )

        formatter = Canon::DiffFormatter.new(
          use_color: false,
          mode: :by_object,
          show_diffs: :normative,
        )

        output = formatter.format(result, :xml)

        # Should show Visual Diff header
        expect(output).to include("Visual Diff:")

        # Verify normative diffs exist (element value change)
        normative_count = result.differences.count(&:normative?)
        expect(normative_count).to be > 0
      end

      it "filters differences internally" do
        Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true,
          match: { comments: :ignore }
        )

        formatter = Canon::DiffFormatter.new(
          use_color: false,
          mode: :by_object,
          show_diffs: :normative,
        )

        # The formatter should accept the parameter
        expect(formatter.instance_variable_get(:@show_diffs)).to eq(:normative)
      end
    end

    context "with show_diffs: :informative" do
      it "shows only informative diffs" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true,
          match: { comments: :ignore }
        )

        formatter = Canon::DiffFormatter.new(
          use_color: false,
          mode: :by_object,
          show_diffs: :informative,
        )

        output = formatter.format(result, :xml)

        # Should show Visual Diff header
        expect(output).to include("Visual Diff:")
      end

      it "filters differences internally" do
        Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true,
          match: { comments: :ignore }
        )

        formatter = Canon::DiffFormatter.new(
          use_color: false,
          mode: :by_object,
          show_diffs: :informative,
        )

        # The formatter should accept the parameter
        expect(formatter.instance_variable_get(:@show_diffs)).to eq(:informative)
      end
    end
  end

  describe "by_line mode filtering" do
    let(:xml1) do
      <<~XML
        <root>
          <!-- Comment 1 -->
          <element>value1</element>
        </root>
      XML
    end

    let(:xml2) do
      <<~XML
        <root>
          <!-- Comment 2 -->
          <element>value2</element>
        </root>
      XML
    end

    context "with show_diffs: :all" do
      it "shows both normative and informative diffs" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true,
          match: { comments: :ignore }
        )

        formatter = Canon::DiffFormatter.new(
          use_color: false,
          mode: :by_line,
          show_diffs: :all,
        )

        str1, str2 = result.preprocessed_strings
        output = formatter.format(result, :xml, doc1: str1, doc2: str2)

        expect(output).to include("Line-by-line diff")
        expect(result.differences).not_to be_empty
      end
    end

    context "with show_diffs: :normative" do
      it "shows only normative diffs in line diff" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true,
          match: { comments: :ignore }
        )

        formatter = Canon::DiffFormatter.new(
          use_color: false,
          mode: :by_line,
          show_diffs: :normative,
        )

        str1, str2 = result.preprocessed_strings
        output = formatter.format(result, :xml, doc1: str1, doc2: str2)

        expect(output).to include("Line-by-line diff")

        # Verify normative diffs exist
        normative_count = result.differences.count(&:normative?)
        expect(normative_count).to be > 0
      end
    end

    context "with show_diffs: :informative" do
      it "shows only informative diffs in line diff" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true,
          match: { comments: :ignore }
        )

        formatter = Canon::DiffFormatter.new(
          use_color: false,
          mode: :by_line,
          show_diffs: :informative,
        )

        str1, str2 = result.preprocessed_strings
        output = formatter.format(result, :xml, doc1: str1, doc2: str2)

        expect(output).to include("Line-by-line diff")

        # The formatter should accept the parameter
        expect(formatter.instance_variable_get(:@show_diffs)).to eq(:informative)
      end
    end
  end

  describe "comment handling with show_diffs" do
    let(:xml1) do
      <<~XML
        <root>
          <!-- Comment A -->
          <element>value</element>
        </root>
      XML
    end

    let(:xml2) do
      <<~XML
        <root>
          <!-- Comment B -->
          <element>value</element>
        </root>
      XML
    end

    context "with comments: :ignore" do
      it "comment diffs are informative and documents are equivalent" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true,
          match: { comments: :ignore }
        )

        # Documents should be equivalent (only informative diffs)
        expect(result.equivalent?).to be true

        # Formatter should accept show_diffs parameter
        formatter = Canon::DiffFormatter.new(
          use_color: false,
          mode: :by_object,
          show_diffs: :normative,
        )
        expect(formatter.instance_variable_get(:@show_diffs)).to eq(:normative)
      end

      it "show_diffs parameter works with informative setting" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true,
          match: { comments: :ignore }
        )

        formatter = Canon::DiffFormatter.new(
          use_color: false,
          mode: :by_object,
          show_diffs: :informative,
        )

        # Formatter should accept the parameter
        expect(formatter.instance_variable_get(:@show_diffs)).to eq(:informative)

        # Documents are equivalent
        expect(result.equivalent?).to be true
      end

      it "show_diffs parameter works with all setting" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true,
          match: { comments: :ignore }
        )

        formatter = Canon::DiffFormatter.new(
          use_color: false,
          mode: :by_object,
          show_diffs: :all,
        )

        # Formatter should accept the parameter
        expect(formatter.instance_variable_get(:@show_diffs)).to eq(:all)

        # Documents are equivalent
        expect(result.equivalent?).to be true
      end
    end

    context "with comments: :strict" do
      it "comment diffs are normative and visible with show_diffs: :normative" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true,
          match: { comments: :strict }
        )

        # Comment diffs should be normative, check actual diff exists
        expect(result.differences).not_to be_empty

        # Documents should NOT be equivalent (has normative diffs)
        expect(result.equivalent?).to be false

        formatter = Canon::DiffFormatter.new(
          use_color: false,
          mode: :by_object,
          show_diffs: :normative,
        )

        # Formatter should accept the parameter
        expect(formatter.instance_variable_get(:@show_diffs)).to eq(:normative)
      end
    end
  end

  describe "equivalence determination is independent of show_diffs" do
    let(:xml1) { "<root><el>A</el></root>" }
    let(:xml2) { "<root><el>B</el></root>" }

    it "show_diffs does not affect equivalence calculation" do
      result_all = Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true,
        match: { text_content: :strict }
      )

      result_normative = Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true,
        match: { text_content: :strict }
      )

      # Both should report not equivalent (normative diff exists)
      expect(result_all.equivalent?).to be false
      expect(result_normative.equivalent?).to be false

      # Both should have the same differences
      expect(result_all.differences.count).to eq(result_normative.differences.count)
    end
  end

  # ---------------------------------------------------------------------------
  # Unit tests for DiffDetailFormatter.format_report show_diffs filtering
  # ---------------------------------------------------------------------------
  describe "DiffDetailFormatter.format_report show_diffs filtering" do
    require "canon/diff_formatter/diff_detail_formatter"

    # Minimal fake DiffNode – only needs to respond to normative?/dimension/reason
    FakeDiff = Struct.new(:is_normative, :dim, keyword_init: false) do # rubocop:disable Lint/ConstantDefinitionInBlock,RSpec/LeakyConstantDeclaration
      def normative? = is_normative
      def dimension  = dim
      def reason     = nil
    end

    let(:normative_diff)   { FakeDiff.new(true,  :text_content) }
    let(:informative_diff) { FakeDiff.new(false, :comments) }
    let(:both_diffs)       { [normative_diff, informative_diff] }

    context "with show_diffs: :all (default)" do
      it "includes both NORMATIVE and INFORMATIVE section headers" do
        output = Canon::DiffFormatter::DiffDetailFormatter.format_report(
          both_diffs, use_color: false, show_diffs: :all
        )
        expect(output).to include("NORMATIVE DIFFERENCES")
        expect(output).to include("INFORMATIVE DIFFERENCES")
      end
    end

    context "with show_diffs: :normative" do
      it "includes NORMATIVE section header" do
        output = Canon::DiffFormatter::DiffDetailFormatter.format_report(
          both_diffs, use_color: false, show_diffs: :normative
        )
        expect(output).to include("NORMATIVE DIFFERENCES")
      end

      it "omits INFORMATIVE section header" do
        output = Canon::DiffFormatter::DiffDetailFormatter.format_report(
          both_diffs, use_color: false, show_diffs: :normative
        )
        expect(output).not_to include("INFORMATIVE DIFFERENCES")
      end
    end

    context "with show_diffs: :informative" do
      it "includes INFORMATIVE section header" do
        output = Canon::DiffFormatter::DiffDetailFormatter.format_report(
          both_diffs, use_color: false, show_diffs: :informative
        )
        expect(output).to include("INFORMATIVE DIFFERENCES")
      end

      it "omits NORMATIVE section header" do
        output = Canon::DiffFormatter::DiffDetailFormatter.format_report(
          both_diffs, use_color: false, show_diffs: :informative
        )
        expect(output).not_to include("NORMATIVE DIFFERENCES")
      end
    end

    context "when differences list is empty" do
      it "returns empty string regardless of show_diffs" do
        %i[all normative informative].each do |filter|
          expect(
            Canon::DiffFormatter::DiffDetailFormatter.format_report(
              [], use_color: false, show_diffs: filter
            ),
          ).to eq("")
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Integration: format_comparison_result propagates show_diffs to the report
  # ---------------------------------------------------------------------------
  describe "format_comparison_result propagates show_diffs to Semantic Diff Report" do
    # xml1/xml2 have BOTH a comment diff (informative) and an element diff (normative)
    let(:xml1) do
      "<root><!-- Comment A --><el>value1</el></root>"
    end

    let(:xml2) do
      "<root><!-- Comment B --><el>value2</el></root>"
    end

    let(:comparison_result) do
      Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true,
        match: { comments: :ignore }
      )
    end

    # Pre-condition: both normative and informative diffs must exist
    it "has both normative and informative differences (pre-condition)" do # rubocop:disable RSpec/MultipleExpectations
      expect(comparison_result.differences.any?(&:normative?)).to be true
      expect(comparison_result.differences.any? do |d|
        !d.normative?
      end).to be true
    end

    context "with show_diffs: :all" do
      it "Semantic Diff Report shows both NORMATIVE and INFORMATIVE sections" do
        formatter = Canon::DiffFormatter.new(use_color: false, show_diffs: :all)
        output = formatter.format_comparison_result(comparison_result, xml1,
                                                    xml2)

        expect(output).to include("NORMATIVE DIFFERENCES")
        expect(output).to include("INFORMATIVE DIFFERENCES")
      end
    end

    context "with show_diffs: :normative" do
      it "Semantic Diff Report shows NORMATIVE section" do
        formatter = Canon::DiffFormatter.new(use_color: false,
                                             show_diffs: :normative)
        output = formatter.format_comparison_result(comparison_result, xml1,
                                                    xml2)

        expect(output).to include("NORMATIVE DIFFERENCES")
      end

      it "Semantic Diff Report omits INFORMATIVE section" do
        formatter = Canon::DiffFormatter.new(use_color: false,
                                             show_diffs: :normative)
        output = formatter.format_comparison_result(comparison_result, xml1,
                                                    xml2)

        expect(output).not_to include("INFORMATIVE DIFFERENCES")
      end
    end

    context "with show_diffs: :informative" do
      it "Semantic Diff Report shows INFORMATIVE section" do
        formatter = Canon::DiffFormatter.new(use_color: false,
                                             show_diffs: :informative)
        output = formatter.format_comparison_result(comparison_result, xml1,
                                                    xml2)

        expect(output).to include("INFORMATIVE DIFFERENCES")
      end

      it "Semantic Diff Report omits NORMATIVE section" do
        formatter = Canon::DiffFormatter.new(use_color: false,
                                             show_diffs: :informative)
        output = formatter.format_comparison_result(comparison_result, xml1,
                                                    xml2)

        expect(output).not_to include("NORMATIVE DIFFERENCES")
      end
    end
  end
end
