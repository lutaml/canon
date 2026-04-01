# frozen_string_literal: true

require "spec_helper"

RSpec.describe "HashMatcher candidate iteration regression" do
  # Regression: match_node was simplified to only try the first candidate,
  # removing position proximity sorting and candidate iteration with prefix
  # closure fallback. This caused massive false diff counts (6000+ instead
  # of ~28) in documents with duplicate subtrees (MathML, lists, etc.).

  describe "duplicate subtree matching" do
    it "matches identical duplicate subtrees at correct positions" do
      xml1 = <<~XML
        <root>
          <list>
            <item>A</item>
            <item>B</item>
            <item>A</item>
            <item>B</item>
            <item>A</item>
          </list>
        </root>
      XML

      result = Canon::Comparison.equivalent?(xml1, xml1,
                                             diff_algorithm: :semantic,
                                             verbose: true)
      expect(result.equivalent?).to be true
      expect(result.differences).to be_empty
    end

    it "does not cause exponential diff explosion on documents with many duplicates" do
      # Generate a document with many duplicate <label>x</label> entries
      items = (1..50).map do |i|
        "  <label>x</label>\n  <value>#{i}</value>"
      end.join("\n")
      xml1 = "<root>\n#{items}\n</root>"

      # Change only the first value
      items2 = items.sub("<value>1</value>", "<value>changed</value>")
      xml2 = "<root>\n#{items2}\n</root>"

      result = Canon::Comparison.equivalent?(xml1, xml2,
                                             diff_algorithm: :semantic,
                                             verbose: true)
      expect(result.equivalent?).to be false
      # Should have a small number of diffs (1-3), not hundreds or thousands
      expect(result.differences.length).to be <= 5
    end

    it "keeps diff count bounded for duplicate subtrees with small changes" do
      # Multiple identical <item>A</item> blocks, change value in each
      xml1 = <<~XML
        <root>
          <list>
            <item>A</item>
            <item>B</item>
            <item>A</item>
            <item>B</item>
          </list>
        </root>
      XML

      xml2 = <<~XML
        <root>
          <list>
            <item>C</item>
            <item>B</item>
            <item>C</item>
            <item>B</item>
          </list>
        </root>
      XML

      result = Canon::Comparison.equivalent?(xml1, xml2,
                                             diff_algorithm: :semantic,
                                             verbose: true)
      expect(result.equivalent?).to be false
      # The hash matcher should report a bounded number of diffs (<= 6),
      # not hundreds from cascading mis-matches
      expect(result.differences.length).to be <= 6
    end

    it "keeps diff count bounded for deeply nested duplicate structures" do
      xml1 = <<~XML
        <doc>
          <section><para><bold>A</bold></para></section>
          <section><para><bold>A</bold></para></section>
          <section><para><bold>A</bold></para></section>
        </doc>
      XML

      xml2 = <<~XML
        <doc>
          <section><para><bold>B</bold></para></section>
          <section><para><bold>A</bold></para></section>
          <section><para><bold>B</bold></para></section>
        </doc>
      XML

      result = Canon::Comparison.equivalent?(xml1, xml2,
                                             diff_algorithm: :semantic,
                                             verbose: true)
      expect(result.equivalent?).to be false
      # Should report bounded diffs, not exponential explosion
      expect(result.differences.length).to be <= 6
    end

    it "uses position proximity to prefer correct match among duplicates" do
      # Structure where identical siblings exist under different parents.
      # Position proximity sorting should match each group's items correctly.
      xml1 = <<~XML
        <root>
          <group id="1"><item>A</item><item>A</item></group>
          <group id="2"><item>A</item><item>A</item></group>
        </root>
      XML

      xml2 = <<~XML
        <root>
          <group id="1"><item>B</item><item>A</item></group>
          <group id="2"><item>A</item><item>B</item></group>
        </root>
      XML

      result = Canon::Comparison.equivalent?(xml1, xml2,
                                             diff_algorithm: :semantic,
                                             verbose: true)
      expect(result.equivalent?).to be false
      # Should report bounded diffs, not cascading mis-matches
      expect(result.differences.length).to be <= 6
    end
  end
end
