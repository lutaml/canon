# frozen_string_literal: true

require "spec_helper"
require "nokogiri"

RSpec.describe "Canon TreeDiff Integration" do
  describe "XML comparison with semantic_diff enabled" do
    it "uses tree diff when semantic_diff is true" do
      xml1 = "<root><child>value</child></root>"
      xml2 = "<root><child>value</child></root>"

      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
        diff_algorithm: :semantic,
      )

      expect(result).to be_a(Canon::Comparison::ComparisonResult)
      expect(result.equivalent?).to be true
      # tree diff is active when statistics are present
      expect(result.match_options[:tree_diff_statistics]).to be_a(Hash)
    end

    it "detects differences with tree diff" do
      xml1 = "<root><child>old value</child></root>"
      xml2 = "<root><child>new value</child></root>"

      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
        diff_algorithm: :semantic,
      )

      expect(result).to be_a(Canon::Comparison::ComparisonResult)
      expect(result.equivalent?).to be false
      expect(result.differences).not_to be_empty
      # tree diff is active when statistics are present
    end

    it "returns boolean false without verbose mode" do
      xml1 = "<root><child>value1</child></root>"
      xml2 = "<root><child>value2</child></root>"

      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        diff_algorithm: :semantic,
      )

      expect(result).to be false
    end

    it "returns boolean true for equivalent documents without verbose" do
      xml1 = "<root><child>value</child></root>"
      xml2 = "<root><child>value</child></root>"

      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        diff_algorithm: :semantic,
      )

      expect(result).to be true
    end

    it "provides tree diff statistics" do
      xml1 = "<root><a>1</a><b>2</b><c>3</c></root>"
      xml2 = "<root><a>1</a><b>2</b><c>3</c></root>"

      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
        diff_algorithm: :semantic,
      )

      stats = result.match_options[:tree_diff_statistics]
      expect(stats).to have_key(:total_matches)
      expect(stats).to have_key(:hash_matches)
      expect(stats).to have_key(:match_ratio_tree1)
      expect(stats).to have_key(:match_ratio_tree2)
      expect(stats[:total_matches]).to be > 0
    end

    it "detects INSERT operations" do
      xml1 = "<root><child1>value</child1></root>"
      xml2 = "<root><child1>value</child1><child2>new</child2></root>"

      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
        diff_algorithm: :semantic,
      )

      expect(result.equivalent?).to be false
      expect(result.differences).not_to be_empty

      # Check that we have an insert operation (node1 nil, node2 present)
      insert_diffs = result.differences.select do |d|
        d.node1.nil? && !d.node2.nil?
      end
      expect(insert_diffs).not_to be_empty
    end

    it "detects DELETE operations" do
      xml1 = "<root><child1>value</child1><child2>old</child2></root>"
      xml2 = "<root><child1>value</child1></root>"

      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
        diff_algorithm: :semantic,
      )

      expect(result.equivalent?).to be false
      expect(result.differences).not_to be_empty

      # Check that we have a delete operation (node1 present, node2 nil)
      delete_diffs = result.differences.select do |d|
        !d.node1.nil? && d.node2.nil?
      end
      expect(delete_diffs).not_to be_empty
    end

    it "detects UPDATE operations" do
      xml1 = "<root><child>old value</child></root>"
      xml2 = "<root><child>new value</child></root>"

      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
        diff_algorithm: :semantic,
      )

      expect(result.equivalent?).to be false
      expect(result.differences).not_to be_empty

      # Check that we have an update operation (both node1 and node2 present)
      update_diffs = result.differences.select do |d|
        !d.node1.nil? && !d.node2.nil?
      end
      expect(update_diffs).not_to be_empty
    end

    it "respects preprocessing option with tree diff" do
      xml1 = "<root>  <child>  value  </child>  </root>"
      xml2 = "<root><child>value</child></root>"

      # With spec_friendly profile, whitespace differences are non-normative
      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        diff_algorithm: :semantic,
        match_profile: :spec_friendly,
      )

      expect(result).to be true
    end

    it "respects similarity_threshold option" do
      xml1 = "<root><child>value</child></root>"
      xml2 = "<root><child>value</child></root>"

      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
        match: {
          diff_algorithm: :semantic,
          similarity_threshold: 0.8,
        },
      )

      expect(result.equivalent?).to be true
      # tree diff is active when statistics are present
    end

    it "works with complex nested structures" do
      xml1 = <<~XML
        <book>
          <title>Sample Book</title>
          <author>
            <name>John Doe</name>
            <email>john@example.com</email>
          </author>
          <chapters>
            <chapter id="1">Introduction</chapter>
            <chapter id="2">Background</chapter>
          </chapters>
        </book>
      XML

      xml2 = <<~XML
        <book>
          <title>Sample Book</title>
          <author>
            <name>John Doe</name>
            <email>john@newdomain.com</email>
          </author>
          <chapters>
            <chapter id="1">Introduction</chapter>
            <chapter id="2">Background</chapter>
            <chapter id="3">Conclusion</chapter>
          </chapters>
        </book>
      XML

      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
        diff_algorithm: :semantic,
      )

      expect(result.equivalent?).to be false
      expect(result.differences).not_to be_empty

      # Should detect email update (both nodes present) and chapter insertion (node1 nil)
      has_update = result.differences.any? do |d|
        !d.node1.nil? && !d.node2.nil?
      end
      has_insert = result.differences.any? { |d| d.node1.nil? && !d.node2.nil? }
      expect(has_update).to be true
      expect(has_insert).to be true
    end
  end

  describe "fallback to regular comparison" do
    it "uses regular comparison when semantic_diff is false" do
      xml1 = "<root><child>value</child></root>"
      xml2 = "<root><child>value</child></root>"

      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
        match: { semantic_diff: false },
      )

      expect(result).to be_a(Canon::Comparison::ComparisonResult)
      expect(result.equivalent?).to be true
      # Should not have tree_diff_enabled flag
      expect(result.match_options[:tree_diff_enabled]).to be_nil
    end

    it "uses regular comparison by default" do
      xml1 = "<root><child>value</child></root>"
      xml2 = "<root><child>value</child></root>"

      result = Canon::Comparison.equivalent?(
        xml1,
        xml2,
        verbose: true,
      )

      expect(result).to be_a(Canon::Comparison::ComparisonResult)
      expect(result.equivalent?).to be true
      # Should not have tree_diff_enabled flag
      expect(result.match_options[:tree_diff_enabled]).to be_nil
    end
  end
end
