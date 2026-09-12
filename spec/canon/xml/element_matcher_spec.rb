# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/canon/xml/element_matcher"

RSpec.describe Canon::Xml::ElementMatcher do
  let(:matcher) { described_class.new }

  describe "#match_children_only" do
    it "pairs one level of children and does not descend into matched pairs" do
      xml1 = '<root><a id="1"><x>t1</x></a><b/></root>'
      xml2 = '<root><a id="1"><x>t2</x></a><b/></root>'
      root1 = Canon::Xml::DataModel.from_xml(xml1).children.first
      root2 = Canon::Xml::DataModel.from_xml(xml2).children.first

      matches = matcher.match_children_only(root1.children, root2.children)

      expect(matches.map(&:status)).to all(eq(:matched))
      expect(matches.map { |m| m.elem1.name }.sort).to eq(%w[a b])
      # Single level only: nested <x> matches must not appear.
      expect(matches.flat_map { |m| m.path.flatten }).not_to include("x")
    end

    it "takes the positional fast path for pairwise-corresponding children" do
      xml1 = '<root><item id="1">a</item><item id="2">b</item><item>plain</item></root>'
      xml2 = '<root><item id="1">x</item><item id="2">y</item><item>z</item></root>'
      root1 = Canon::Xml::DataModel.from_xml(xml1).children.first
      root2 = Canon::Xml::DataModel.from_xml(xml2).children.first

      matches = matcher.match_children_only(root1.children, root2.children)

      expect(matches.map(&:status)).to all(eq(:matched))
      expect(matches.map { |m| [m.elem1.object_id, m.elem2.object_id] })
        .to eq(root1.children.each_index.map { |i| [root1.children[i].object_id, root2.children[i].object_id] })
      expect(matches.map(&:pos1)).to eq([0, 1, 2])
      expect(matches.map(&:pos2)).to eq([0, 1, 2])
    end

    it "falls back to the full matcher when identity values differ at a position" do
      xml1 = '<root><item id="1">a</item><item id="2">b</item></root>'
      xml2 = '<root><item id="1">a</item><item id="3">b</item></root>'
      root1 = Canon::Xml::DataModel.from_xml(xml1).children.first
      root2 = Canon::Xml::DataModel.from_xml(xml2).children.first

      matches = matcher.match_children_only(root1.children, root2.children)

      # The full matcher's positional phase recovers the id-changed
      # element as a match (same name, same position); the attribute
      # comparator reports the id difference itself. Positional-phase
      # matches carry subset indexes, so only pos1 == pos2 is
      # observable (position_changed? never fires for them).
      expect(matches.map(&:status)).to all(eq(:matched))
      expect(matches.map(&:pos1)).to eq(matches.map(&:pos2))
    end

    it "records deleted and inserted elements at this level" do
      xml1 = "<root><a/><b/></root>"
      xml2 = "<root><a/><c/></root>"
      root1 = Canon::Xml::DataModel.from_xml(xml1).children.first
      root2 = Canon::Xml::DataModel.from_xml(xml2).children.first

      matches = matcher.match_children_only(root1.children, root2.children)

      expect(matches.find { |m| m.matched? && m.elem1.name == "a" }).not_to be_nil
      expect(matches.find { |m| m.deleted? && m.elem1.name == "b" }).not_to be_nil
      expect(matches.find { |m| m.inserted? && m.elem2.name == "c" }).not_to be_nil
    end
  end

  describe "#match_trees" do
    context "with namespace handling" do
      it "matches elements with same name and same namespace URI" do
        xml1 = <<~XML
          <root xmlns="http://example.org/ns1">
            <child id="1">content</child>
          </root>
        XML

        xml2 = <<~XML
          <root xmlns="http://example.org/ns1">
            <child id="1">content</child>
          </root>
        XML

        root1 = Canon::Xml::DataModel.from_xml(xml1)
        root2 = Canon::Xml::DataModel.from_xml(xml2)

        matches = matcher.match_trees(root1, root2)

        # Should find matched elements
        child_matches = matches.select { |m| m.elem1&.name == "child" }
        expect(child_matches).not_to be_empty
        expect(child_matches.first.status).to eq(:matched)
      end

      it "does not match elements with same name but different namespace URIs" do
        xml1 = <<~XML
          <root xmlns="http://example.org/ns1">
            <child>content1</child>
          </root>
        XML

        xml2 = <<~XML
          <root xmlns="http://example.org/ns2">
            <child>content2</child>
          </root>
        XML

        root1 = Canon::Xml::DataModel.from_xml(xml1)
        root2 = Canon::Xml::DataModel.from_xml(xml2)

        matches = matcher.match_trees(root1, root2)

        # root elements have different namespaces - should be deleted/inserted
        root_matched = matches.find { |m| m.matched? && m.elem1.name == "root" }
        expect(root_matched).to be_nil

        # Should have deleted root from tree1 and inserted root from tree2
        deleted_root = matches.find { |m| m.deleted? && m.elem1.name == "root" }
        inserted_root = matches.find do |m|
          m.inserted? && m.elem2.name == "root"
        end

        expect(deleted_root).not_to be_nil
        expect(inserted_root).not_to be_nil
      end

      it "detects namespace inheritance vs explicit declaration differences" do
        # XML1: child inherits parent namespace
        xml1 = <<~XML
          <root xmlns="http://example.org/ns1">
            <child>content</child>
          </root>
        XML

        # XML2: child explicitly declares different namespace
        xml2 = <<~XML
          <root xmlns="http://example.org/ns1">
            <child xmlns="http://example.org/ns2">content</child>
          </root>
        XML

        root1 = Canon::Xml::DataModel.from_xml(xml1)
        root2 = Canon::Xml::DataModel.from_xml(xml2)

        matches = matcher.match_trees(root1, root2)

        # child elements have different namespaces - should be deleted/inserted
        child_matched = matches.find do |m|
          m.matched? && m.elem1&.name == "child"
        end
        expect(child_matched).to be_nil

        deleted_child = matches.find do |m|
          m.deleted? && m.elem1&.name == "child"
        end
        inserted_child = matches.find do |m|
          m.inserted? && m.elem2&.name == "child"
        end

        expect(deleted_child).not_to be_nil
        expect(inserted_child).not_to be_nil
      end

      it "includes namespace URI in match result paths" do
        xml1 = <<~XML
          <root xmlns="http://example.org/ns1">
            <child id="1">content</child>
          </root>
        XML

        xml2 = <<~XML
          <root xmlns="http://example.org/ns1">
            <child id="1">content</child>
          </root>
        XML

        root1 = Canon::Xml::DataModel.from_xml(xml1)
        root2 = Canon::Xml::DataModel.from_xml(xml2)

        matches = matcher.match_trees(root1, root2)

        # Paths should include namespace information
        child_match = matches.find do |m|
          m.elem1&.name == "child" && m.matched?
        end
        expect(child_match).not_to be_nil
        expect(child_match.path.join("/")).to include("http://example.org/ns1")
      end

      it "groups elements by name AND namespace URI for position matching" do
        xml1 = <<~XML
          <root>
            <item xmlns="http://example.org/ns1">one</item>
            <item xmlns="http://example.org/ns2">two</item>
          </root>
        XML

        xml2 = <<~XML
          <root>
            <item xmlns="http://example.org/ns1">one</item>
            <item xmlns="http://example.org/ns2">two</item>
          </root>
        XML

        root1 = Canon::Xml::DataModel.from_xml(xml1)
        root2 = Canon::Xml::DataModel.from_xml(xml2)

        matches = matcher.match_trees(root1, root2)

        # Both items should be matched despite having the same element name
        # because they're grouped by [name, namespace_uri] tuples
        item_matches = matches.select do |m|
          m.matched? && m.elem1&.name == "item"
        end
        expect(item_matches.length).to eq(2)
      end

      it "correctly handles elements with no namespace" do
        xml1 = "<root><child>content</child></root>"
        xml2 = "<root><child>content</child></root>"

        root1 = Canon::Xml::DataModel.from_xml(xml1)
        root2 = Canon::Xml::DataModel.from_xml(xml2)

        matches = matcher.match_trees(root1, root2)

        child_match = matches.find do |m|
          m.elem1&.name == "child" && m.matched?
        end
        expect(child_match).not_to be_nil
      end

      it "detects mixed namespace and no-namespace elements as different" do
        xml1 = "<root><child>content</child></root>"
        xml2 = '<root xmlns="http://example.org/ns1"><child>content</child></root>'

        root1 = Canon::Xml::DataModel.from_xml(xml1)
        root2 = Canon::Xml::DataModel.from_xml(xml2)

        matches = matcher.match_trees(root1, root2)

        # root elements have different namespaces (nil vs ns1)
        root_matched = matches.find { |m| m.matched? && m.elem1.name == "root" }
        expect(root_matched).to be_nil
      end
    end

    context "with identity attribute matching" do
      it "matches elements by id attribute across different namespaces" do
        xml1 = <<~XML
          <root xmlns="http://example.org/ns1">
            <item id="unique-1">content</item>
          </root>
        XML

        xml2 = <<~XML
          <root xmlns="http://example.org/ns1">
            <item id="unique-1">modified content</item>
          </root>
        XML

        root1 = Canon::Xml::DataModel.from_xml(xml1)
        root2 = Canon::Xml::DataModel.from_xml(xml2)

        matches = matcher.match_trees(root1, root2)

        item_match = matches.find { |m| m.elem1&.name == "item" && m.matched? }
        expect(item_match).not_to be_nil
        expect(item_match.elem1.attribute_nodes.find do |a|
          a.name == "id"
        end.value).to eq("unique-1")
      end
    end
  end
end
