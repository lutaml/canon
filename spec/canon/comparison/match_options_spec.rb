# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison::MatchOptions do
  describe "constants" do
    it "defines PREPROCESSING_OPTIONS" do
      expect(described_class::PREPROCESSING_OPTIONS).to eq(
        %i[none c14n normalize format rendered],
      )
    end

    it "defines MATCH_BEHAVIORS" do
      expect(described_class::MATCH_BEHAVIORS).to eq(
        %i[strict strip compact normalize ignore],
      )
    end
  end

  describe ".match_text?" do
    context "with strict behavior" do
      it "requires exact match" do
        expect(described_class.match_text?("hello", "hello", :strict))
          .to be true
        expect(described_class.match_text?("hello", "hello ", :strict))
          .to be false
        expect(described_class.match_text?("hello", "Hello", :strict))
          .to be false
      end
    end

    context "with normalize behavior" do
      it "normalizes whitespace before comparing" do
        expect(described_class.match_text?("hello", "hello", :normalize))
          .to be true
        expect(described_class.match_text?("hello ", " hello", :normalize))
          .to be true
        expect(described_class.match_text?(
                 "hello  world", "hello world", :normalize
               )).to be true
        expect(described_class.match_text?(
                 "hello\n\nworld", "hello world", :normalize
               )).to be true
        expect(described_class.match_text?("hello", "goodbye", :normalize))
          .to be false
      end
    end

    context "with ignore behavior" do
      it "always returns true" do
        expect(described_class.match_text?("hello", "hello", :ignore))
          .to be true
        expect(described_class.match_text?("hello", "goodbye", :ignore))
          .to be true
        expect(described_class.match_text?("", "anything", :ignore))
          .to be true
      end
    end

    context "with unknown behavior" do
      it "raises error" do
        expect do
          described_class.match_text?("hello", "hello", :unknown)
        end.to raise_error(Canon::Error, /Unknown match behavior: unknown/)
      end
    end
  end

  describe ".normalize_text" do
    it "collapses whitespace sequences to single space" do
      expect(described_class.normalize_text("hello  world"))
        .to eq("hello world")
      expect(described_class.normalize_text("hello\t\tworld"))
        .to eq("hello world")
      expect(described_class.normalize_text("hello\n\nworld"))
        .to eq("hello world")
    end

    it "trims leading and trailing whitespace" do
      expect(described_class.normalize_text("  hello  ")).to eq("hello")
      expect(described_class.normalize_text("\nhello\n")).to eq("hello")
    end

    it "handles empty strings" do
      expect(described_class.normalize_text("")).to eq("")
      expect(described_class.normalize_text("   ")).to eq("")
    end

    it "handles nil" do
      expect(described_class.normalize_text(nil)).to eq("")
    end
  end
end

RSpec.describe Canon::Comparison::MatchOptions::Xml do
  describe "constants" do
    it "defines MATCH_DIMENSIONS" do
      expect(described_class::MATCH_DIMENSIONS).to eq(%i[
                                                        text_content
                                                        structural_whitespace
                                                        attribute_presence
                                                        attribute_order
                                                        attribute_values
                                                        element_position
                                                        comments
                                                      ])
    end

    it "defines MATCH_PROFILES" do
      expect(described_class::MATCH_PROFILES.keys).to eq(%i[
                                                           strict rendered html4 html5 spec_friendly content_only
                                                         ])
    end

    it "defines FORMAT_DEFAULTS" do
      expect(described_class::FORMAT_DEFAULTS.keys).to eq(
        %i[html xml],
      )
    end
  end

  describe "format-specific defaults" do
    it "defines HTML defaults (mimics CSS rendering)" do
      expect(described_class::FORMAT_DEFAULTS[:html]).to eq(
        preprocessing: :rendered,
        text_content: :normalize,
        structural_whitespace: :normalize,
        attribute_presence: :strict,
        attribute_order: :ignore,
        attribute_values: :strict,
        element_position: :ignore,
        comments: :ignore,
      )
    end

    it "defines XML defaults (strict matching)" do
      expect(described_class::FORMAT_DEFAULTS[:xml]).to eq(
        preprocessing: :none,
        text_content: :strict,
        structural_whitespace: :strict,
        attribute_presence: :strict,
        attribute_order: :ignore,
        attribute_values: :strict,
        element_position: :strict,
        comments: :strict,
      )
    end
  end

  describe "match profiles" do
    it "defines strict profile" do
      expect(described_class::MATCH_PROFILES[:strict]).to eq(
        preprocessing: :none,
        text_content: :strict,
        structural_whitespace: :strict,
        attribute_presence: :strict,
        attribute_order: :strict,
        attribute_values: :strict,
        element_position: :strict,
        comments: :strict,
      )
    end

    it "defines rendered profile" do
      expect(described_class::MATCH_PROFILES[:rendered]).to eq(
        preprocessing: :none,
        text_content: :normalize,
        structural_whitespace: :normalize,
        attribute_presence: :strict,
        attribute_order: :strict,
        attribute_values: :strict,
        element_position: :strict,
        comments: :ignore,
      )
    end

    it "defines spec_friendly profile" do
      expect(described_class::MATCH_PROFILES[:spec_friendly]).to eq(
        preprocessing: :rendered,
        text_content: :normalize,
        structural_whitespace: :ignore,
        attribute_presence: :strict,
        attribute_order: :ignore,
        attribute_values: :normalize,
        element_position: :ignore,
        comments: :ignore,
      )
    end

    it "defines content_only profile" do
      expect(described_class::MATCH_PROFILES[:content_only]).to eq(
        preprocessing: :c14n,
        text_content: :normalize,
        structural_whitespace: :ignore,
        attribute_presence: :strict,
        attribute_order: :ignore,
        attribute_values: :normalize,
        element_position: :ignore,
        comments: :ignore,
      )
    end
  end

  describe ".resolve" do
    context "with format defaults" do
      it "returns HTML defaults when no other options specified" do
        result = described_class.resolve(format: :html)
        expect(result).to eq(
          format: :html,
          preprocessing: :rendered,
          text_content: :normalize,
          structural_whitespace: :normalize,
          attribute_presence: :strict,
          attribute_order: :ignore,
          attribute_values: :strict,
          element_position: :ignore,
          comments: :ignore,
        )
      end

      it "returns XML defaults when no other options specified" do
        result = described_class.resolve(format: :xml)
        expect(result).to eq(
          format: :xml,
          preprocessing: :none,
          text_content: :strict,
          structural_whitespace: :strict,
          attribute_presence: :strict,
          attribute_order: :ignore,
          attribute_values: :strict,
          element_position: :strict,
          comments: :strict,
        )
      end

      it "falls back to XML defaults for unknown format" do
        result = described_class.resolve(format: :unknown)
        expect(result).to eq(
          format: :unknown,
          preprocessing: :none,
          text_content: :strict,
          structural_whitespace: :strict,
          attribute_presence: :strict,
          attribute_order: :ignore,
          attribute_values: :strict,
          element_position: :strict,
          comments: :strict,
        )
      end
    end

    context "with global profile" do
      it "applies global profile over format defaults" do
        result = described_class.resolve(
          format: :html,
          global_profile: :spec_friendly,
        )

        expect(result).to eq(
          format: :html,
          preprocessing: :rendered,
          text_content: :normalize,
          structural_whitespace: :ignore,
          attribute_presence: :strict,
          attribute_order: :ignore,
          attribute_values: :normalize,
          element_position: :ignore,
          comments: :ignore,
        )
      end
    end

    context "with global options" do
      it "applies global options over format defaults" do
        result = described_class.resolve(
          format: :xml,
          global_options: { text_content: :normalize },
        )
        expect(result[:text_content]).to eq(:normalize)
        expect(result[:structural_whitespace]).to eq(:strict)
      end
    end

    context "with per-call profile" do
      it "applies per-call profile over global profile" do
        result = described_class.resolve(
          format: :xml,
          global_profile: :strict,
          match_profile: :rendered,
        )
        expect(result).to eq(
          format: :xml,
          preprocessing: :none,
          text_content: :normalize,
          structural_whitespace: :normalize,
          attribute_presence: :strict,
          attribute_order: :strict,
          attribute_values: :strict,
          element_position: :strict,
          comments: :ignore,
        )
      end

      it "raises error for unknown profile" do
        expect do
          described_class.resolve(
            format: :xml,
            match_profile: :unknown,
          )
        end.to raise_error(Canon::Error, /Unknown match profile: unknown/)
      end
    end

    context "with per-call preprocessing" do
      it "applies preprocessing over profile" do
        result = described_class.resolve(
          format: :xml,
          match_profile: :strict,
          preprocessing: :c14n,
        )
        expect(result[:preprocessing]).to eq(:c14n)
        expect(result[:text_content]).to eq(:strict)
      end

      it "raises error for unknown preprocessing option" do
        expect do
          described_class.resolve(
            format: :xml,
            preprocessing: :unknown,
          )
        end.to raise_error(Canon::Error, /Unknown preprocessing option/)
      end
    end

    context "with per-call match options" do
      it "applies explicit options over profile" do
        result = described_class.resolve(
          format: :xml,
          match_profile: :rendered,
          match: { text_content: :strict },
        )
        expect(result[:text_content]).to eq(:strict)
        expect(result[:structural_whitespace]).to eq(:normalize)
      end

      it "raises error for unknown dimension" do
        expect do
          described_class.resolve(
            format: :xml,
            match: { unknown_dimension: :normalize },
          )
        end.to raise_error(Canon::Error, /Unknown match dimension/)
      end

      it "raises error for unknown behavior" do
        expect do
          described_class.resolve(
            format: :xml,
            match: { text_content: :unknown_behavior },
          )
        end.to raise_error(Canon::Error, /Unknown match behavior/)
      end
    end

    context "precedence order" do
      it "applies options in correct precedence order" do
        result = described_class.resolve(
          format: :html,                          # Base: rendered-like
          global_profile: :strict,                # Override to strict
          global_options: { comments: :ignore },  # Override comments
          match_profile: :spec_friendly,          # Override to spec_friendly
          preprocessing: :c14n,                   # Override preprocessing
          match: { text_content: :strict },       # Override text_content
        )

        # Highest priority: match
        expect(result[:text_content]).to eq(:strict)

        # Second priority: preprocessing parameter
        expect(result[:preprocessing]).to eq(:c14n)

        # Third priority: match_profile
        expect(result[:structural_whitespace]).to eq(:ignore)
        expect(result[:attribute_values]).to eq(:normalize)

        # Fourth priority: global_options (but overridden by match_profile)
        expect(result[:comments]).to eq(:ignore)
      end
    end
  end

  describe ".get_profile_options" do
    it "returns profile options" do
      result = described_class.get_profile_options(:rendered)
      expect(result).to eq(
        preprocessing: :none,
        text_content: :normalize,
        structural_whitespace: :normalize,
        attribute_presence: :strict,
        attribute_order: :strict,
        attribute_values: :strict,
        element_position: :strict,
        comments: :ignore,
      )
    end

    it "returns a copy of the profile" do
      result1 = described_class.get_profile_options(:strict)
      result2 = described_class.get_profile_options(:strict)
      expect(result1).to eq(result2)
      expect(result1).not_to be(result2)
    end

    it "raises error for unknown profile" do
      expect do
        described_class.get_profile_options(:unknown)
      end.to raise_error(Canon::Error, /Unknown match profile/)
    end
  end
end

RSpec.describe Canon::Comparison::MatchOptions::Json do
  describe "constants" do
    it "defines MATCH_DIMENSIONS" do
      expect(described_class::MATCH_DIMENSIONS).to eq(%i[
                                                        text_content
                                                        structural_whitespace
                                                        key_order
                                                      ])
    end

    it "defines FORMAT_DEFAULTS" do
      expect(described_class::FORMAT_DEFAULTS.keys).to eq([:json])
    end
  end

  describe ".resolve" do
    it "returns JSON defaults when no other options specified" do
      result = described_class.resolve(format: :json)
      expect(result).to eq(
        format: :json,
        preprocessing: :none,
        text_content: :strict,
        structural_whitespace: :ignore,
        key_order: :ignore,
      )
    end
  end
end

RSpec.describe Canon::Comparison::MatchOptions::Yaml do
  describe "constants" do
    it "defines MATCH_DIMENSIONS" do
      expect(described_class::MATCH_DIMENSIONS).to eq(%i[
                                                        text_content
                                                        structural_whitespace
                                                        key_order
                                                        comments
                                                      ])
    end

    it "defines FORMAT_DEFAULTS" do
      expect(described_class::FORMAT_DEFAULTS.keys).to eq([:yaml])
    end
  end

  describe ".resolve" do
    it "returns YAML defaults when no other options specified" do
      result = described_class.resolve(format: :yaml)
      expect(result).to eq(
        format: :yaml,
        preprocessing: :none,
        text_content: :strict,
        structural_whitespace: :ignore,
        key_order: :ignore,
        comments: :ignore,
      )
    end
  end
end
