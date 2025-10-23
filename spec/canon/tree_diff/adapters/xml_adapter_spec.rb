# frozen_string_literal: true

require "spec_helper"
require "nokogiri"
require_relative "../../../../lib/canon/tree_diff"

RSpec.describe Canon::TreeDiff::Adapters::XMLAdapter do
  let(:adapter) { described_class.new }

  describe "#to_tree" do
    context "with simple XML element" do
      let(:xml) { Nokogiri::XML("<root>text content</root>") }

      it "converts to TreeNode" do
        tree = adapter.to_tree(xml)

        expect(tree).to be_a(Canon::TreeDiff::Core::TreeNode)
        expect(tree.label).to eq("root")
        expect(tree.value).to eq("text content")
        expect(tree.children).to be_empty
      end
    end

    context "with nested elements" do
      let(:xml) do
        Nokogiri::XML(<<~XML)
          <root>
            <child1>value1</child1>
            <child2>value2</child2>
          </root>
        XML
      end

      it "converts nested structure" do
        tree = adapter.to_tree(xml)

        expect(tree.label).to eq("root")
        expect(tree.children.size).to eq(2)

        child1 = tree.children[0]
        expect(child1.label).to eq("child1")
        expect(child1.value).to eq("value1")

        child2 = tree.children[1]
        expect(child2.label).to eq("child2")
        expect(child2.value).to eq("value2")
      end
    end

    context "with attributes" do
      let(:xml) { Nokogiri::XML('<root id="123" name="test">content</root>') }

      it "preserves attributes" do
        tree = adapter.to_tree(xml)

        expect(tree.attributes).to eq({
          "id" => "123",
          "name" => "test"
        })
        expect(tree.value).to eq("content")
      end
    end

    context "with mixed content" do
      let(:xml) do
        Nokogiri::XML(<<~XML)
          <root>
            <parent>
              <child>nested</child>
            </parent>
          </root>
        XML
      end

      it "converts deeply nested structure" do
        tree = adapter.to_tree(xml)

        parent = tree.children[0]
        expect(parent.label).to eq("parent")

        child = parent.children[0]
        expect(child.label).to eq("child")
        expect(child.value).to eq("nested")
      end
    end

    context "with empty element" do
      let(:xml) { Nokogiri::XML("<root></root>") }

      it "converts to TreeNode with nil value" do
        tree = adapter.to_tree(xml)

        expect(tree.label).to eq("root")
        expect(tree.value).to be_nil
        expect(tree.children).to be_empty
      end
    end

    context "with whitespace-only content" do
      let(:xml) { Nokogiri::XML("<root>   \n  </root>") }

      it "treats whitespace-only as nil" do
        tree = adapter.to_tree(xml)

        expect(tree.value).to be_nil
      end
    end
  end

  describe "#from_tree" do
    context "with simple TreeNode" do
      let(:tree_node) do
        Canon::TreeDiff::Core::TreeNode.new(
          label: "root",
          value: "content"
        )
      end

      it "converts back to XML" do
        result = adapter.from_tree(tree_node)

        expect(result).to be_a(Nokogiri::XML::Document)
        expect(result.root.name).to eq("root")
        expect(result.root.content).to eq("content")
      end
    end

    context "with nested TreeNode" do
      let(:tree_node) do
        root = Canon::TreeDiff::Core::TreeNode.new(label: "root")
        child1 = Canon::TreeDiff::Core::TreeNode.new(
          label: "child1",
          value: "value1"
        )
        child2 = Canon::TreeDiff::Core::TreeNode.new(
          label: "child2",
          value: "value2"
        )
        root.add_child(child1)
        root.add_child(child2)
        root
      end

      it "converts nested structure to XML" do
        result = adapter.from_tree(tree_node)

        expect(result.root.name).to eq("root")
        expect(result.root.children.size).to eq(2)

        children = result.root.element_children
        expect(children[0].name).to eq("child1")
        expect(children[0].content).to eq("value1")
        expect(children[1].name).to eq("child2")
        expect(children[1].content).to eq("value2")
      end
    end

    context "with attributes" do
      let(:tree_node) do
        Canon::TreeDiff::Core::TreeNode.new(
          label: "root",
          value: "content",
          attributes: { "id" => "123", "name" => "test" }
        )
      end

      it "preserves attributes" do
        result = adapter.from_tree(tree_node)

        expect(result.root["id"]).to eq("123")
        expect(result.root["name"]).to eq("test")
        expect(result.root.content).to eq("content")
      end
    end
  end

  describe "round-trip conversion" do
    let(:xml_string) do
      <<~XML
        <book id="1">
          <title>The Great Gatsby</title>
          <author>F. Scott Fitzgerald</author>
          <year>1925</year>
          <metadata>
            <publisher>Scribner</publisher>
            <isbn>978-0-7432-7356-5</isbn>
          </metadata>
        </book>
      XML
    end

    it "maintains structure through round-trip" do
      original = Nokogiri::XML(xml_string)
      tree = adapter.to_tree(original)
      result = adapter.from_tree(tree)

      # Compare structure
      expect(result.root.name).to eq(original.root.name)
      expect(result.root["id"]).to eq(original.root["id"])

      # Compare children count
      expect(result.root.element_children.size).to eq(
        original.root.element_children.size
      )

      # Compare specific elements
      original_title = original.at_css("title")
      result_title = result.at_css("title")
      expect(result_title.content).to eq(original_title.content)

      original_publisher = original.at_css("metadata publisher")
      result_publisher = result.at_css("metadata publisher")
      expect(result_publisher.content).to eq(original_publisher.content)
    end
  end
end
