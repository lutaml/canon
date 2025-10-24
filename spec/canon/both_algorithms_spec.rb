# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Canon::Comparison with diff_algorithm: :both" do
  let(:xml1) do
    <<~XML
      <root>
        <person>
          <name>Alice</name>
          <age>30</age>
        </person>
      </root>
    XML
  end

  let(:xml2) do
    <<~XML
      <root>
        <person>
          <name>Bob</name>
          <age>25</age>
        </person>
      </root>
    XML
  end

  describe "running both DOM and Semantic Tree diff algorithms" do
    it "returns CombinedComparisonResult when verbose: true" do
      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
        diff_algorithm: :both
      )

      expect(result).to be_a(Canon::Comparison::CombinedComparisonResult)
    end

    it "provides access to both DOM and Tree results" do
      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
        diff_algorithm: :both
      )

      expect(result.dom_result).to be_a(Canon::Comparison::ComparisonResult)
      expect(result.tree_result).to be_a(Canon::Comparison::ComparisonResult)
    end

    it "correctly identifies algorithm types" do
      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
        diff_algorithm: :both
      )

      expect(result.algorithm).to eq(:both)
      expect(result.dom_result.algorithm).to eq(:dom)
      expect(result.tree_result.algorithm).to eq(:semantic)
    end

    it "returns false when both algorithms find differences" do
      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
        diff_algorithm: :both
      )

      expect(result.equivalent?).to be false
      expect(result.dom_result.equivalent?).to be false
      expect(result.tree_result.equivalent?).to be false
    end

    it "provides differences from both algorithms" do
      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
        diff_algorithm: :both
      )

      expect(result.dom_result.differences).not_to be_empty
      expect(result.tree_result.differences).not_to be_empty
      expect(result.tree_result.operations).not_to be_empty
    end

    it "returns true for identical documents when both algorithms agree" do
      result = Canon::Comparison.equivalent?(
        xml1,
        xml1,
        verbose: true,
        diff_algorithm: :both
      )

      expect(result.equivalent?).to be true
      expect(result.dom_result.equivalent?).to be true
      expect(result.tree_result.equivalent?).to be true
    end

    it "provides iterative access to results" do
      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
        diff_algorithm: :both
      )

      results = result.results
      expect(results).to be_an(Array)
      expect(results.length).to eq(2)
      expect(results[0]).to eq(result.dom_result)
      expect(results[1]).to eq(result.tree_result)
    end
  end

  describe "non-verbose mode with :both algorithm" do
    it "returns boolean value" do
      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        diff_algorithm: :both
      )

      expect([true, false]).to include(result)
      expect(result).to be false
    end

    it "returns true only when both algorithms agree on equivalence" do
      result_different = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        diff_algorithm: :both
      )

      result_same = Canon::Comparison.equivalent?(
        xml1,
        xml1,
        diff_algorithm: :both
      )

      expect(result_different).to be false
      expect(result_same).to be true
    end
  end

  describe "DiffFormatter integration with :both algorithm" do
    it "can format combined comparison results" do
      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
        diff_algorithm: :both
      )

      formatter = Canon::DiffFormatter.new(use_color: false)

      # Should not raise an error
      expect do
        output = formatter.format_comparison_result(result, xml1, xml2)
        expect(output).to be_a(String)
        expect(output).to include("RUNNING BOTH ALGORITHMS")
        expect(output).to include("DOM DIFF")
        expect(output).to include("SEMANTIC TREE DIFF")
      end.not_to raise_error
    end
  end

  describe "combined result interface" do
    let(:result) do
      Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
        diff_algorithm: :both
      )
    end

    it "provides combined differences" do
      combined_diffs = result.differences
      dom_diffs = result.dom_result.differences
      tree_diffs = result.tree_result.differences

      expect(combined_diffs.length).to eq(dom_diffs.length + tree_diffs.length)
    end

    it "provides unified normative/informative diff detection" do
      expect(result).to respond_to(:has_normative_diffs?)
      expect(result).to respond_to(:has_informative_diffs?)
      expect(result).to respond_to(:normative_differences)
      expect(result).to respond_to(:informative_differences)
    end

    it "provides format and metadata from DOM result" do
      expect(result.format).to eq(:xml)
      expect(result.preprocessed_strings).to eq(result.dom_result.preprocessed_strings)
    end

    it "provides tree diff operations from tree result" do
      expect(result.operations).to eq(result.tree_result.operations)
      expect(result.operations).not_to be_empty
    end
  end
end
