# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Reflow explosion" do
  describe "attribute order differences" do
    let(:old_xml) do
      File.read("spec/fixtures/canon/reflow/old_multiline_attrs.xml")
    end

    let(:new_xml) do
      File.read("spec/fixtures/canon/reflow/new_compacted_attrs.xml")
    end

    it "documents are equivalent despite attribute order differences" do
      result = Canon::Comparison.equivalent?(old_xml, new_xml, verbose: true)

      expect(result.equivalent?).to be true
      expect(result.differences).not_to be_empty

      # All differences should be informative (attribute_order), not normative
      result.differences.each do |d|
        expect(d.dimension).to eq(:attribute_order)
        expect(d.normative?).to be false
        expect(d.informative?).to be true
      end
    end

    it "suppresses diff output when equivalent and no normative diffs" do
      result = Canon::Comparison.equivalent?(old_xml, new_xml, verbose: true)
      diff = result.diff(use_color: false)
      lines = diff.split("\n")

      # When equivalent, diff should be minimal (header only)
      # Should NOT show individual attribute order lines
      expect(lines.length).to eq(1)
    end
  end

  describe "extreme reflow (sts-ruby pattern)" do
    it "handles large reflow efficiently" do
      # Build 50 items with multi-line attributes in old, inline in new
      old_lines = ["<?xml version=\"1.0\"?>", "<doc>"]
      new_lines = ["<?xml version=\"1.0\"?>", "<doc>"]

      50.times do |i|
        old_lines << "  <item"
        old_lines << "    id=\"item-#{i}\""
        old_lines << "    type=\"#{i.even? ? 'alpha' : 'beta'}\""
        old_lines << "    status=\"active\">"
        old_lines << "    <title>Item #{i}</title>"
        old_lines << "  </item>"

        new_lines << "  <item id=\"item-#{i}\" status=\"active\" type=\"#{i.even? ? 'alpha' : 'beta'}\">"
        new_lines << "    <title>Item #{i}</title>"
        new_lines << "  </item>"
      end

      old_lines << "</doc>"
      new_lines << "</doc>"

      old_xml = old_lines.join("\n")
      new_xml = new_lines.join("\n")

      result = Canon::Comparison.equivalent?(old_xml, new_xml, verbose: true)
      diff = result.diff(use_color: false)
      lines = diff.split("\n")

      # Should be equivalent
      expect(result.equivalent?).to be true

      # Diff should be minimal - no explosion of lines
      # Just the header since these are all informative (attribute_order) differences
      expect(lines.length).to eq(1),
                              "Expected 1 line (header only), got #{lines.length}. Reflow should be suppressed for equivalent docs."
    end
  end

  describe "true equivalent (no differences)" do
    it "shows no diff output" do
      xml1 = "<root><item>One</item></root>"
      xml2 = "<root><item>One</item></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true)
      diff = result.diff(use_color: false)

      expect(result.equivalent?).to be true
      expect(result.differences).to be_empty
      expect(diff.lines.length).to eq(1) # Just the header
    end
  end
end
