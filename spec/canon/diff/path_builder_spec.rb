# frozen_string_literal: true

require "spec_helper"
require "canon/tree_diff/core/tree_node"

RSpec.describe Canon::Diff::PathBuilder do
  def make_node(label, parent: nil)
    node = Canon::TreeDiff::Core::TreeNode.new(label: label)
    node.parent = parent
    node.children = []
    node
  end

  describe ".build" do
    context "with TreeNode (from semantic diff)" do
      it "generates path with ordinal indices" do
        root = make_node("#document")
        div1 = make_node("div", parent: root)
        div2 = make_node("div", parent: root)
        p1 = make_node("p", parent: div1)
        p2 = make_node("p", parent: div1)
        root.children = [div1, div2]
        div1.children = [p1, p2]

        path = described_class.build(p1)

        expect(path).to include("/div[0]/p[0]")
      end

      it "calculates correct ordinal index among siblings" do
        root = make_node("#document")
        span1 = make_node("span", parent: root)
        span2 = make_node("span", parent: root)
        span3 = make_node("span", parent: root)
        root.children = [span1, span2, span3]

        path1 = described_class.build(span1)
        path2 = described_class.build(span2)
        path3 = described_class.build(span3)

        expect(path1).to include("/span[0]")
        expect(path2).to include("/span[1]")
        expect(path3).to include("/span[2]")
      end

      it "handles nil node" do
        path = described_class.build(nil)
        expect(path).to eq("")
      end
    end

    context "with Nokogiri nodes" do
      it "generates path for HTML fragment" do
        html = "<div><p>First</p><p>Second</p></div>"
        doc = Nokogiri::HTML4.fragment(html)
        p_tag = doc.at_css("p:last")

        path = described_class.build(p_tag)

        expect(path).to include("/p[1]")
      end

      it "generates path for nested elements" do
        html = "<div><p><span>Text</span></p></div>"
        doc = Nokogiri::HTML4.fragment(html)
        span = doc.at_css("span")

        path = described_class.build(span)

        expect(path).to include("/div[0]/p[0]/span[0]")
      end

      it "handles document node" do
        html = "<html><body><div></div></body></html>"
        doc = Nokogiri::HTML4.parse(html)

        path = described_class.build(doc)

        expect(path).to eq("/document[0]")
      end
    end

    context "with Nokogiri XML nodes" do
      it "generates path for XML elements" do
        xml = "<root><div><p>Text</p></div></root>"
        doc = Nokogiri::XML(xml)
        p_node = doc.at_css("p")

        path = described_class.build(p_node)

        expect(path).to include("/root[0]/div[0]/p[0]")
      end
    end

    context "with format option" do
      it "uses document format for XML" do
        html = "<div><p>Text</p></div>"
        doc = Nokogiri::HTML4.fragment(html)
        p_tag = doc.at_css("p")

        path = described_class.build(p_tag, format: :document)

        expect(path).to match(%r{^/#document})
      end
    end
  end

  describe ".segment_for_node" do
    it "returns segment with label and ordinal index" do
      parent = make_node("div")
      child1 = make_node("span", parent: parent)
      child2 = make_node("span", parent: parent)
      child3 = make_node("span", parent: parent)
      parent.children = [child1, child2, child3]

      segment = described_class.segment_for_node(child2)

      expect(segment).to eq("span[1]")
    end

    it "handles node without parent" do
      node = make_node("root")

      segment = described_class.segment_for_node(node)

      expect(segment).to eq("root[0]")
    end
  end

  describe ".ordinal_index" do
    it "calculates zero-based index among same-label siblings" do
      parent = make_node("parent")
      child1 = make_node("div", parent: parent)
      child2 = make_node("span", parent: parent)
      child3 = make_node("span", parent: parent)
      child4 = make_node("span", parent: parent)
      child5 = make_node("div", parent: parent)
      parent.children = [child1, child2, child3, child4, child5]

      expect(described_class.ordinal_index(child1)).to eq(0)
      expect(described_class.ordinal_index(child2)).to eq(0)
      expect(described_class.ordinal_index(child3)).to eq(1)
      expect(described_class.ordinal_index(child4)).to eq(2)
      expect(described_class.ordinal_index(child5)).to eq(1)
    end

    it "returns 0 for node without parent" do
      node = make_node("root")

      index = described_class.ordinal_index(node)

      expect(index).to eq(0)
    end

    it "returns 0 for node without parent.children" do
      parent = make_node("parent")
      node = make_node("child", parent: parent)
      parent.children = nil

      index = described_class.ordinal_index(node)

      expect(index).to eq(0)
    end
  end

  describe ".human_path" do
    it "generates human-readable path with arrows" do
      root = make_node("#document")
      div = make_node("div", parent: root)
      p = make_node("p", parent: div)
      root.children = [div]
      div.children = [p]

      human = described_class.human_path(p)

      expect(human).to eq("#document[0] → div[0] → p[0]")
    end
  end
end
