# frozen_string_literal: true

require "spec_helper"

RSpec.describe "IsoDoc attribute order issue" do
  let(:expected) do
    File.read(File.join(__dir__,
                        "../fixtures/html/isodoc-section-names-expected.html"))
  end
  let(:actual) do
    File.read(File.join(__dir__,
                        "../fixtures/html/isodoc-section-names-actual.html"))
  end

  it "is equivalent with spec_friendly profile (only attribute order differs)" do
    result = Canon::Comparison.equivalent?(
      expected,
      actual,
      format: :html4,
      match_profile: :spec_friendly,
      verbose: true,
    )

    puts "\n=== ATTRIBUTE ORDER FIXTURE TEST ==="
    puts "Equivalent? #{result.equivalent?}"
    puts "Has active? #{result.has_active_diffs?}"
    puts "Diff count: #{result.differences.length}"

    result.differences.each_with_index do |d, i|
      puts "\nDiff #{i}: #{d.class}"
      if d.respond_to?(:dimension)
        puts "  Dimension: #{d.dimension}"
        puts "  Active: #{d.active?}"
        puts "  Node1: #{d.node1.name if d.node1.respond_to?(:name)}"
        puts "  Node2: #{d.node2.name if d.node2.respond_to?(:name)}"
      end
    end

    # With spec_friendly, attribute order is normalized - should be equivalent
    expect(result.equivalent?).to be true
  end
end
