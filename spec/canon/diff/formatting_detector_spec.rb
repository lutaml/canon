# frozen_string_literal: true

require "spec_helper"
require "canon/diff/formatting_detector"

RSpec.describe Canon::Diff::FormattingDetector do
  describe ".formatting_only?" do
    context "with formatting-only differences" do
      it "detects single space vs multiple spaces" do
        line1 = "<p>Hello  world</p>"
        line2 = "<p>Hello world</p>"

        expect(described_class.formatting_only?(line1, line2)).to be true
      end

      it "detects tabs vs spaces" do
        line1 = "<p>Hello\tworld</p>"
        line2 = "<p>Hello world</p>"

        expect(described_class.formatting_only?(line1, line2)).to be true
      end

      it "detects leading/trailing whitespace differences" do
        line1 = "  <p>Hello</p>  "
        line2 = "<p>Hello</p>"

        expect(described_class.formatting_only?(line1, line2)).to be true
      end

      it "detects mixed whitespace" do
        line1 = "<p>Hello   \t  world</p>"
        line2 = "<p>Hello world</p>"

        expect(described_class.formatting_only?(line1, line2)).to be true
      end

      it "detects newline differences" do
        line1 = "<p>Hello\nworld</p>"
        line2 = "<p>Hello world</p>"

        expect(described_class.formatting_only?(line1, line2)).to be true
      end

      it "detects complex whitespace patterns" do
        line1 = "  <div  class='test'  >  Content  </div>  "
        line2 = "<div class='test'> Content </div>"

        expect(described_class.formatting_only?(line1, line2)).to be true
      end
    end

    context "with semantic differences" do
      it "detects different text content" do
        line1 = "<p>Hello</p>"
        line2 = "<p>Goodbye</p>"

        expect(described_class.formatting_only?(line1, line2)).to be false
      end

      it "detects different attribute values" do
        line1 = "<p class='test'>Hello</p>"
        line2 = "<p class='other'>Hello</p>"

        expect(described_class.formatting_only?(line1, line2)).to be false
      end

      it "detects different element names" do
        line1 = "<p>Hello</p>"
        line2 = "<div>Hello</div>"

        expect(described_class.formatting_only?(line1, line2)).to be false
      end

      it "detects added content" do
        line1 = "<p>Hello</p>"
        line2 = "<p>Hello world</p>"

        expect(described_class.formatting_only?(line1, line2)).to be false
      end

      it "detects removed content" do
        line1 = "<p>Hello world</p>"
        line2 = "<p>Hello</p>"

        expect(described_class.formatting_only?(line1, line2)).to be false
      end
    end

    context "with edge cases" do
      it "handles nil values" do
        expect(described_class.formatting_only?(nil, nil)).to be false
        expect(described_class.formatting_only?(nil, "text")).to be false
        expect(described_class.formatting_only?("text", nil)).to be false
      end

      it "handles empty strings" do
        expect(described_class.formatting_only?("", "")).to be false
        expect(described_class.formatting_only?("", "text")).to be false
        expect(described_class.formatting_only?("text", "")).to be false
      end

      it "handles whitespace-only strings" do
        expect(described_class.formatting_only?("   ", "  ")).to be false
        expect(described_class.formatting_only?("   ", "text")).to be false
      end

      it "handles identical strings" do
        line = "<p>Hello world</p>"
        expect(described_class.formatting_only?(line, line)).to be true
      end

      it "handles strings with only whitespace differences and no content" do
        line1 = "   "
        line2 = "  "
        expect(described_class.formatting_only?(line1, line2)).to be false
      end
    end

    context "with real-world examples" do
      it "detects line-split formatting difference" do
        line1 = '<p class="section-break"><br clear="all" class="section"></p>'
        line2 = '<p class="section-break"><br clear="all" class="section"><div class="WordSection2">'

        # These are NOT formatting-only - content differs
        expect(described_class.formatting_only?(line1, line2)).to be false
      end

      it "detects indentation-only difference" do
        line1 = "    <div>Content</div>"
        line2 = "  <div>Content</div>"

        expect(described_class.formatting_only?(line1, line2)).to be true
      end

      it "detects attribute spacing difference" do
        line1 = '<div class="test"  id="main">'
        line2 = '<div class="test" id="main">'

        expect(described_class.formatting_only?(line1, line2)).to be true
      end
    end
  end

  describe ".normalize_for_comparison" do
    it "collapses multiple spaces to single space" do
      normalized = described_class.send(:normalize_for_comparison, "Hello    world")
      expect(normalized).to eq("Hello world")
    end

    it "strips leading and trailing whitespace" do
      normalized = described_class.send(:normalize_for_comparison, "  Hello world  ")
      expect(normalized).to eq("Hello world")
    end

    it "handles tabs" do
      normalized = described_class.send(:normalize_for_comparison, "Hello\t\tworld")
      expect(normalized).to eq("Hello world")
    end

    it "handles newlines" do
      normalized = described_class.send(:normalize_for_comparison, "Hello\n\nworld")
      expect(normalized).to eq("Hello world")
    end

    it "handles nil" do
      normalized = described_class.send(:normalize_for_comparison, nil)
      expect(normalized).to eq("")
    end
  end

  describe ".blank?" do
    it "returns true for nil" do
      expect(described_class.send(:blank?, nil)).to be true
    end

    it "returns true for empty string" do
      expect(described_class.send(:blank?, "")).to be true
    end

    it "returns true for whitespace-only string" do
      expect(described_class.send(:blank?, "   ")).to be true
      expect(described_class.send(:blank?, "\t\n")).to be true
    end

    it "returns false for non-blank string" do
      expect(described_class.send(:blank?, "text")).to be false
      expect(described_class.send(:blank?, " text ")).to be false
    end
  end
end