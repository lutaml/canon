# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison::Dimensions::Registry do
  describe ".for" do
    context "XML format" do
      let(:set) { described_class.for(:xml) }

      it "returns a DimensionSet with :xml format" do
        expect(set).to be_a(Canon::Comparison::Dimensions::DimensionSet)
        expect(set.format).to eq(:xml)
      end

      it "has 7 dimensions" do
        expect(set.names).to eq(%i[
                                  text_content
                                  structural_whitespace
                                  attribute_presence
                                  attribute_order
                                  attribute_values
                                  element_position
                                  comments
                                ])
      end

      it "has :strict_only normative rule for structural_whitespace" do
        dim = set[:structural_whitespace]
        expect(dim.normative?(:strict)).to be true
        expect(dim.normative?(:normalize)).to be false
        expect(dim.normative?(:ignore)).to be false
      end

      it "has :behavior_not_ignore normative rule for text_content" do
        dim = set[:text_content]
        expect(dim.normative?(:strict)).to be true
        expect(dim.normative?(:normalize)).to be true
        expect(dim.normative?(:ignore)).to be false
      end

      it "supports formatting detection on text_content" do
        expect(set[:text_content].supports_formatting_detection?).to be true
      end

      it "supports formatting detection on structural_whitespace" do
        expect(set[:structural_whitespace].supports_formatting_detection?).to be true
      end

      it "does not support formatting detection on comments" do
        expect(set[:comments].supports_formatting_detection?).to be false
      end

      it "has extended behaviors for attribute_values" do
        expect(set[:attribute_values].valid_behaviors).to eq(
          %i[strict strip compact normalize ignore],
        )
      end
    end

    context "HTML format aliases" do
      it "resolves :html to the XML set" do
        expect(described_class.for(:html).format).to eq(:xml)
      end

      it "resolves :html4 to the XML set" do
        expect(described_class.for(:html4).format).to eq(:xml)
      end

      it "resolves :html5 to the XML set" do
        expect(described_class.for(:html5).format).to eq(:xml)
      end
    end

    context "JSON format" do
      let(:set) { described_class.for(:json) }

      it "returns a DimensionSet with :json format" do
        expect(set.format).to eq(:json)
      end

      it "has 3 dimensions" do
        expect(set.names).to eq(%i[text_content structural_whitespace
                                   key_order])
      end

      it "has :strict_only normative rule for structural_whitespace" do
        expect(set[:structural_whitespace].normative?(:normalize)).to be false
      end

      it "has key_order dimension" do
        expect(set[:key_order].valid_behaviors).to eq(%i[strict ignore])
      end
    end

    context "YAML format" do
      let(:set) { described_class.for(:yaml) }

      it "returns a DimensionSet with :yaml format" do
        expect(set.format).to eq(:yaml)
      end

      it "has 4 dimensions" do
        expect(set.names).to eq(%i[text_content structural_whitespace key_order
                                   comments])
      end

      it "has :strict_only normative rule for structural_whitespace" do
        expect(set[:structural_whitespace].normative?(:normalize)).to be false
      end
    end

    it "falls back to XML set for unknown formats" do
      expect(described_class.for(:unknown).format).to eq(:xml)
    end
  end

  describe ".format_names" do
    it "returns the three format keys" do
      expect(described_class.format_names).to eq(%i[xml json yaml])
    end
  end
end
