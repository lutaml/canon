# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe "IsoDoc HTML comparison fixtures" do
  describe "DOM DIFF algorithm" do
    it "detects insertion and attribute differences" do
      expected = File.read("spec/fixtures/canon/isodoc_expected.html")
      actual = File.read("spec/fixtures/canon/isodoc_actual.html")

      result = Canon::Comparison.equivalent?(actual, expected,
                                             format: :html4,
                                             verbose: true)

      # Group by dimension
      by_dimension = result.differences.group_by(&:dimension)
      by_dimension.each do |dimension, diffs|
        # puts "Dimension: #{dimension}, Count: #{diffs.size}"
      end

      # Show first few differences
      result.differences.first(10).each_with_index do |d, _i|
        # Show attributes if element nodes
        if d.node1.is_a?(Nokogiri::XML::Element)
          attrs1 = d.node1.attributes.map do |k, v|
            "#{k}='#{v}'"
          end.sort.join(", ")
          if attrs1 && !attrs1.empty?
            # puts "Node1 attributes: #{attrs1}"
          end
        end
        if d.node2.is_a?(Nokogiri::XML::Element)
          attrs2 = d.node2.attributes.map do |k, v|
            "#{k}='#{v}'"
          end.sort.join(", ")
          if attrs2 && !attrs2.empty?
            # puts "Node2 attributes: #{attrs2}"
          end
        end
      end

      # We expect this to fail
      expect(result.equivalent?).to be false
    end
  end

  describe "Semantic DIFF algorithm (experimental)" do
    it "detects insertions correctly using semantic matching" do
      expected = File.read("spec/fixtures/canon/isodoc_expected.html")
      actual = File.read("spec/fixtures/canon/isodoc_actual.html")

      # Use semantic tree diff algorithm
      result = Canon::Comparison.equivalent?(actual, expected,
                                             format: :html4,
                                             diff_algorithm: :semantic,
                                             verbose: true)

      # Semantic diff should detect the differences
      expect(result).to be_a(Canon::Comparison::ComparisonResult)
      expect(result.differences).not_to be_empty
    end
  end
end
