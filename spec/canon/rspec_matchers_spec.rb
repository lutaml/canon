# frozen_string_literal: true

require "spec_helper"
require "canon/rspec_matchers"

RSpec.describe Canon::RSpecMatchers do
  # Test data - minimal examples for each format
  let(:xml_original) { '<root><a b="2" c="1">text</a></root>' }
  let(:xml_reordered) { '<root><a c="1" b="2">text</a></root>' }
  let(:xml_different) { "<root><d>other</d></root>" }

  let(:yaml_original) { "---\nz: 3\na: 1\nb: 2\n" }
  let(:yaml_reordered) { "---\na: 1\nb: 2\nz: 3\n" }
  let(:yaml_different) { "---\nc: 4\n" }

  let(:json_original) { '{"z":3,"a":1,"b":2}' }
  let(:json_reordered) { '{"a":1,"b":2,"z":3}' }
  let(:json_different) { '{"c":4}' }

  describe "#be_serialization_equivalent_to" do
    it "matches equivalent XML with format parameter" do
      expect(xml_original).to be_serialization_equivalent_to(xml_reordered,
                                                             format: :xml)
    end

    it "matches equivalent YAML with format parameter" do
      expect(yaml_original).to be_serialization_equivalent_to(yaml_reordered,
                                                              format: :yaml)
    end

    it "matches equivalent JSON with format parameter" do
      expect(json_original).to be_serialization_equivalent_to(json_reordered,
                                                              format: :json)
    end

    it "raises error for unsupported format" do
      expect do
        expect(xml_original).to be_serialization_equivalent_to(xml_reordered,
                                                               format: :unsupported)
      end.to raise_error(Canon::Error, "Unsupported format: unsupported")
    end
  end

  describe "#be_xml_equivalent_to" do
    it "matches equivalent XML documents" do
      expect(xml_original).to be_xml_equivalent_to(xml_reordered)
    end

    it "does not match different XML documents" do
      expect(xml_original).not_to be_xml_equivalent_to(xml_different)
    end
  end

  describe "#be_analogous_with" do
    it "matches equivalent XML documents (legacy matcher)" do
      expect(xml_original).to be_analogous_with(xml_reordered)
    end
  end

  describe "#be_yaml_equivalent_to" do
    it "matches equivalent YAML documents" do
      expect(yaml_original).to be_yaml_equivalent_to(yaml_reordered)
    end

    it "does not match different YAML documents" do
      expect(yaml_original).not_to be_yaml_equivalent_to(yaml_different)
    end
  end

  describe "#be_json_equivalent_to" do
    it "matches equivalent JSON documents" do
      expect(json_original).to be_json_equivalent_to(json_reordered)
    end

    it "does not match different JSON documents" do
      expect(json_original).not_to be_json_equivalent_to(json_different)
    end
  end

  describe "RSpec integration" do
    it "includes matchers in RSpec context" do
      expect(self).to respond_to(:be_serialization_equivalent_to)
      expect(self).to respond_to(:be_xml_equivalent_to)
      expect(self).to respond_to(:be_analogous_with)
      expect(self).to respond_to(:be_yaml_equivalent_to)
      expect(self).to respond_to(:be_json_equivalent_to)
    end
  end
end
