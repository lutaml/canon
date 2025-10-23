# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Semantic Diff Integration" do
  describe "Canon::Comparison.equivalent? with diff_algorithm: :semantic" do
    context "with XML documents" do
      let(:xml1) { "<root><item>Hello</item></root>" }
      let(:xml2) { "<root><item>Hello</item></root>" }

      it "returns true for identical documents" do
        result = Canon::Comparison.equivalent?(xml1, xml2, diff_algorithm: :semantic)
        expect(result).to be true
      end

      it "returns false for different documents" do
        xml_different = "<root><item>Goodbye</item></root>"
        result = Canon::Comparison.equivalent?(xml1, xml_different, diff_algorithm: :semantic)
        expect(result).to be false
      end

      it "returns ComparisonResult in verbose mode" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          diff_algorithm: :semantic,
          verbose: true
        )

        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.equivalent?).to be true
        expect(result.differences).to be_empty
      end

      it "includes differences in ComparisonResult when documents differ" do
        xml_different = "<root><item>Goodbye</item></root>"
        result = Canon::Comparison.equivalent?(
          xml1, xml_different,
          diff_algorithm: :semantic,
          verbose: true
        )

        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.equivalent?).to be false
        expect(result.differences).not_to be_empty
        expect(result.differences.first).to be_a(Canon::Diff::DiffNode)
      end
    end

    context "with HTML documents" do
      let(:html1) { "<div><p>Test</p></div>" }
      let(:html2) { "<div><p>Test</p></div>" }

      it "works with HTML format" do
        result = Canon::Comparison.equivalent?(
          html1, html2,
          format: :html,
          diff_algorithm: :semantic
        )
        expect(result).to be true
      end
    end

    context "with JSON documents" do
      let(:json1) { '{"name": "test", "value": 42}' }
      let(:json2) { '{"name": "test", "value": 42}' }

      it "works with JSON format" do
        result = Canon::Comparison.equivalent?(
          json1, json2,
          format: :json,
          diff_algorithm: :semantic
        )
        expect(result).to be true
      end
    end

    context "with YAML documents" do
      let(:yaml1) { "name: test\nvalue: 42" }
      let(:yaml2) { "name: test\nvalue: 42" }

      it "works with YAML format" do
        result = Canon::Comparison.equivalent?(
          yaml1, yaml2,
          format: :yaml,
          diff_algorithm: :semantic
        )
        expect(result).to be true
      end
    end

    context "with match options" do
      let(:xml1) { '<root id="1" class="foo">Content</root>' }
      let(:xml2) { '<root class="foo" id="1">Content</root>' }

      it "respects attribute_order match option" do
        # Should be equivalent with attribute_order: :ignore
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          diff_algorithm: :semantic,
          match: { attribute_order: :ignore }
        )
        expect(result).to be true
      end

      it "can detect element structure changes" do
        xml_added = '<root><item>New</item></root>'
        xml_empty = '<root></root>'

        result = Canon::Comparison.equivalent?(
          xml_empty, xml_added,
          diff_algorithm: :semantic,
          verbose: true
        )

        expect(result.equivalent?).to be false
        expect(result.differences.first.dimension).to eq(:element_structure)
      end
    end
  end

  describe "RSpec matchers with diff_algorithm" do
    context "be_xml_equivalent_to" do
      it "supports semantic diff algorithm" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root><item>Test</item></root>"

        expect(xml1).to be_xml_equivalent_to(xml2, diff_algorithm: :semantic)
      end

      it "fails when documents differ" do
        xml1 = "<root><item>Test1</item></root>"
        xml2 = "<root><item>Test2</item></root>"

        expect do
          expect(xml1).to be_xml_equivalent_to(xml2, diff_algorithm: :semantic)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
      end
    end
  end

  describe "ComparisonResult compatibility" do
    let(:xml1) { "<root><a>1</a><b>2</b></root>" }
    let(:xml2) { "<root><a>1</a><b>3</b></root>" }

    it "ComparisonResult from semantic diff has same interface as DOM diff" do
      semantic_result = Canon::Comparison.equivalent?(
        xml1, xml2,
        diff_algorithm: :semantic,
        verbose: true
      )

      dom_result = Canon::Comparison.equivalent?(
        xml1, xml2,
        diff_algorithm: :dom,
        verbose: true
      )

      # Both should respond to the same methods
      expect(semantic_result).to respond_to(:equivalent?)
      expect(semantic_result).to respond_to(:differences)
      expect(semantic_result).to respond_to(:preprocessed_strings)
      expect(semantic_result).to respond_to(:format)

      expect(dom_result).to respond_to(:equivalent?)
      expect(dom_result).to respond_to(:differences)
      expect(dom_result).to respond_to(:preprocessed_strings)
      expect(dom_result).to respond_to(:format)

      # Both should indicate non-equivalence
      expect(semantic_result.equivalent?).to be false
      expect(dom_result.equivalent?).to be false
    end

    it "differences are DiffNode objects in both cases" do
      semantic_result = Canon::Comparison.equivalent?(
        xml1, xml2,
        diff_algorithm: :semantic,
        verbose: true
      )

      dom_result = Canon::Comparison.equivalent?(
        xml1, xml2,
        diff_algorithm: :dom,
        verbose: true
      )

      expect(semantic_result.differences).to all(be_a(Canon::Diff::DiffNode))
      expect(dom_result.differences).to all(be_a(Canon::Diff::DiffNode))
    end
  end

  describe "format auto-detection with semantic diff" do
    it "auto-detects XML format" do
      xml1 = "<root>Test</root>"
      xml2 = "<root>Test</root>"

      result = Canon::Comparison.equivalent?(xml1, xml2, diff_algorithm: :semantic)
      expect(result).to be true
    end

    it "auto-detects JSON format" do
      json1 = '{"test": "value"}'
      json2 = '{"test": "value"}'

      result = Canon::Comparison.equivalent?(json1, json2, diff_algorithm: :semantic)
      expect(result).to be true
    end

    it "auto-detects YAML format" do
      yaml1 = "test: value"
      yaml2 = "test: value"

      result = Canon::Comparison.equivalent?(yaml1, yaml2, diff_algorithm: :semantic)
      expect(result).to be true
    end
  end

  describe "error handling" do
    it "raises error for format mismatch" do
      xml = "<root>Test</root>"
      json = '{"test": "value"}'

      expect do
        Canon::Comparison.equivalent?(xml, json, diff_algorithm: :semantic)
      end.to raise_error(Canon::CompareFormatMismatchError)
    end
  end

  describe "backward compatibility" do
    it "defaults to DOM diff when diff_algorithm not specified" do
      xml1 = "<root>Test</root>"
      xml2 = "<root>Test</root>"

      # Should use DOM diff by default
      result = Canon::Comparison.equivalent?(xml1, xml2)
      expect(result).to be true
    end

    it "explicit :dom algorithm works" do
      xml1 = "<root>Test</root>"
      xml2 = "<root>Test</root>"

      result = Canon::Comparison.equivalent?(xml1, xml2, diff_algorithm: :dom)
      expect(result).to be true
    end
  end

  describe "ComparisonResult.operations" do
    it "provides access to tree diff operations" do
      xml1 = "<root><item>Test</item></root>"
      xml2 = "<root><item>Changed</item><new>Added</new></root>"

      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        diff_algorithm: :semantic,
        verbose: true
      )

      expect(result).to respond_to(:operations)
      expect(result.operations).to be_an(Array)
      expect(result.operations).not_to be_empty
      expect(result.operations.first).to respond_to(:type)
    end

    it "returns empty array for DOM diff" do
      xml1 = "<root>Test</root>"
      xml2 = "<root>Test2</root>"

      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        diff_algorithm: :dom,
        verbose: true
      )

      expect(result.operations).to be_empty
    end

    it "provides tree diff statistics via match_options" do
      xml1 = "<root><item>Test</item></root>"
      xml2 = "<root><item>Test</item><new>Added</new></root>"

      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        diff_algorithm: :semantic,
        verbose: true
      )

      expect(result.match_options).to include(:tree_diff_statistics)
      stats = result.match_options[:tree_diff_statistics]
      expect(stats).to be_a(Hash)
      expect(stats).to include(:tree1_node_count, :tree2_node_count, :matched_count)
    end

    it "provides tree diff matching via match_options" do
      xml1 = "<root><item>Test</item></root>"
      xml2 = "<root><item>Test</item></root>"

      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        diff_algorithm: :semantic,
        verbose: true
      )

      expect(result.match_options).to include(:tree_diff_matching)
      matching = result.match_options[:tree_diff_matching]
      expect(matching).to respond_to(:each_pair)
    end
  end
end
