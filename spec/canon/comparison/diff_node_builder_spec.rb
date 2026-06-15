# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison::DiffNodeBuilder do
  describe ".build_reason" do
    describe ":attribute_order dimension" do
      it "shows actual attribute names when order differs" do
        xml1 = '<author fullname="John" initials="J." surname="Doe"/>'
        xml2 = '<author initials="J." surname="Doe" fullname="John"/>'

        doc1 = Nokogiri::XML(xml1).children.first
        doc2 = Nokogiri::XML(xml2).children.first

        reason = described_class.build_reason(
          doc1, doc2, 4, 4, :attribute_order
        )

        expect(reason).to eq(
          "Attribute order changed: [fullname, initials, surname] → [initials, surname, fullname]",
        )
      end

      it "handles single attribute" do
        xml1 = '<item priority="high"/>'
        xml2 = '<item priority="high"/>'

        doc1 = Nokogiri::XML(xml1).children.first
        doc2 = Nokogiri::XML(xml2).children.first

        reason = described_class.build_reason(
          doc1, doc2, 4, 4, :attribute_order
        )

        expect(reason).to eq(
          "Attribute order changed: [priority] → [priority]",
        )
      end

      it "handles nil nodes gracefully" do
        reason = described_class.build_reason(
          nil, nil, 4, 4, :attribute_order
        )

        expect(reason).to eq(
          "Attribute order changed: [] → []",
        )
      end
    end

    describe ":text_content dimension" do
      it "shows text with whitespace visualization when both have content" do
        node1 = Canon::Xml::Nodes::TextNode.new(value: "This is some very long text content that exceeds the limit")
        node2 = Canon::Xml::Nodes::TextNode.new(value: "This is some short content")

        reason = described_class.build_reason(
          node1, node2, 9, 9, :text_content
        )

        expect(reason).to start_with('Text: "')
        expect(reason).to include("vs")
      end

      it "handles missing text gracefully" do
        node1 = Canon::Xml::Nodes::TextNode.new(value: "")
        node2 = Canon::Xml::Nodes::TextNode.new(value: "present")

        reason = described_class.build_reason(
          node1, node2, 9, 9, :text_content
        )

        expect(reason).to start_with('Text: "')
        expect(reason).to include("present")
      end
    end

    describe ":attribute_presence dimension" do
      it "shows which attributes differ" do
        node1 = double("node")
        node2 = double("node")

        allow(described_class).to receive(:extract_attributes)
          .with(node1).and_return({ "id" => "1", "class" => "foo" })
        allow(described_class).to receive(:extract_attributes)
          .with(node2).and_return({ "id" => "1", "class" => "bar" })

        reason = described_class.build_reason(
          node1, node2, 2, 2, :attribute_presence
        )

        expect(reason).to include("different values: class")
      end
    end

    # Issue #127: previously this fallback rendered the raw integer
    # constant value (e.g. "7 vs 7" for UNEQUAL_ELEMENTS) into the user-
    # facing reason text.  After the fix it routes through
    # Canon::Comparison.code_pair_label and produces a human-readable
    # label, with a more specific "different element name" reason when
    # the dimension is :element_structure and both nodes carry differing
    # tag names.
    describe "default fallback (issue #127)" do
      it "uses 'different element name (<a> vs <b>)' for differing element names" do
        doc1 = Nokogiri::XML("<i>x</i>").children.first
        doc2 = Nokogiri::XML("<br/>").children.first

        reason = described_class.build_reason(
          doc1, doc2,
          Canon::Comparison::UNEQUAL_ELEMENTS,
          Canon::Comparison::UNEQUAL_ELEMENTS,
          :element_structure
        )

        expect(reason).to eq("different element name (<i> vs <br>)")
        expect(reason).not_to match(/\A\d+ vs \d+\z/)
      end

      it "uses the human-readable label when both codes are equal" do
        node = Nokogiri::XML("<x/>").children.first

        reason = described_class.build_reason(
          node, node,
          Canon::Comparison::UNEQUAL_NODES_TYPES,
          Canon::Comparison::UNEQUAL_NODES_TYPES,
          :element_position
        )

        expect(reason).to eq("node types differ")
      end

      it "joins differing labels with ' vs '" do
        node = Nokogiri::XML("<x/>").children.first

        reason = described_class.build_reason(
          node, node,
          Canon::Comparison::UNEQUAL_ELEMENTS,
          Canon::Comparison::UNEQUAL_NODES_TYPES,
          :element_position
        )

        expect(reason).to eq("elements differ vs node types differ")
      end

      it "passes through string diff codes unchanged (e.g. 'position 3')" do
        node = Nokogiri::XML("<x/>").children.first

        reason = described_class.build_reason(
          node, node, "position 3", "position 5", :element_position
        )

        expect(reason).to eq("position 3 vs position 5")
      end

      # PR #126's first cut covered the *fallback* line at the end of
      # build_reason but missed the namespace-prefixed early return at
      # build_reason line ~62, which interpolated the same raw codes.
      # This regression guard locks the early-return path too.
      # Canon::Xml::Nodes::ElementNode (not Nokogiri::XML::Element) is
      # used because the early-return only fires for nodes that respond
      # to namespace_uri, which Canon nodes do but Nokogiri elements
      # do not.
      it "uses code_pair_label in the namespace-prefixed text_content branch" do
        node = Canon::Xml::Nodes::ElementNode.new(name: "body")

        reason = described_class.build_reason(
          node, nil,
          Canon::Comparison::MISSING_NODE,
          Canon::Comparison::MISSING_NODE,
          :text_content
        )

        expect(reason).to eq("element 'body': missing")
        expect(reason).not_to match(/\d+ vs \d+/)
      end
    end
  end

  describe ".build_reason :whitespace_adjacency" do
    it "names the side that carries the whitespace" do
      root1 = Canon::Xml::Nodes::RootNode.new
      parent1 = Canon::Xml::Nodes::ElementNode.new(name: "p")
      root1.add_child(parent1)
      ws_text = Canon::Xml::Nodes::TextNode.new(value: " ")
      content_text = Canon::Xml::Nodes::TextNode.new(value: "hello")
      parent1.add_child(ws_text)
      parent1.add_child(content_text)

      root2 = Canon::Xml::Nodes::RootNode.new
      parent2 = Canon::Xml::Nodes::ElementNode.new(name: "p")
      root2.add_child(parent2)
      parent2.add_child(Canon::Xml::Nodes::TextNode.new(value: "hello"))

      reason = described_class.build_reason(
        ws_text, content_text,
        Canon::Comparison::MISSING_NODE,
        Canon::Comparison::MISSING_NODE,
        :whitespace_adjacency
      )

      expect(reason).to include("EXPECTED")
      expect(reason).to include("absent on ACTUAL")
    end

    it "falls back to text diff when neither side is whitespace-only" do
      node1 = Canon::Xml::Nodes::TextNode.new(value: "hello")
      node2 = Canon::Xml::Nodes::TextNode.new(value: "world")

      reason = described_class.build_reason(
        node1, node2,
        Canon::Comparison::UNEQUAL_TEXT_CONTENTS,
        Canon::Comparison::UNEQUAL_TEXT_CONTENTS,
        :whitespace_adjacency
      )

      expect(reason).to start_with('Text: "')
    end
  end

  describe ".visualize_whitespace" do
    it "returns empty string for nil" do
      expect(described_class.visualize_whitespace(nil)).to eq("")
    end

    it "passes through text with no special whitespace" do
      expect(described_class.visualize_whitespace("hello")).to eq("hello")
    end

    it "visualizes space characters" do
      result = described_class.visualize_whitespace("a b")
      expect(result).not_to eq("a b")
      expect(result).to include("a")
      expect(result).to include("b")
    end
  end

  describe ".describe_whitespace" do
    it "returns 0 chars for nil or empty" do
      expect(described_class.describe_whitespace(nil)).to eq("0 chars")
      expect(described_class.describe_whitespace("")).to eq("0 chars")
    end

    it "counts chars and reports components" do
      result = described_class.describe_whitespace(" \n")
      expect(result).to include("2 chars")
      expect(result).to include("1 spaces")
      expect(result).to include("1 newlines")
    end
  end

  describe ".whitespace_only?" do
    it "returns false for nil" do
      expect(described_class.whitespace_only?(nil)).to be(false)
    end

    it "returns true for whitespace-only strings" do
      expect(described_class.whitespace_only?("  \n\t")).to be(true)
      expect(described_class.whitespace_only?("   ")).to be(true)
    end

    it "returns false for content strings" do
      expect(described_class.whitespace_only?("hello")).to be(false)
      expect(described_class.whitespace_only?(" x ")).to be(false)
    end
  end

  describe ".build_reason :comments" do
    it "shows comment on expected side" do
      root = Canon::Xml::Nodes::RootNode.new
      parent = Canon::Xml::Nodes::ElementNode.new(name: "div")
      root.add_child(parent)
      comment = Canon::Xml::Nodes::CommentNode.new(value: "hello")
      parent.add_child(comment)

      reason = described_class.build_reason(
        comment, nil,
        Canon::Comparison::MISSING_NODE,
        Canon::Comparison::MISSING_NODE,
        :comments
      )

      expect(reason).to eq("Comment present on EXPECTED only: <!--hello-->")
    end

    it "shows comment on actual side" do
      root = Canon::Xml::Nodes::RootNode.new
      parent = Canon::Xml::Nodes::ElementNode.new(name: "div")
      root.add_child(parent)
      comment = Canon::Xml::Nodes::CommentNode.new(value: "world")
      parent.add_child(comment)

      reason = described_class.build_reason(
        nil, comment,
        Canon::Comparison::MISSING_NODE,
        Canon::Comparison::MISSING_NODE,
        :comments
      )

      expect(reason).to eq("Comment present on ACTUAL only: <!--world-->")
    end
  end

  describe ".build_reason :attribute_values" do
    it "shows which attributes changed" do
      doc1 = Nokogiri::XML('<item id="1"/>').children.first
      doc2 = Nokogiri::XML('<item id="2"/>').children.first

      reason = described_class.build_reason(
        doc1, doc2, 4, 4, :attribute_values
      )

      expect(reason).to include('id="1"')
      expect(reason).to include('"2"')
      expect(reason).to include("Changed")
    end
  end
end
