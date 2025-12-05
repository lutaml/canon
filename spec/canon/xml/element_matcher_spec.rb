# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/canon/xml/element_matcher"

RSpec.describe Canon::Xml::ElementMatcher do
  let(:matcher) { described_class.new }

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
        inserted_root = matches.find { |m| m.inserted? && m.elem2.name == "root" }

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
        child_matched = matches.find { |m| m.matched? && m.elem1&.name == "child" }
        expect(child_matched).to be_nil

        deleted_child = matches.find { |m| m.deleted? && m.elem1&.name == "child" }
        inserted_child = matches.find { |m| m.inserted? && m.elem2&.name == "child" }

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
        child_match = matches.find { |m| m.elem1&.name == "child" && m.matched? }
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
        item_matches = matches.select { |m| m.matched? && m.elem1&.name == "item" }
        expect(item_matches.length).to eq(2)
      end

      it "correctly handles elements with no namespace" do
        xml1 = '<root><child>content</child></root>'
        xml2 = '<root><child>content</child></root>'

        root1 = Canon::Xml::DataModel.from_xml(xml1)
        root2 = Canon::Xml::DataModel.from_xml(xml2)

        matches = matcher.match_trees(root1, root2)

        child_match = matches.find { |m| m.elem1&.name == "child" && m.matched? }
        expect(child_match).not_to be_nil
      end

      it "detects mixed namespace and no-namespace elements as different" do
        xml1 = '<root><child>content</child></root>'
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
        expect(item_match.elem1.attribute_nodes.find { |a| a.name == "id" }.value).to eq("unique-1")
      end
    end
  end
end
