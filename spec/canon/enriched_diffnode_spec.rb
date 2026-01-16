# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Enriched DiffNode metadata" do
  describe "DOM algorithm (XmlComparator)" do
    it "populates path on DiffNodes" do
      xml1 = "<root><div><p>Text</p></div></root>"
      xml2 = "<root><div><p>Changed</p></div></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2,
                                             diff_algorithm: :dom,
                                             verbose: true)

      expect(result.differences).not_to be_empty

      diff = result.differences.first
      expect(diff).to respond_to(:path)
      expect(diff.path).to be_a(String)
      expect(diff.path).not_to be_empty
      # Should contain ordinal indices
      expect(diff.path).to match(/\[\d+\]/)
    end

    it "populates serialized_before and serialized_after" do
      xml1 = "<root><div><p>Original</p></div></root>"
      xml2 = "<root><div><p>Modified</p></div></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2,
                                             diff_algorithm: :dom,
                                             verbose: true)

      expect(result.differences).not_to be_empty

      diff = result.differences.first
      expect(diff).to respond_to(:serialized_before)
      expect(diff).to respond_to(:serialized_after)

      expect(diff.serialized_before).to be_a(String)
      expect(diff.serialized_after).to be_a(String)

      # Serialized content should reflect the actual change
      expect(diff.serialized_before).to include("Original")
      expect(diff.serialized_after).to include("Modified")
    end

    it "populates attributes_before and attributes_after for attribute changes" do
      xml1 = "<root><div id='old'>Text</div></root>"
      xml2 = "<root><div id='new'>Text</div></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2,
                                             diff_algorithm: :dom,
                                             verbose: true,
                                             match: { attribute_values: :strict })

      expect(result.differences).not_to be_empty

      diff = result.differences.find { |d| d.dimension == :attribute_values }
      expect(diff).not_to be_nil

      expect(diff).to respond_to(:attributes_before)
      expect(diff).to respond_to(:attributes_after)

      expect(diff.attributes_before).to be_a(Hash)
      expect(diff.attributes_after).to be_a(Hash)

      expect(diff.attributes_before["id"]).to eq("old")
      expect(diff.attributes_after["id"]).to eq("new")
    end

    it "populates path for nested elements" do
      xml1 = "<root><div><span><p>Text</p></span></div></root>"
      xml2 = "<root><div><span><p>Changed</p></span></div></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2,
                                             diff_algorithm: :dom,
                                             verbose: true)

      expect(result.differences).not_to be_empty

      diff = result.differences.first
      expect(diff.path).to include("/root[0]/div[0]/span[0]/p[0]")
    end

    it "handles nil nodes for INSERT operations" do
      xml1 = "<root><div><p>A</p><p>B</p></div></root>"
      xml2 = "<root><div><p>A</p><p>B</p><p>C</p></div></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2,
                                             diff_algorithm: :dom,
                                             verbose: true)

      # Find the element_structure difference (different number of children)
      insert_diff = result.differences.find do |d|
        d.dimension == :element_structure && d.node1.nil? && !d.node2.nil?
      end

      expect(insert_diff).not_to be_nil

      # For INSERT: node1 is nil, node2 is present
      expect(insert_diff.node1).to be_nil
      expect(insert_diff.node2).not_to be_nil

      # serialized_before should be nil, serialized_after should have content
      expect(insert_diff.serialized_before).to be_nil
      expect(insert_diff.serialized_after).to be_a(String)
      expect(insert_diff.serialized_after).to include("<p")
    end

    it "handles nil nodes for DELETE operations" do
      xml1 = "<root><div><p>A</p><p>B</p><p>C</p></div></root>"
      xml2 = "<root><div><p>A</p><p>B</p></div></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2,
                                             diff_algorithm: :dom,
                                             verbose: true)

      # Find the element_structure difference (different number of children)
      delete_diff = result.differences.find do |d|
        d.dimension == :element_structure && !d.node1.nil? && d.node2.nil?
      end

      expect(delete_diff).not_to be_nil

      # For DELETE: node1 is present, node2 is nil
      expect(delete_diff.node1).not_to be_nil
      expect(delete_diff.node2).to be_nil

      # serialized_before should have content, serialized_after should be nil
      expect(delete_diff.serialized_before).to be_a(String)
      expect(delete_diff.serialized_before).to include("<p")
      expect(delete_diff.serialized_after).to be_nil
    end
  end

  describe "Semantic algorithm (OperationConverter)" do
    it "populates path on DiffNodes from semantic diff" do
      xml1 = "<root><item>A</item><item>B</item></root>"
      xml2 = "<root><item>A</item><item>C</item></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2,
                                             diff_algorithm: :semantic,
                                             verbose: true)

      expect(result.differences).not_to be_empty

      diff = result.differences.first
      expect(diff).to respond_to(:path)
      expect(diff.path).to be_a(String)
      expect(diff.path).not_to be_empty
      # Should contain ordinal indices
      expect(diff.path).to match(/\[\d+\]/)
    end

    it "populates serialized_after for INSERT operations" do
      xml1 = "<root><item>A</item></root>"
      xml2 = "<root><item>A</item><item>B</item></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2,
                                             diff_algorithm: :semantic,
                                             verbose: true)

      insert_diff = result.differences.find do |d|
        d.reason.include?("inserted")
      end
      expect(insert_diff).not_to be_nil

      expect(insert_diff.serialized_before).to be_nil
      expect(insert_diff.serialized_after).to be_a(String)
      expect(insert_diff.serialized_after).to include("<item")
    end

    it "populates serialized_before for DELETE operations" do
      xml1 = "<root><item>A</item><item>B</item></root>"
      xml2 = "<root><item>A</item></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2,
                                             diff_algorithm: :semantic,
                                             verbose: true)

      delete_diff = result.differences.find { |d| d.reason.include?("deleted") }
      expect(delete_diff).not_to be_nil

      expect(delete_diff.serialized_before).to be_a(String)
      expect(delete_diff.serialized_before).to include("<item")
      expect(delete_diff.serialized_after).to be_nil
    end

    it "populates both serialized_before and serialized_after for UPDATE operations" do
      xml1 = "<root><item>Original</item></root>"
      xml2 = "<root><item>Modified</item></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2,
                                             diff_algorithm: :semantic,
                                             verbose: true)

      update_diff = result.differences.find { |d| d.dimension == :text_content }
      expect(update_diff).not_to be_nil

      expect(update_diff.serialized_before).to be_a(String)
      expect(update_diff.serialized_after).to be_a(String)
      expect(update_diff.serialized_before).to include("Original")
      expect(update_diff.serialized_after).to include("Modified")
    end

    it "uses TreeNode attributes when available" do
      xml1 = "<root><div id='old'>Text</div></root>"
      xml2 = "<root><div id='new'>Text</div></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2,
                                             diff_algorithm: :semantic,
                                             verbose: true,
                                             match: { attribute_values: :strict })

      attr_diff = result.differences.find do |d|
        d.dimension == :attribute_values
      end
      expect(attr_diff).not_to be_nil

      expect(attr_diff.attributes_before).to be_a(Hash)
      expect(attr_diff.attributes_after).to be_a(Hash)
      expect(attr_diff.attributes_before["id"]).to eq("old")
      expect(attr_diff.attributes_after["id"]).to eq("new")
    end
  end

  describe "HTML comparisons" do
    it "populates enriched metadata for HTML elements" do
      html1 = "<html><body><div><p>Original</p></div></body></html>"
      html2 = "<html><body><div><p>Changed</p></div></body></html>"

      result = Canon::Comparison.equivalent?(html1, html2,
                                             format: :html,
                                             diff_algorithm: :dom,
                                             verbose: true)

      expect(result.differences).not_to be_empty

      diff = result.differences.first
      expect(diff.path).to be_a(String)
      expect(diff.serialized_before).to be_a(String)
      expect(diff.serialized_after).to be_a(String)
    end

    it "handles HTML-specific attributes" do
      html1 = "<div class='old-class'>Text</div>"
      html2 = "<div class='new-class'>Text</div>"

      result = Canon::Comparison.equivalent?(html1, html2,
                                             format: :html,
                                             diff_algorithm: :dom,
                                             verbose: true,
                                             match: { attribute_values: :strict })

      expect(result.differences).not_to be_empty

      diff = result.differences.first
      expect(diff.attributes_before).to be_a(Hash)
      expect(diff.attributes_after).to be_a(Hash)
      expect(diff.attributes_before["class"]).to eq("old-class")
      expect(diff.attributes_after["class"]).to eq("new-class")
    end
  end
end
