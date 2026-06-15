# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison::Dimensions::Dimension do
  describe "constructor" do
    it "sets name and valid_behaviors" do
      dim = described_class.new(name: :text_content,
                                valid_behaviors: %i[strict normalize ignore])
      expect(dim.name).to eq(:text_content)
      expect(dim.valid_behaviors).to eq(%i[strict normalize ignore])
    end

    it "defaults normative_rule to :behavior_not_ignore" do
      dim = described_class.new(name: :comments,
                                valid_behaviors: %i[
                                  strict ignore
                                ])
      expect(dim.normative?(:strict)).to be true
      expect(dim.normative?(:ignore)).to be false
    end

    it "defaults formatting_detection to false" do
      dim = described_class.new(name: :comments,
                                valid_behaviors: %i[
                                  strict ignore
                                ])
      expect(dim.supports_formatting_detection?).to be false
    end

    it "is frozen" do
      dim = described_class.new(name: :test, valid_behaviors: %i[strict])
      expect(dim).to be_frozen
    end
  end

  describe "#normative?" do
    context "with :behavior_not_ignore rule (default)" do
      let(:dimension) do
        described_class.new(name: :text_content,
                            valid_behaviors: %i[strict normalize ignore])
      end

      it "returns true for :strict" do
        expect(dimension.normative?(:strict)).to be true
      end

      it "returns true for :normalize" do
        expect(dimension.normative?(:normalize)).to be true
      end

      it "returns false for :ignore" do
        expect(dimension.normative?(:ignore)).to be false
      end
    end

    context "with :strict_only rule" do
      let(:dimension) do
        described_class.new(name: :structural_whitespace,
                            valid_behaviors: %i[strict normalize ignore],
                            normative_rule: :strict_only)
      end

      it "returns true for :strict" do
        expect(dimension.normative?(:strict)).to be true
      end

      it "returns false for :normalize" do
        expect(dimension.normative?(:normalize)).to be false
      end

      it "returns false for :ignore" do
        expect(dimension.normative?(:ignore)).to be false
      end
    end
  end

  describe "#valid_behavior?" do
    let(:dimension) do
      described_class.new(name: :attribute_values,
                          valid_behaviors: %i[strict strip compact normalize
                                              ignore])
    end

    it "returns true for valid behaviors" do
      expect(dimension.valid_behavior?(:strict)).to be true
      expect(dimension.valid_behavior?(:normalize)).to be true
      expect(dimension.valid_behavior?(:strip)).to be true
    end

    it "returns false for invalid behaviors" do
      expect(dimension.valid_behavior?(:unknown)).to be false
    end
  end

  describe "#supports_formatting_detection?" do
    it "returns true when formatting_detection is set" do
      dim = described_class.new(name: :text_content,
                                valid_behaviors: %i[strict normalize ignore],
                                formatting_detection: true)
      expect(dim.supports_formatting_detection?).to be true
    end

    it "returns false by default" do
      dim = described_class.new(name: :comments,
                                valid_behaviors: %i[
                                  strict ignore
                                ])
      expect(dim.supports_formatting_detection?).to be false
    end
  end
end
