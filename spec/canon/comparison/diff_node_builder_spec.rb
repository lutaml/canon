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
      it "shows truncated text when both have content" do
        node1 = double("node",
                       text_content: "This is some very long text content that exceeds the limit")
        node2 = double("node", text_content: "This is some short content")

        reason = described_class.build_reason(
          node1, node2, 9, 9, :text_content
        )

        expect(reason).to match(/\A'This is some very long text content that...' vs 'This is some short content'\z/)
      end

      it "handles missing text gracefully" do
        node1 = double("node", text_content: nil)
        node2 = double("node", text_content: "present")

        reason = described_class.build_reason(
          node1, node2, 9, 9, :text_content
        )

        expect(reason).to eq("missing vs 'present'")
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
    end
  end
end
