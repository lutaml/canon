# frozen_string_literal: true

require "spec_helper"
require "canon/diff_formatter/legend"

RSpec.describe Canon::DiffFormatter::Legend do
  let(:visualization_map) { Canon::DiffFormatter::DEFAULT_VISUALIZATION_MAP }

  describe ".detect_non_ascii" do
    it "returns empty hash for ASCII-only text" do
      text = "Hello, world! 123"
      result = described_class.detect_non_ascii(text, visualization_map)
      expect(result).to be_empty
    end

    it "detects non-breaking space (U+00A0)" do
      text = "Hello\u00A0world"
      result = described_class.detect_non_ascii(text, visualization_map)

      expect(result).to have_key("\u00A0")
      expect(result["\u00A0"][:codepoint]).to eq("U+00A0")
      expect(result["\u00A0"][:visualization]).to eq("␣")
      expect(result["\u00A0"][:category]).to eq(:whitespace)
    end

    it "detects Four-Per-Em Space (U+2005)" do
      text = "Hello\u2005world"
      result = described_class.detect_non_ascii(text, visualization_map)

      expect(result).to have_key("\u2005")
      expect(result["\u2005"][:codepoint]).to eq("U+2005")
      expect(result["\u2005"][:visualization]).to eq("⏓")
      expect(result["\u2005"][:name]).to eq("Four-Per-Em Space")
    end

    it "detects zero-width space (U+200B)" do
      text = "Hello\u200Bworld"
      result = described_class.detect_non_ascii(text, visualization_map)

      expect(result).to have_key("\u200B")
      expect(result["\u200B"][:codepoint]).to eq("U+200B")
      expect(result["\u200B"][:visualization]).to eq("→")
      expect(result["\u200B"][:category]).to eq(:zero_width)
    end

    it "detects LTR mark (U+200E)" do
      text = "Hello\u200Eworld"
      result = described_class.detect_non_ascii(text, visualization_map)

      expect(result).to have_key("\u200E")
      expect(result["\u200E"][:codepoint]).to eq("U+200E")
      expect(result["\u200E"][:category]).to eq(:directional)
    end

    it "detects multiple different non-ASCII characters" do
      text = "Hello\u00A0world\u2005test\u200B"
      result = described_class.detect_non_ascii(text, visualization_map)

      expect(result.keys).to contain_exactly("\u00A0", "\u2005", "\u200B")
    end

    it "returns each character only once even if repeated" do
      text = "Hello\u00A0world\u00A0test\u00A0"
      result = described_class.detect_non_ascii(text, visualization_map)

      expect(result.keys).to eq(["\u00A0"])
    end

    it "handles characters not in visualization map" do
      text = "Hello\u3042world" # Hiragana 'a'
      result = described_class.detect_non_ascii(text, visualization_map)

      # Characters without custom visualization are skipped
      expect(result).to be_empty
    end

    it "handles mixed ASCII and non-ASCII text" do
      text = "Normal text\u00A0with\u2005various\u200Bspaces"
      result = described_class.detect_non_ascii(text, visualization_map)

      expect(result.keys.length).to eq(3)
      expect(result.keys).to contain_exactly("\u00A0", "\u2005", "\u200B")
    end
  end

  describe ".build_legend" do
    context "with color enabled" do
      let(:use_color) { true }

      it "builds legend for single whitespace character" do
        detected = {
          "\u00A0" => {
            codepoint: "U+00A0",
            visualization: "␣",
            category: :whitespace,
            name: "No-Break Space",
          },
        }

        legend = described_class.build_legend(detected, use_color: use_color)

        expect(legend).to include("Character Visualization Legend")
        expect(legend).to include("Whitespace:")
        expect(legend).to include("'␣': U+00A0")
        expect(legend).to include("NO-Break-Space")
      end

      it "builds legend for multiple categories" do
        detected = {
          "\u00A0" => {
            codepoint: "U+00A0",
            visualization: "␣",
            category: :whitespace,
            name: "No-Break Space",
          },
          "\u200B" => {
            codepoint: "U+200B",
            visualization: "→",
            category: :zero_width,
            name: "Zero Width Space",
          },
        }

        legend = described_class.build_legend(detected, use_color: use_color)

        expect(legend).to include("Whitespace:")
        expect(legend).to include("Zero-Width Characters:")
        expect(legend).to include("'␣': U+00A0")
        expect(legend).to include("'→': U+200B")
      end

      it "groups characters by category" do
        detected = {
          "\u00A0" => {
            codepoint: "U+00A0",
            visualization: "␣",
            category: :whitespace,
            name: "No-Break Space",
          },
          "\u2005" => {
            codepoint: "U+2005",
            visualization: "⏓",
            category: :whitespace,
            name: "Four-Per-Em Space",
          },
          "\u200B" => {
            codepoint: "U+200B",
            visualization: "→",
            category: :zero_width,
            name: "Zero Width Space",
          },
        }

        legend = described_class.build_legend(detected, use_color: use_color)

        # Should have whitespace section with both characters
        lines = legend.split("\n")
        whitespace_idx = lines.index { |l| l.include?("Whitespace:") }
        expect(whitespace_idx).not_to be_nil

        # Next two lines should be the whitespace characters
        expect(lines[whitespace_idx + 1]).to include("'␣': U+00A0")
        expect(lines[whitespace_idx + 2]).to include("'⏓': U+2005")
      end

      it "shows original character when different from visualization" do
        detected = {
          "\u00A0" => {
            codepoint: "U+00A0",
            visualization: "␣",
            category: :whitespace,
            name: "No-Break Space",
          },
        }

        legend = described_class.build_legend(detected, use_color: use_color)

        # Should show: '␣': U+00A0 ( ) NO-Break-Space
        # where the middle character is the original non-breaking space
        expect(legend).to match(/'␣': U\+00A0 \(.\) NO-Break-Space/)
      end

    end

    context "without color" do
      let(:use_color) { false }

      it "builds plain text legend without ANSI codes" do
        detected = {
          "\u00A0" => {
            codepoint: "U+00A0",
            visualization: "␣",
            category: :whitespace,
            name: "No-Break Space",
          },
        }

        legend = described_class.build_legend(detected, use_color: use_color)

        expect(legend).to include("Character Visualization Legend")
        expect(legend).to include("Whitespace:")
        expect(legend).to include("'␣': U+00A0")
        expect(legend).not_to include("\e[") # No ANSI escape codes
      end
    end

    context "with empty detected characters" do
      it "returns nil" do
        legend = described_class.build_legend({}, use_color: true)
        expect(legend).to be_nil
      end
    end

    context "with all character categories" do
      it "displays all categories in order" do
        detected = {
          "\u00A0" => { codepoint: "U+00A0", visualization: "␣",
                        category: :whitespace, name: "No-Break Space" },
          "\n" => { codepoint: "U+000A", visualization: "↵",
                    category: :line_endings, name: "Line Feed" },
          "\u200B" => { codepoint: "U+200B", visualization: "→",
                        category: :zero_width, name: "Zero Width Space" },
          "\u200E" => { codepoint: "U+200E", visualization: "⟹",
                        category: :directional, name: "Left-To-Right Mark" },
          "\u0000" => { codepoint: "U+0000", visualization: "␀",
                        category: :control, name: "Null" },
        }

        legend = described_class.build_legend(detected, use_color: true)
        lines = legend.split("\n").map(&:strip).reject(&:empty?)

        # Check order of categories
        whitespace_idx = lines.index { |l| l.include?("Whitespace") }
        line_ending_idx = lines.index { |l| l.include?("Line Endings") }
        zero_width_idx = lines.index { |l| l.include?("Zero-Width") }
        directional_idx = lines.index { |l| l.include?("Directional") }
        control_idx = lines.index { |l| l.include?("Control") }

        expect(whitespace_idx).to be < line_ending_idx
        expect(line_ending_idx).to be < zero_width_idx
        expect(zero_width_idx).to be < directional_idx
        expect(directional_idx).to be < control_idx
      end
    end
  end

  describe "integration with formatters" do
    it "detects and formats characters used in actual diffs" do
      # Simulate text with various special characters
      text = "Hello\u00A0world\u2005test\u200Bend"

      detected = described_class.detect_non_ascii(text, visualization_map)
      legend = described_class.build_legend(detected, use_color: false)

      expect(legend).to include("Character Visualization Legend")
      expect(legend).to include("'␣': U+00A0")
      expect(legend).to include("'⏓': U+2005")
      expect(legend).to include("'→': U+200B")
    end

    it "handles edge case of only ASCII characters" do
      text = "Just normal ASCII text here"

      detected = described_class.detect_non_ascii(text, visualization_map)
      legend = described_class.build_legend(detected, use_color: false)

      expect(detected).to be_empty
      expect(legend).to be_nil
    end
  end
end
