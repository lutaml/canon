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

      puts "\n=== Canon Comparison Results ==="
      puts "Equivalent: #{result.equivalent?}"
      puts "Total differences: #{result.differences.length}"

      # Group by dimension
      by_dimension = result.differences.group_by(&:dimension)
      puts "\n=== Differences by Dimension ==="
      by_dimension.each do |dimension, diffs|
        puts "#{dimension}: #{diffs.length} differences"
      end

      # Show first few differences
      puts "\n=== First 10 Differences ==="
      result.differences.first(10).each_with_index do |d, i|
        puts "\nDiff #{i + 1}:"
        puts "  dimension: #{d.dimension}"
        puts "  normative: #{d.normative?}"
        puts "  location: #{d.path}"
        puts "  node1: #{d.node1.class} - #{d.node1.name if d.node1.respond_to?(:name)}"
        puts "  node2: #{d.node2.class} - #{d.node2.name if d.node2.respond_to?(:name)}"

        # Show attributes if element nodes
        if d.node1.is_a?(Nokogiri::XML::Element)
          attrs1 = d.node1.attributes.map do |k, v|
            "#{k}='#{v}'"
          end.sort.join(", ")
          puts "  node1 attributes: #{attrs1}" if attrs1 && !attrs1.empty?
        end
        if d.node2.is_a?(Nokogiri::XML::Element)
          attrs2 = d.node2.attributes.map do |k, v|
            "#{k}='#{v}'"
          end.sort.join(", ")
          puts "  node2 attributes: #{attrs2}" if attrs2 && !attrs2.empty?
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
