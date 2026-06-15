# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison::Dimensions::DimensionSet do
  let(:text_dim) do
    Canon::Comparison::Dimensions::Dimension.new(
      name: :text_content,
      valid_behaviors: %i[strict normalize ignore],
      formatting_detection: true,
    )
  end

  let(:comments_dim) do
    Canon::Comparison::Dimensions::Dimension.new(
      name: :comments,
      valid_behaviors: %i[strict ignore],
    )
  end

  let(:set) do
    described_class.new(:test_format, [text_dim, comments_dim])
  end

  describe "constructor" do
    it "sets format" do
      expect(set.format).to eq(:test_format)
    end

    it "is frozen" do
      expect(set).to be_frozen
    end
  end

  describe "#[]" do
    it "returns dimension by name" do
      expect(set[:text_content]).to eq(text_dim)
      expect(set[:comments]).to eq(comments_dim)
    end

    it "returns nil for unknown dimension" do
      expect(set[:unknown]).to be_nil
    end
  end

  describe "#names" do
    it "returns dimension names in definition order" do
      expect(set.names).to eq(%i[text_content comments])
    end
  end

  describe "#dimension?" do
    it "returns true for known dimensions" do
      expect(set.dimension?(:text_content)).to be true
      expect(set.dimension?(:comments)).to be true
    end

    it "returns false for unknown dimensions" do
      expect(set.dimension?(:unknown)).to be false
    end
  end
end
