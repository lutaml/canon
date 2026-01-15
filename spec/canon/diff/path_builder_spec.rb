# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Diff::PathBuilder do
  describe ".build" do
    context "with TreeNode (from semantic diff)" do
      it "generates path with ordinal indices" do
        # Create a tree structure with multiple children
        root = double("TreeNode", label: "#document", parent: nil)
        div1 = double("TreeNode", label: "div", parent: root)
        div2 = double("TreeNode", label: "div", parent: root)
        p1 = double("TreeNode", label: "p", parent: div1)
        p2 = double("TreeNode", label: "p", parent: div1)

        allow(root).to receive(:children).and_return([div1, div2])
        allow(div1).to receive(:children).and_return([p1, p2])
        allow(div2).to receive(:children).and_return([])
        allow(p1).to receive(:children).and_return([])
        allow(p2).to receive(:children).and_return([])

        path = Canon::Diff::PathBuilder.build(p1)

        expect(path).to include("/div[0]/p[0]")
      end

      it "calculates correct ordinal index among siblings" do
        root = double("TreeNode", label: "#document", parent: nil)
        span1 = double("TreeNode", label: "span", parent: root)
        span2 = double("TreeNode", label: "span", parent: root)
        span3 = double("TreeNode", label: "span", parent: root)

        allow(root).to receive(:children).and_return([span1, span2, span3])
        allow(span1).to receive(:children).and_return([])
        allow(span2).to receive(:children).and_return([])
        allow(span3).to receive(:children).and_return([])

        path1 = Canon::Diff::PathBuilder.build(span1)
        path2 = Canon::Diff::PathBuilder.build(span2)
        path3 = Canon::Diff::PathBuilder.build(span3)

        expect(path1).to include("/span[0]")
        expect(path2).to include("/span[1]")
        expect(path3).to include("/span[2]")
      end

      it "handles nil node" do
        path = Canon::Diff::PathBuilder.build(nil)
        expect(path).to eq("")
      end
    end

    context "with Nokogiri nodes" do
      it "generates path for HTML fragment" do
        html = "<div><p>First</p><p>Second</p></div>"
        doc = Nokogiri::HTML4.fragment(html)
        p_tag = doc.at_css("p:last")

        path = Canon::Diff::PathBuilder.build(p_tag)

        expect(path).to include("/p[1]")
      end

      it "generates path for nested elements" do
        html = "<div><p><span>Text</span></p></div>"
        doc = Nokogiri::HTML4.fragment(html)
        span = doc.at_css("span")

        path = Canon::Diff::PathBuilder.build(span)

        expect(path).to include("/div[0]/p[0]/span[0]")
      end

      it "handles document node" do
        html = "<html><body><div></div></body></html>"
        doc = Nokogiri::HTML4.parse(html)

        path = Canon::Diff::PathBuilder.build(doc)

        # Nokogiri document node's name is "document" not "#document"
        expect(path).to eq("/document[0]")
      end
    end

    context "with Nokogiri XML nodes" do
      it "generates path for XML elements" do
        xml = "<root><div><p>Text</p></div></root>"
        doc = Nokogiri::XML(xml)
        p_node = doc.at_css("p")

        path = Canon::Diff::PathBuilder.build(p_node)

        expect(path).to include("/root[0]/div[0]/p[0]")
      end
    end

    context "with format option" do
      it "uses document format for XML" do
        html = "<div><p>Text</p></div>"
        doc = Nokogiri::HTML4.fragment(html)
        p_tag = doc.at_css("p")

        path = Canon::Diff::PathBuilder.build(p_tag, format: :document)

        # Document format includes document root
        expect(path).to match(%r{^/#document})
      end
    end
  end

  describe ".segment_for_node" do
    it "returns segment with label and ordinal index" do
      parent = double("TreeNode", label: "div", parent: nil)
      child1 = double("TreeNode", label: "span", parent: parent)
      child2 = double("TreeNode", label: "span", parent: parent)
      child3 = double("TreeNode", label: "span", parent: parent)

      allow(parent).to receive(:children).and_return([child1, child2, child3])

      segment = Canon::Diff::PathBuilder.segment_for_node(child2)

      expect(segment).to eq("span[1]")
    end

    it "handles node without parent" do
      node = double("TreeNode", label: "root", parent: nil)

      segment = Canon::Diff::PathBuilder.segment_for_node(node)

      expect(segment).to eq("root[0]")
    end
  end

  describe ".ordinal_index" do
    it "calculates zero-based index among same-label siblings" do
      parent = double("TreeNode", parent: nil)
      child1 = double("TreeNode", label: "div", parent: parent)
      child2 = double("TreeNode", label: "span", parent: parent)
      child3 = double("TreeNode", label: "span", parent: parent)
      child4 = double("TreeNode", label: "span", parent: parent)
      child5 = double("TreeNode", label: "div", parent: parent)

      allow(parent).to receive(:children).and_return([child1, child2, child3, child4, child5])

      expect(Canon::Diff::PathBuilder.ordinal_index(child1)).to eq(0)
      expect(Canon::Diff::PathBuilder.ordinal_index(child2)).to eq(0)
      expect(Canon::Diff::PathBuilder.ordinal_index(child3)).to eq(1)
      expect(Canon::Diff::PathBuilder.ordinal_index(child4)).to eq(2)
      expect(Canon::Diff::PathBuilder.ordinal_index(child5)).to eq(1)
    end

    it "returns 0 for node without parent" do
      node = double("TreeNode", parent: nil)

      index = Canon::Diff::PathBuilder.ordinal_index(node)

      expect(index).to eq(0)
    end

    it "returns 0 for node without parent.children" do
      parent = double("TreeNode", parent: nil)
      node = double("TreeNode", parent: parent)

      allow(parent).to receive(:children).and_return(nil)

      index = Canon::Diff::PathBuilder.ordinal_index(node)

      expect(index).to eq(0)
    end
  end

  describe ".human_path" do
    it "generates human-readable path with arrows" do
      root = double("TreeNode", label: "#document", parent: nil)
      div = double("TreeNode", label: "div", parent: root)
      p = double("TreeNode", label: "p", parent: div)

      allow(root).to receive(:children).and_return([div])
      allow(div).to receive(:children).and_return([p])
      allow(p).to receive(:children).and_return([])

      human = Canon::Diff::PathBuilder.human_path(p)

      expect(human).to eq("#document[0] → div[0] → p[0]")
    end
  end
end
