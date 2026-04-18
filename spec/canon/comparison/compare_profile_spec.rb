# frozen_string_literal: true

require "spec_helper"
require "canon/comparison/compare_profile"
require "canon/comparison/match_options"

RSpec.describe Canon::Comparison::CompareProfile do
  describe "#track_dimension?" do
    it "always returns true for all dimensions" do
      match_opts = { text_content: :strict }
      profile = described_class.new(match_opts)

      expect(profile.track_dimension?(:text_content)).to be true
      expect(profile.track_dimension?(:comments)).to be true
      expect(profile.track_dimension?(:structural_whitespace)).to be true
    end
  end

  describe "#affects_equivalence?" do
    context "when dimension behavior is :strict" do
      it "returns true" do
        match_opts = { text_content: :strict }
        profile = described_class.new(match_opts)

        expect(profile.affects_equivalence?(:text_content)).to be true
      end
    end

    context "when dimension behavior is :normalize" do
      it "returns true" do
        match_opts = { text_content: :normalize }
        profile = described_class.new(match_opts)

        expect(profile.affects_equivalence?(:text_content)).to be true
      end
    end

    context "when dimension behavior is :ignore" do
      it "returns false" do
        match_opts = { comments: :ignore }
        profile = described_class.new(match_opts)

        expect(profile.affects_equivalence?(:comments)).to be false
      end
    end
  end

  describe "#normative_dimension?" do
    context "when dimension affects equivalence (behavior is not :ignore)" do
      it "returns true for text_content with :strict" do
        profile = described_class.new({ text_content: :strict })
        expect(profile.normative_dimension?(:text_content)).to be true
      end

      it "returns true for element_structure with :strict" do
        profile = described_class.new({ element_structure: :strict })
        expect(profile.normative_dimension?(:element_structure)).to be true
      end

      it "returns true for element_structure by default" do
        profile = described_class.new({})
        expect(profile.normative_dimension?(:element_structure)).to be true
      end
    end

    context "when dimension does not affect equivalence (behavior is :ignore)" do
      it "returns false for comments with :ignore" do
        profile = described_class.new({ comments: :ignore })
        expect(profile.normative_dimension?(:comments)).to be false
      end

      it "returns false for element_structure with :ignore" do
        profile = described_class.new({ element_structure: :ignore })
        expect(profile.normative_dimension?(:element_structure)).to be false
      end
    end

    context "for structural_whitespace (special rule)" do
      it "returns true only for :strict" do
        profile = described_class.new({ structural_whitespace: :strict })
        expect(profile.normative_dimension?(:structural_whitespace)).to be true
      end

      it "returns false for :normalize" do
        profile = described_class.new({ structural_whitespace: :normalize })
        expect(profile.normative_dimension?(:structural_whitespace)).to be false
      end

      it "returns false for :ignore" do
        profile = described_class.new({ structural_whitespace: :ignore })
        expect(profile.normative_dimension?(:structural_whitespace)).to be false
      end
    end
  end

  describe "#supports_formatting_detection?" do
    context "for text content dimensions" do
      it "returns true for :text_content" do
        profile = described_class.new({})

        expect(profile.supports_formatting_detection?(:text_content)).to be true
      end

      it "returns true for :structural_whitespace" do
        profile = described_class.new({})

        expect(profile.supports_formatting_detection?(:structural_whitespace)).to be true
      end

      it "returns false for :comments" do
        profile = described_class.new({})

        expect(profile.supports_formatting_detection?(:comments)).to be false
      end
    end

    context "for structural/attribute dimensions" do
      it "returns false for :element_structure" do
        profile = described_class.new({})

        expect(profile.supports_formatting_detection?(:element_structure)).to be false
      end

      it "returns false for :attribute_values" do
        profile = described_class.new({})

        expect(profile.supports_formatting_detection?(:attribute_values)).to be false
      end

      it "returns false for :namespace_declarations" do
        profile = described_class.new({})

        expect(profile.supports_formatting_detection?(:namespace_declarations)).to be false
      end
    end
  end

  describe "integration with ResolvedMatchOptions" do
    it "works with ResolvedMatchOptions object" do
      match_opts_hash = { comments: :ignore, text_content: :strict }
      resolved_opts = Canon::Comparison::ResolvedMatchOptions.new(
        match_opts_hash,
        format: :xml,
      )
      profile = described_class.new(resolved_opts)

      expect(profile.affects_equivalence?(:comments)).to be false
      expect(profile.affects_equivalence?(:text_content)).to be true
      expect(profile.normative_dimension?(:comments)).to be false
      expect(profile.normative_dimension?(:text_content)).to be true
    end

    it "defaults element_structure to normative when not in resolved options" do
      # element_structure is a derived dimension, not in match_dimensions,
      # so ResolvedMatchOptions returns nil for it — should still default to normative
      resolved_opts = Canon::Comparison::ResolvedMatchOptions.new(
        { comments: :ignore },
        format: :xml,
      )
      profile = described_class.new(resolved_opts)

      expect(profile.normative_dimension?(:element_structure)).to be true
    end
  end
end
