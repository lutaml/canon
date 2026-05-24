# frozen_string_literal: true

require "spec_helper"
require "canon/comparison/node_inspector"

RSpec.describe Canon::Comparison::NodeInspector do
  describe ".text_node?" do
    context "with Canon::Xml::Nodes::TextNode" do
      it "returns true" do
        node = Canon::Xml::Nodes::TextNode.new(value: "hello")
        expect(described_class.text_node?(node)).to be true
      end
    end

    context "with Canon::Xml::Nodes::ElementNode" do
      it "returns false" do
        node = Canon::Xml::Nodes::ElementNode.new(name: "div")
        expect(described_class.text_node?(node)).to be false
      end
    end

    context "with Nokogiri text node" do
      it "returns true" do
        doc = Nokogiri::XML("<root>text</root>")
        text = doc.at_xpath("//text()")
        expect(described_class.text_node?(text)).to be true
      end
    end

    context "with Nokogiri element node" do
      it "returns false" do
        doc = Nokogiri::XML("<root><child/></root>")
        elem = doc.at_xpath("//child")
        expect(described_class.text_node?(elem)).to be false
      end
    end

    context "with nil" do
      it "returns false" do
        expect(described_class.text_node?(nil)).to be false
      end
    end

    context "with Moxml::Text" do
      it "returns true" do
        doc = Moxml.new.parse("<root>text</root>")
        text = doc.xpath("/root/text()").first
        expect(described_class.text_node?(text)).to be true
      end
    end
  end

  describe ".element_node?" do
    context "with Canon::Xml::Nodes::ElementNode" do
      it "returns true" do
        node = Canon::Xml::Nodes::ElementNode.new(name: "div")
        expect(described_class.element_node?(node)).to be true
      end
    end

    context "with Canon::Xml::Nodes::TextNode" do
      it "returns false" do
        node = Canon::Xml::Nodes::TextNode.new(value: "hello")
        expect(described_class.element_node?(node)).to be false
      end
    end

    context "with Nokogiri element" do
      it "returns true" do
        doc = Nokogiri::XML("<root><child/></root>")
        elem = doc.at_xpath("//child")
        expect(described_class.element_node?(elem)).to be true
      end
    end

    context "with nil" do
      it "returns false" do
        expect(described_class.element_node?(nil)).to be false
      end
    end
  end

  describe ".comment_node?" do
    context "with Canon::Xml::Nodes::CommentNode" do
      it "returns true" do
        node = Canon::Xml::Nodes::CommentNode.new(value: "a comment")
        expect(described_class.comment_node?(node)).to be true
      end
    end

    context "with Nokogiri comment" do
      it "returns true" do
        doc = Nokogiri::XML("<root><!-- comment --></root>")
        comment = doc.at_xpath("//comment()")
        expect(described_class.comment_node?(comment)).to be true
      end
    end

    context "with Nokogiri text node" do
      it "returns false" do
        doc = Nokogiri::XML("<root>text</root>")
        text = doc.at_xpath("//text()")
        expect(described_class.comment_node?(text)).to be false
      end
    end

    context "with nil" do
      it "returns false" do
        expect(described_class.comment_node?(nil)).to be false
      end
    end
  end

  describe ".whitespace_only_text?" do
    it "returns true for whitespace-only Canon text node" do
      node = Canon::Xml::Nodes::TextNode.new(value: "  \n\t  ")
      expect(described_class.whitespace_only_text?(node)).to be true
    end

    it "returns false for content-bearing Canon text node" do
      node = Canon::Xml::Nodes::TextNode.new(value: "hello")
      expect(described_class.whitespace_only_text?(node)).to be false
    end

    it "returns false for empty Canon text node" do
      node = Canon::Xml::Nodes::TextNode.new(value: "")
      expect(described_class.whitespace_only_text?(node)).to be false
    end

    it "returns true for Nokogiri whitespace-only text" do
      doc = Nokogiri::XML("<root>  \n  </root>")
      text = doc.at_xpath("//text()")
      expect(described_class.whitespace_only_text?(text)).to be true
    end

    it "returns false for non-text node" do
      node = Canon::Xml::Nodes::ElementNode.new(name: "div")
      expect(described_class.whitespace_only_text?(node)).to be false
    end
  end

  describe ".name" do
    it "returns name for Canon ElementNode" do
      node = Canon::Xml::Nodes::ElementNode.new(name: "div")
      expect(described_class.name(node)).to eq("div")
    end

    it "returns name for Canon TextNode" do
      node = Canon::Xml::Nodes::TextNode.new(value: "hello")
      expect(described_class.name(node)).to eq("#text")
    end

    it "returns name for Nokogiri element" do
      doc = Nokogiri::XML("<root><child/></root>")
      elem = doc.at_xpath("//child")
      expect(described_class.name(elem)).to eq("child")
    end

    it "returns label for TreeNode" do
      tn = Canon::TreeDiff::Core::TreeNode.new(label: "div")
      expect(described_class.name(tn)).to eq("div")
    end

    it "returns nil for nil" do
      expect(described_class.name(nil)).to be_nil
    end
  end

  describe ".parent" do
    it "returns parent for Canon node" do
      root = Canon::Xml::Nodes::ElementNode.new(name: "root")
      child = Canon::Xml::Nodes::ElementNode.new(name: "child")
      root.add_child(child)
      expect(described_class.parent(child)).to eq(root)
    end

    it "returns parent for Nokogiri node" do
      doc = Nokogiri::XML("<root><child/></root>")
      child = doc.at_xpath("//child")
      expect(described_class.parent(child).name).to eq("root")
    end

    it "returns nil for nil" do
      expect(described_class.parent(nil)).to be_nil
    end
  end

  describe ".children" do
    it "returns children for Canon node" do
      root = Canon::Xml::Nodes::ElementNode.new(name: "root")
      child = Canon::Xml::Nodes::ElementNode.new(name: "child")
      root.add_child(child)
      expect(described_class.children(root)).to eq([child])
    end

    it "returns children for Nokogiri node" do
      doc = Nokogiri::XML("<root><a/><b/></root>")
      root = doc.at_xpath("//root")
      expect(described_class.children(root).length).to eq(2)
    end

    it "returns [] for nil" do
      expect(described_class.children(nil)).to eq([])
    end

    it "returns children for TreeNode" do
      child = Canon::TreeDiff::Core::TreeNode.new(label: "child")
      tn = Canon::TreeDiff::Core::TreeNode.new(label: "root", children: [child])
      child.instance_variable_set(:@parent, tn)
      expect(described_class.children(tn)).to eq([child])
    end
  end

  describe ".text_content" do
    it "returns value for Canon TextNode" do
      node = Canon::Xml::Nodes::TextNode.new(value: "hello world")
      expect(described_class.text_content(node)).to eq("hello world")
    end

    it "returns concatenated text for Canon ElementNode" do
      root = Canon::Xml::Nodes::ElementNode.new(name: "p")
      root.add_child(Canon::Xml::Nodes::TextNode.new(value: "hello "))
      root.add_child(Canon::Xml::Nodes::TextNode.new(value: "world"))
      expect(described_class.text_content(root)).to eq("hello world")
    end

    it "returns content for Nokogiri node" do
      doc = Nokogiri::XML("<root>hello</root>")
      text = doc.at_xpath("//text()")
      expect(described_class.text_content(text)).to eq("hello")
    end

    it "returns content for Moxml::Text" do
      doc = Moxml.new.parse("<root>hello</root>")
      text = doc.xpath("/root/text()").first
      expect(described_class.text_content(text)).to eq("hello")
    end
  end

  describe ".node_type" do
    it "returns :text for Canon TextNode" do
      node = Canon::Xml::Nodes::TextNode.new(value: "hello")
      expect(described_class.node_type(node)).to eq(:text)
    end

    it "returns :element for Canon ElementNode" do
      node = Canon::Xml::Nodes::ElementNode.new(name: "div")
      expect(described_class.node_type(node)).to eq(:element)
    end

    it "returns :comment for Canon CommentNode" do
      node = Canon::Xml::Nodes::CommentNode.new(value: "comment")
      expect(described_class.node_type(node)).to eq(:comment)
    end

    it "returns symbol for Nokogiri element" do
      doc = Nokogiri::XML("<root><child/></root>")
      elem = doc.at_xpath("//child")
      expect(described_class.node_type(elem)).to eq(:element)
    end

    it "returns symbol for Nokogiri text" do
      doc = Nokogiri::XML("<root>text</root>")
      text = doc.at_xpath("//text()")
      expect(described_class.node_type(text)).to eq(:text)
    end

    it "returns nil for nil" do
      expect(described_class.node_type(nil)).to be_nil
    end
  end

  describe ".attribute_value" do
    it "returns attribute value for Canon ElementNode" do
      node = Canon::Xml::Nodes::ElementNode.new(name: "div")
      node.add_attribute(Canon::Xml::Nodes::AttributeNode.new(name: "class",
                                                              value: "foo"))
      expect(described_class.attribute_value(node, "class")).to eq("foo")
    end

    it "returns nil for missing attribute" do
      node = Canon::Xml::Nodes::ElementNode.new(name: "div")
      expect(described_class.attribute_value(node, "class")).to be_nil
    end

    it "returns attribute value for Nokogiri element" do
      doc = Nokogiri::XML('<div class="foo"/>')
      elem = doc.at_xpath("//div")
      expect(described_class.attribute_value(elem, "class")).to eq("foo")
    end

    it "returns nil for TextNode" do
      node = Canon::Xml::Nodes::TextNode.new(value: "hello")
      expect(described_class.attribute_value(node, "class")).to be_nil
    end
  end

  describe ".namespace_uri" do
    it "returns namespace URI for Canon ElementNode" do
      node = Canon::Xml::Nodes::ElementNode.new(name: "div",
                                                namespace_uri: "http://example.com")
      expect(described_class.namespace_uri(node)).to eq("http://example.com")
    end

    it "returns nil for Canon TextNode" do
      node = Canon::Xml::Nodes::TextNode.new(value: "hello")
      expect(described_class.namespace_uri(node)).to be_nil
    end

    it "returns namespace URI for Nokogiri element" do
      doc = Nokogiri::XML('<root xmlns:ns="http://example.com"><ns:child/></root>')
      elem = doc.at_xpath("//ns:child")
      expect(described_class.namespace_uri(elem)).to eq("http://example.com")
    end
  end

  describe ".noise_dimension_for" do
    it "returns :whitespace_adjacency for whitespace-only text" do
      node = Canon::Xml::Nodes::TextNode.new(value: "  \n  ")
      expect(described_class.noise_dimension_for(node)).to eq(:whitespace_adjacency)
    end

    it "returns :comments for comment node" do
      node = Canon::Xml::Nodes::CommentNode.new(value: "comment")
      expect(described_class.noise_dimension_for(node)).to eq(:comments)
    end

    it "returns nil for content-bearing text" do
      node = Canon::Xml::Nodes::TextNode.new(value: "hello")
      expect(described_class.noise_dimension_for(node)).to be_nil
    end

    it "returns nil for element node" do
      node = Canon::Xml::Nodes::ElementNode.new(name: "div")
      expect(described_class.noise_dimension_for(node)).to be_nil
    end
  end

  describe ".noise_node?" do
    it "returns true for whitespace-only text" do
      node = Canon::Xml::Nodes::TextNode.new(value: "  \n  ")
      expect(described_class.noise_node?(node)).to be true
    end

    it "returns false for content-bearing text" do
      node = Canon::Xml::Nodes::TextNode.new(value: "hello")
      expect(described_class.noise_node?(node)).to be false
    end
  end

  describe ".parse_errors" do
    it "returns [] for nil" do
      expect(described_class.parse_errors(nil)).to eq([])
    end

    it "returns parse_errors for Canon node" do
      node = Canon::Xml::Nodes::ElementNode.new(name: "div")
      node.parse_errors = ["error1", "error2"]
      expect(described_class.parse_errors(node)).to eq(["error1", "error2"])
    end

    it "returns [] for Canon node with no errors" do
      node = Canon::Xml::Nodes::ElementNode.new(name: "div")
      expect(described_class.parse_errors(node)).to eq([])
    end
  end

  describe ".document?" do
    it "returns true for Canon RootNode" do
      node = Canon::Xml::Nodes::RootNode.new
      expect(described_class.document?(node)).to be true
    end

    it "returns false for Canon ElementNode" do
      node = Canon::Xml::Nodes::ElementNode.new(name: "div")
      expect(described_class.document?(node)).to be false
    end
  end
end
