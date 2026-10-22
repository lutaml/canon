# frozen_string_literal: true

require "spec_helper"

# Regression vectors for canon#285: a child element removed from mixed
# content was reported as an insertion (node1=nil, node2=element) —
# the emitter derived the diff side from the REDUCED child sets
# (equal length after determine_mismatch_children) instead of the
# original arrays, so every mid-content removal inverted direction,
# and opposite changes (row 4 vs row 7) produced identical output.
RSpec.describe "mixed-content child diff direction (canon#285)" do
  def first_direction(before, after)
    result = Canon::Comparison.equivalent?(before, after, verbose: true,
                                                          format: :xml)
    result.differences.filter_map do |d|
      if d.node1 && d.node2.nil? then "removal"
      elsif d.node2 && d.node1.nil? then "insertion"
      end
    end
  end

  {
    "adjacent siblings" => ["<root><title><b/><c/></title></root>",
                            "<root><title><c/></title></root>"],
    "trailing sibling" => ["<root><title><c/><b/></title></root>",
                           "<root><title><c/></title></root>"],
    "only child" => ["<root><title><b/></title></root>",
                     "<root><title/></root>"],
    "text both sides" => ["<root><title>t <b/> <c/></title></root>",
                          "<root><title>t <c/></title></root>"],
    "text before" => ["<root><title>t <b/></title></root>",
                      "<root><title>t </title></root>"],
    "mixed text" => ["<root><title>Name <b/></title></root>",
                     "<root><title>Name </title></root>"],
  }.each do |name, (before, after)|
    it "reports a removal for #{name}" do
      expect(first_direction(before, after)).to eq(["removal"])
    end
  end

  it "reports an insertion for the added element" do
    expect(first_direction("<root><title>t <c/></title></root>",
                           "<root><title>t <b/> <c/></title></root>"))
      .to eq(["insertion"])
  end

  it "keeps opposite changes distinct" do
    removal = first_direction("<root><title>t <b/></title></root>",
                              "<root><title>t </title></root>")
    addition = first_direction("<root><title>t </title></root>",
                               "<root><title>t <b/></title></root>")
    expect(removal).to eq(["removal"])
    expect(addition).to eq(["insertion"])
  end

  it "reports the removed element for the block-level case" do
    expect(first_direction("<root><title>T</title><p>x</p></root>",
                           "<root><p>x</p></root>"))
      .to eq(["removal"])
  end
end
