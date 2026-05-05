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
# and ChildRealignment advances the cursor on the side carrying the
# comment so subsequent content/content pairing is preserved.
RSpec.describe ":comments asymmetry (#144)" do
  # --- HTML path tests ---

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

    let(:result) { Canon::Comparison.equivalent?(expected, actual, format: :html5, verbose: true) }

    it "emits a :comments diff anchored at the asymmetric comment, not :element_structure" do
      structural = result.differences.select do |d|
        d.dimension == :element_structure
      end
      comments = result.differences.select { |d| d.dimension == :comments }

      expect(structural).to be_empty
      expect(comments).not_to be_empty
      expect(comments.first.serialized_before).to include("expected-only")
    end

    it "does not falsely report the trailing footnote-list div as removed" do
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
    let(:result)   { Canon::Comparison.equivalent?(expected, actual, format: :html5, verbose: true) }

    it "emits a :comments diff anchored on the ACTUAL side" do
      comments = result.differences.select { |d| d.dimension == :comments }
      expect(comments).not_to be_empty
      expect(comments.first.reason).to include("ACTUAL only")
    end

    it "preserves alignment so the second <div> is not reported as differing" do
      structural = result.differences.select do |d|
        d.dimension == :element_structure
      end
      expect(structural).to be_empty
    end
  end

  # --- XML path tests (including reason messages) ---

  context "XML with one extra comment on EXPECTED" do
    let(:expected) { "<root><a/><!-- expected-only --><b/></root>" }
    let(:actual)   { "<root><a/><b/></root>" }
    let(:result)   { Canon::Comparison::XmlComparator.equivalent?(expected, actual, verbose: true) }

    it "emits a :comments diff, not :element_structure" do
      dims = result.differences.map(&:dimension)
      expect(dims).to include(:comments)
      expect(dims).not_to include(:element_structure)
    end

    it "produces a descriptive reason mentioning the EXPECTED side" do
      comment_diff = result.differences.find { |d| d.dimension == :comments }
      expect(comment_diff.reason).to include("EXPECTED only")
      expect(comment_diff.reason).to include("expected-only")
    end
  end

  context "XML with one extra comment on ACTUAL" do
    let(:expected) { "<root><a/><b/></root>" }
    let(:actual)   { "<root><a/><!-- actual-only --><b/></root>" }
    let(:result)   { Canon::Comparison::XmlComparator.equivalent?(expected, actual, verbose: true) }

    it "produces a descriptive reason mentioning the ACTUAL side" do
      comment_diff = result.differences.find { |d| d.dimension == :comments }
      expect(comment_diff.reason).to include("ACTUAL only")
      expect(comment_diff.reason).to include("actual-only")
    end
  end

  # --- Combined noise tests ---

  context "combined: one extra whitespace AND one extra comment (XML)" do
    let(:expected) do
      "<root><a/>\n  <!-- expected-only --><b/></root>"
    end
    let(:actual) do
      "<root><a/><b/></root>"
    end
    let(:result) { Canon::Comparison::XmlComparator.equivalent?(expected, actual, verbose: true) }

    it "emits a :comments diff, no :element_structure" do
      dims = result.differences.map(&:dimension).uniq
      expect(dims).to include(:comments)
      expect(dims).not_to include(:element_structure)
    end
  end

  context "combined: one extra whitespace AND one extra comment (HTML)" do
    let(:expected) { "<div>a</div>\n  <!-- x --><div>b</div>" }
    let(:actual)   { "<div>a</div><div>b</div>" }
    let(:result)   { Canon::Comparison.equivalent?(expected, actual, format: :html5, verbose: true) }

    it "emits :comments diff (whitespace stripped by HTML normalization)" do
      dims = result.differences.map(&:dimension).uniq
      expect(dims).to include(:comments)
      expect(dims).not_to include(:element_structure)
    end
  end

  # --- Structural + comment coexistence ---

  context "regression: genuine structural diff alongside an asymmetric comment" do
    let(:expected) do
      "<root><a/><!-- here --><b/><c/></root>"
    end
    let(:actual) do
      "<root><a/><b/></root>"
    end
    let(:result) { Canon::Comparison::XmlComparator.equivalent?(expected, actual, verbose: true) }

    it "still reports the missing <c/> under :element_structure" do
      structural = result.differences.select do |d|
        d.dimension == :element_structure
      end
      expect(structural).not_to be_empty
    end

    it "also reports the asymmetric comment under :comments" do
      comments = result.differences.select { |d| d.dimension == :comments }
      expect(comments).not_to be_empty
    end
  end

  # --- Symmetric comments (both sides have comments) ---

  context "both sides have a comment at the same position" do
    let(:symmetric_xml_a) { "<root><a/><!-- same --><b/></root>" }
    let(:symmetric_xml_b) { "<root><a/><!-- same --><b/></root>" }
    let(:result) { Canon::Comparison::XmlComparator.equivalent?(symmetric_xml_a, symmetric_xml_b, verbose: true) }

    it "does not emit any diffs" do
      expect(result.differences).to be_empty
    end
  end

  context "both sides have comments but with different text" do
    let(:comment_alpha_xml) { "<root><a/><!-- alpha --><b/></root>" }
    let(:comment_beta_xml)  { "<root><a/><!-- beta --><b/></root>" }
    let(:result) { Canon::Comparison::XmlComparator.equivalent?(comment_alpha_xml, comment_beta_xml, verbose: true) }

    it "emits a :comments diff with text comparison in the reason" do
      comments = result.differences.select { |d| d.dimension == :comments }
      expect(comments).not_to be_empty
      expect(comments.first.reason).to include("alpha")
      expect(comments.first.reason).to include("beta")
    end
  end

  # --- Multiple consecutive asymmetric comments ---

  context "multiple consecutive comments on one side" do
    let(:expected) { "<root><a/><!-- c1 --><!-- c2 --><b/></root>" }
    let(:actual)   { "<root><a/><b/></root>" }
    let(:result)   { Canon::Comparison::XmlComparator.equivalent?(expected, actual, verbose: true) }

    it "emits a separate :comments diff for each comment" do
      comments = result.differences.select { |d| d.dimension == :comments }
      expect(comments.length).to eq(2)
    end

    it "preserves alignment of the trailing <b/> element" do
      structural = result.differences.select do |d|
        d.dimension == :element_structure
      end
      expect(structural).to be_empty
    end
  end

  # --- DiffClassifier: :comments respects match profile ---

  context "DiffClassifier classification" do
    let(:xml_with_comment)    { "<root><a/><!-- x --><b/></root>" }
    let(:xml_without_comment) { "<root><a/><b/></root>" }

    it "classifies :comments as normative under default profile" do
      result = Canon::Comparison::XmlComparator.equivalent?(
        xml_with_comment, xml_without_comment, verbose: true
      )
      comment_diff = result.differences.find { |d| d.dimension == :comments }
      expect(comment_diff).to be_normative
    end

    it "classifies :comments as informative when comments: :ignore" do
      result = Canon::Comparison::XmlComparator.equivalent?(
        xml_with_comment, xml_without_comment, verbose: true, match: { comments: :ignore }
      )
      comment_diff = result.differences.find { |d| d.dimension == :comments }
      expect(comment_diff).not_to be_nil
      expect(comment_diff).not_to be_normative
    end
  end

  # --- NodeInspector noise classification (#144 OCP) ---

  context "NodeInspector.noise_dimension_for" do
    let(:ni) { Canon::Comparison::NodeInspector }

    it "returns :whitespace_adjacency for whitespace-only text nodes" do
      doc = Nokogiri::XML("<root>   </root>")
      text_node = doc.at_css("root").children.first
      expect(ni.noise_dimension_for(text_node)).to eq(:whitespace_adjacency)
    end

    it "returns :comments for comment nodes" do
      doc = Nokogiri::XML("<root><!-- x --></root>")
      comment_node = doc.at_css("root").children.first
      expect(ni.noise_dimension_for(comment_node)).to eq(:comments)
    end

    it "returns nil for element nodes" do
      doc = Nokogiri::XML("<root><a/></root>")
      element = doc.at_css("a")
      expect(ni.noise_dimension_for(element)).to be_nil
    end

    it "returns nil for text nodes with content" do
      doc = Nokogiri::XML("<root>hello</root>")
      text_node = doc.at_css("root").children.first
      expect(ni.noise_dimension_for(text_node)).to be_nil
    end
  end

  context "NodeInspector.noise_node?" do
    let(:ni) { Canon::Comparison::NodeInspector }

    it "returns true for whitespace-only text nodes" do
      doc = Nokogiri::XML("<root>   </root>")
      text_node = doc.at_css("root").children.first
      expect(ni.noise_node?(text_node)).to be true
    end

    it "returns true for comment nodes" do
      doc = Nokogiri::XML("<root><!-- x --></root>")
      comment_node = doc.at_css("root").children.first
      expect(ni.noise_node?(comment_node)).to be true
    end

    it "returns false for element nodes" do
      doc = Nokogiri::XML("<root><a/></root>")
      element = doc.at_css("a")
      expect(ni.noise_node?(element)).to be false
    end
  end
end
