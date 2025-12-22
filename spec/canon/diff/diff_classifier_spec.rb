# frozen_string_literal: true

require "spec_helper"
require "canon/diff/diff_classifier"
require "canon/diff/diff_node"
require "canon/comparison/match_options"

RSpec.describe Canon::Diff::DiffClassifier do
  describe "#classify" do
    describe "comment dimension classification" do
      context "when comments behavior is :ignore" do
        let(:match_options_hash) { { comments: :ignore } }
        let(:match_options) do
          Canon::Comparison::ResolvedMatchOptions.new(
            match_options_hash,
            format: :xml,
          )
        end
        let(:classifier) { described_class.new(match_options) }

        it "classifies comment differences as non-normative (informative)" do
          # Create actual comment nodes from parsed XML
          require "canon/xml/data_model"
          xml1 = "<root><!-- comment 1 --></root>"
          xml2 = "<root><!-- comment 2 --></root>"

          doc1 = Canon::Xml::DataModel.from_xml(xml1)
          doc2 = Canon::Xml::DataModel.from_xml(xml2)

          comment1 = doc1.children.first
          comment2 = doc2.children.first

          diff_node = Canon::Diff::DiffNode.new(
            node1: comment1,
            node2: comment2,
            dimension: :comments,
            reason: "comment content differs",
          )

          classifier.classify(diff_node)

          # When comments: :ignore, they are non-normative (informative)
          # Classification is based on match profile, not content
          expect(diff_node.formatting?).to be false
          expect(diff_node.normative?).to be false
          expect(diff_node.informative?).to be true
        end

        it "classifies comments as non-normative" do
          require "canon/xml/data_model"
          xml1 = "<root><!-- v1 --></root>"
          xml2 = "<root><!-- v2 --></root>"

          doc1 = Canon::Xml::DataModel.from_xml(xml1)
          doc2 = Canon::Xml::DataModel.from_xml(xml2)

          comment1 = doc1.children.first
          comment2 = doc2.children.first

          diff_node = Canon::Diff::DiffNode.new(
            node1: comment1,
            node2: comment2,
            dimension: :comments,
            reason: "comment content differs",
          )

          result = classifier.classify(diff_node)

          expect(result.normative?).to be false
        end

        it "returns the same diff_node instance" do
          require "canon/xml/data_model"
          xml1 = "<root><!-- v1 --></root>"
          xml2 = "<root><!-- v2 --></root>"

          doc1 = Canon::Xml::DataModel.from_xml(xml1)
          doc2 = Canon::Xml::DataModel.from_xml(xml2)

          comment1 = doc1.children.first
          comment2 = doc2.children.first

          diff_node = Canon::Diff::DiffNode.new(
            node1: comment1,
            node2: comment2,
            dimension: :comments,
            reason: "comment differs",
          )

          result = classifier.classify(diff_node)

          expect(result).to be(diff_node)
        end
      end

      context "when comments behavior is :strict" do
        let(:match_options_hash) { { comments: :strict } }
        let(:match_options) do
          Canon::Comparison::ResolvedMatchOptions.new(
            match_options_hash,
            format: :xml,
          )
        end
        let(:classifier) { described_class.new(match_options) }

        it "classifies comment differences as normative" do
          comment1 = double("CommentNode", value: " comment 1 ")
          comment2 = double("CommentNode", value: " comment 2 ")

          diff_node = Canon::Diff::DiffNode.new(
            node1: comment1,
            node2: comment2,
            dimension: :comments,
            reason: "comment content differs",
          )

          classifier.classify(diff_node)

          expect(diff_node.formatting?).to be false
          expect(diff_node.normative?).to be true
          expect(diff_node.informative?).to be false
        end

        it "does not check formatting for normative dimensions" do
          comment1 = double("CommentNode", value: " v1 ")
          comment2 = double("CommentNode", value: " v2 ")

          diff_node = Canon::Diff::DiffNode.new(
            node1: comment1,
            node2: comment2,
            dimension: :comments,
            reason: "comment differs",
          )

          # Should not call formatting_only_diff? for normative dimensions
          expect(classifier).not_to receive(:formatting_only_diff?)

          classifier.classify(diff_node)
        end
      end
    end

    describe "text_content dimension classification" do
      context "with whitespace-only differences" do
        let(:match_options_hash) { { text_content: :ignore } }
        let(:match_options) do
          Canon::Comparison::ResolvedMatchOptions.new(
            match_options_hash,
            format: :xml,
          )
        end
        let(:classifier) { described_class.new(match_options) }

        it "classifies as formatting when only whitespace differs" do
          text1 = double("TextNode")
          text2 = double("TextNode")
          allow(text1).to receive(:value).and_return("Hello  world")
          allow(text2).to receive(:value).and_return("Hello world")

          diff_node = Canon::Diff::DiffNode.new(
            node1: text1,
            node2: text2,
            dimension: :text_content,
            reason: "text content differs",
          )

          classifier.classify(diff_node)

          expect(diff_node.formatting?).to be true
          expect(diff_node.normative?).to be false
        end
      end

      context "with semantic differences" do
        let(:match_options_hash) { { text_content: :ignore } }
        let(:match_options) do
          Canon::Comparison::ResolvedMatchOptions.new(
            match_options_hash,
            format: :xml,
          )
        end
        let(:classifier) { described_class.new(match_options) }

        it "classifies as informative when content differs" do
          text1 = double("TextNode")
          text2 = double("TextNode")
          allow(text1).to receive(:value).and_return("Hello")
          allow(text2).to receive(:value).and_return("Goodbye")

          diff_node = Canon::Diff::DiffNode.new(
            node1: text1,
            node2: text2,
            dimension: :text_content,
            reason: "text content differs",
          )

          classifier.classify(diff_node)

          expect(diff_node.formatting?).to be false
          expect(diff_node.informative?).to be true
          expect(diff_node.normative?).to be false
        end
      end
    end

    describe "structural_whitespace dimension classification" do
      context "with :ignore behavior" do
        let(:match_options_hash) { { structural_whitespace: :ignore } }
        let(:match_options) do
          Canon::Comparison::ResolvedMatchOptions.new(
            match_options_hash,
            format: :xml,
          )
        end
        let(:classifier) { described_class.new(match_options) }

        it "classifies whitespace differences as formatting" do
          # Structural whitespace nodes with content that differs only in whitespace
          ws1 = double("WhitespaceNode")
          ws2 = double("WhitespaceNode")
          allow(ws1).to receive(:value).and_return("<div>  content  </div>")
          allow(ws2).to receive(:value).and_return("<div> content </div>")

          diff_node = Canon::Diff::DiffNode.new(
            node1: ws1,
            node2: ws2,
            dimension: :structural_whitespace,
            reason: "whitespace differs",
          )

          classifier.classify(diff_node)

          expect(diff_node.formatting?).to be true
          expect(diff_node.normative?).to be false
        end
      end
    end

    describe "element_structure dimension classification" do
      let(:match_options_hash) { {} }
      let(:match_options) do
        Canon::Comparison::ResolvedMatchOptions.new(
          match_options_hash,
          format: :xml,
        )
      end
      let(:classifier) { described_class.new(match_options) }

      it "always classifies as normative" do
        elem1 = double("Element", name: "div")
        elem2 = double("Element", name: "span")

        diff_node = Canon::Diff::DiffNode.new(
          node1: elem1,
          node2: elem2,
          dimension: :element_structure,
          reason: "element structure differs",
        )

        classifier.classify(diff_node)

        expect(diff_node.formatting?).to be false
        expect(diff_node.normative?).to be true
      end
    end
  end

  describe "#classify_all" do
    let(:match_options_hash) { { comments: :ignore, text_content: :ignore } }
    let(:match_options) do
      Canon::Comparison::ResolvedMatchOptions.new(
        match_options_hash,
        format: :xml,
      )
    end
    let(:classifier) { described_class.new(match_options) }

    it "classifies multiple diff nodes" do
      require "canon/xml/data_model"

      # Create actual nodes from parsed XML
      xml1 = "<root><!-- c1 -->Hello</root>"
      xml2 = "<root><!-- c2 -->Goodbye</root>"

      doc1 = Canon::Xml::DataModel.from_xml(xml1)
      doc2 = Canon::Xml::DataModel.from_xml(xml2)

      comment1 = doc1.children[0]
      comment2 = doc2.children[0]
      text1 = doc1.children[1]
      text2 = doc2.children[1]

      diff_nodes = [
        Canon::Diff::DiffNode.new(
          node1: comment1,
          node2: comment2,
          dimension: :comments,
          reason: "comment differs",
        ),
        Canon::Diff::DiffNode.new(
          node1: text1,
          node2: text2,
          dimension: :text_content,
          reason: "text differs",
        ),
      ]

      classifier.classify_all(diff_nodes)

      # Both dimensions are :ignore, so both are informative (non-normative)
      expect(diff_nodes[0].informative?).to be true
      expect(diff_nodes[1].informative?).to be true
    end
  end
end
