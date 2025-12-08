# frozen_string_literal: true

require "spec_helper"
require "canon/comparison/html_compare_profile"

RSpec.describe Canon::Comparison::HtmlCompareProfile do
  describe "#initialize" do
    it "creates profile with default HTML5 version" do
      profile = described_class.new({})
      expect(profile.html_version).to eq(:html5)
    end

    it "accepts HTML4 version" do
      profile = described_class.new({}, html_version: :html4)
      expect(profile.html_version).to eq(:html4)
    end

    it "accepts HTML5 version explicitly" do
      profile = described_class.new({}, html_version: :html5)
      expect(profile.html_version).to eq(:html5)
    end
  end

  describe "#affects_equivalence?" do
    context "for comments dimension" do
      it "returns false by default (HTML comments are presentational)" do
        profile = described_class.new({})
        expect(profile.affects_equivalence?(:comments)).to be false
      end

      it "returns false when comments is :normalize" do
        profile = described_class.new({ comments: :normalize })
        expect(profile.affects_equivalence?(:comments)).to be false
      end

      it "returns false when comments is :ignore" do
        profile = described_class.new({ comments: :ignore })
        expect(profile.affects_equivalence?(:comments)).to be false
      end

      it "returns true when explicitly set to :strict" do
        profile = described_class.new({ comments: :strict })
        expect(profile.affects_equivalence?(:comments)).to be true
      end
    end

    context "for other dimensions" do
      it "returns true for text_content with default :strict" do
        profile = described_class.new({})
        expect(profile.affects_equivalence?(:text_content)).to be true
      end

      it "returns false for text_content with :ignore" do
        profile = described_class.new({ text_content: :ignore })
        expect(profile.affects_equivalence?(:text_content)).to be false
      end

      it "returns true for element_structure by default" do
        profile = described_class.new({})
        expect(profile.affects_equivalence?(:element_structure)).to be true
      end

      it "returns true for attributes by default" do
        profile = described_class.new({})
        expect(profile.affects_equivalence?(:attributes)).to be true
      end
    end
  end

  describe "#preserve_whitespace?" do
    let(:profile) { described_class.new({}) }

    context "for whitespace-sensitive elements" do
      it "returns true for pre elements" do
        expect(profile.preserve_whitespace?("pre")).to be true
      end

      it "returns true for code elements" do
        expect(profile.preserve_whitespace?("code")).to be true
      end

      it "returns true for textarea elements" do
        expect(profile.preserve_whitespace?("textarea")).to be true
      end

      it "returns true for script elements" do
        expect(profile.preserve_whitespace?("script")).to be true
      end

      it "returns true for style elements" do
        expect(profile.preserve_whitespace?("style")).to be true
      end

      it "is case-insensitive for element names" do
        expect(profile.preserve_whitespace?("PRE")).to be true
        expect(profile.preserve_whitespace?("Code")).to be true
        expect(profile.preserve_whitespace?("TEXTAREA")).to be true
      end
    end

    context "for regular elements" do
      it "returns false for div elements" do
        expect(profile.preserve_whitespace?("div")).to be false
      end

      it "returns false for p elements" do
        expect(profile.preserve_whitespace?("p")).to be false
      end

      it "returns false for span elements" do
        expect(profile.preserve_whitespace?("span")).to be false
      end

      it "returns false for arbitrary elements" do
        expect(profile.preserve_whitespace?("article")).to be false
        expect(profile.preserve_whitespace?("section")).to be false
      end
    end
  end

  describe "#case_sensitive?" do
    context "for HTML5" do
      it "returns true (HTML5 is case-sensitive)" do
        profile = described_class.new({}, html_version: :html5)
        expect(profile.case_sensitive?).to be true
      end
    end

    context "for HTML4" do
      it "returns false (HTML4 is case-insensitive)" do
        profile = described_class.new({}, html_version: :html4)
        expect(profile.case_sensitive?).to be false
      end
    end

    context "with default version" do
      it "defaults to HTML5 (case-sensitive)" do
        profile = described_class.new({})
        expect(profile.case_sensitive?).to be true
      end
    end
  end

  describe "#normative_dimension?" do
    it "returns true for element_structure (always normative)" do
      profile = described_class.new({})
      expect(profile.normative_dimension?(:element_structure)).to be true
    end

    it "returns false for comments (not normative in HTML)" do
      profile = described_class.new({})
      expect(profile.normative_dimension?(:comments)).to be false
    end

    it "returns true for comments when explicitly :strict" do
      profile = described_class.new({ comments: :strict })
      expect(profile.normative_dimension?(:comments)).to be true
    end

    it "returns true for text_content by default" do
      profile = described_class.new({})
      expect(profile.normative_dimension?(:text_content)).to be true
    end
  end

  describe "#supports_formatting_detection?" do
    let(:profile) { described_class.new({}) }

    it "returns true for text_content" do
      expect(profile.supports_formatting_detection?(:text_content)).to be true
    end

    it "returns true for structural_whitespace" do
      expect(profile.supports_formatting_detection?(:structural_whitespace)).to be true
    end

    it "returns false for comments" do
      expect(profile.supports_formatting_detection?(:comments)).to be false
    end

    it "returns false for element_structure" do
      expect(profile.supports_formatting_detection?(:element_structure)).to be false
    end

    it "returns false for attributes" do
      expect(profile.supports_formatting_detection?(:attributes)).to be false
    end
  end

  describe "integration with match options" do
    context "with complex match options" do
      let(:match_options) do
        {
          comments: :ignore,
          text_content: :normalize,
          attributes: :strict,
          structural_whitespace: :ignore,
        }
      end

      let(:profile) { described_class.new(match_options, html_version: :html5) }

      it "properly handles multiple dimension behaviors" do
        expect(profile.affects_equivalence?(:comments)).to be false
        expect(profile.affects_equivalence?(:text_content)).to be true
        expect(profile.affects_equivalence?(:attributes)).to be true
        expect(profile.affects_equivalence?(:structural_whitespace)).to be false
      end

      it "maintains HTML-specific behavior" do
        expect(profile.preserve_whitespace?("pre")).to be true
        expect(profile.case_sensitive?).to be true
      end
    end
  end
end