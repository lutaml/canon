# frozen_string_literal: true

require "spec_helper"

# Regression tests for the :comments diff dimension under asymmetric
# comment nodes (issue #144).
#
# Background: in verbose mode, +filter_children+ keeps comment nodes in
# both sides (see markup_comparator.rb's verbose short-circuit).  When
# the two sides have a different number of comments at a given level,
# the children arrays end up with different lengths.  Pre-#144, the
# length-mismatch heuristic fell through to +:element_structure+ and
# blamed whichever named element happened to sit at the trailing edge,
# producing a confusing false positive.
#
# Post-#144, asymmetric comment nodes are classified under +:comments+
# and the realignment walker advances the cursor on the side carrying
# the comment so subsequent content/content pairing is preserved.
RSpec.describe ":comments asymmetry (#144)" do
  def compare_html(html1, html2) # rubocop:disable Naming/PredicateMethod
    Canon::Comparison.equivalent?(html1, html2, format: :html5, verbose: true)
  end

  def compare_xml(xml1, xml2, **opts) # rubocop:disable Naming/PredicateMethod
    Canon::Comparison::XmlComparator.equivalent?(
      xml1, xml2, verbose: true, **opts
    )
  end

  context "HTML fragment with one extra comment on EXPECTED" do
    let(:expected) do
      <<~HTML
        <html><body>
          <div>first</div>
          <div>second</div>
          <!-- expected-only -->
          <div style="mso-element:footnote-list"></div>
        </body></html>
      HTML
    end

    let(:actual) do
      <<~HTML
        <html><body>
          <div>first</div>
          <div>second</div>
          <div style="mso-element:footnote-list"></div>
        </body></html>
      HTML
    end

    it "emits a :comments diff anchored at the asymmetric comment, not :element_structure" do
      result = compare_html(expected, actual)
      structural = result.differences.select do |d|
        d.dimension == :element_structure
      end
      comments = result.differences.select { |d| d.dimension == :comments }

      expect(structural).to be_empty
      expect(comments).not_to be_empty
      expect(comments.first.serialized_before).to include("expected-only")
    end

    it "does not falsely report the trailing footnote-list div as removed" do
      result = compare_html(expected, actual)
      footnote_diffs = result.differences.select do |d|
        (d.serialized_before || "").include?("mso-element:footnote-list") ||
          (d.serialized_after || "").include?("mso-element:footnote-list")
      end
      expect(footnote_diffs).to be_empty
    end
  end

  context "HTML fragment with one extra comment on ACTUAL" do
    let(:expected) { "<div>a</div><div>b</div>" }
    let(:actual)   { "<div>a</div><!-- actual-only --><div>b</div>" }

    it "emits a :comments diff anchored on the ACTUAL side" do
      result = compare_html(expected, actual)
      comments = result.differences.select { |d| d.dimension == :comments }
      expect(comments).not_to be_empty
      expect(comments.first.reason).to include("ACTUAL only")
    end

    it "preserves alignment so the second <div> is not reported as differing" do
      result = compare_html(expected, actual)
      structural = result.differences.select do |d|
        d.dimension == :element_structure
      end
      expect(structural).to be_empty
    end
  end

  context "combined: one extra whitespace AND one extra comment" do
    let(:expected) do
      "<root><a/>\n  <!-- expected-only --><b/></root>"
    end
    let(:actual) do
      "<root><a/><b/></root>"
    end

    it "emits both a :whitespace_adjacency and a :comments diff, no :element_structure" do
      result = compare_xml(expected, actual)
      dims = result.differences.map(&:dimension).uniq
      expect(dims).to include(:comments)
      expect(dims).not_to include(:element_structure)
    end
  end

  context "regression: genuine structural diff alongside an asymmetric comment" do
    let(:expected) do
      "<root><a/><!-- here --><b/><c/></root>"
    end
    let(:actual) do
      "<root><a/><b/></root>"
    end

    it "still reports the missing <c/> under :element_structure" do
      result = compare_xml(expected, actual)
      structural = result.differences.select do |d|
        d.dimension == :element_structure
      end
      expect(structural).not_to be_empty
    end

    it "also reports the asymmetric comment under :comments" do
      result = compare_xml(expected, actual)
      comments = result.differences.select { |d| d.dimension == :comments }
      expect(comments).not_to be_empty
    end
  end
end
