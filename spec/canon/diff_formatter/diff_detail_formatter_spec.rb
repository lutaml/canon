# frozen_string_literal: true

require "spec_helper"
require "canon/diff_formatter/diff_detail_formatter/dimension_formatter"
require "canon/diff_formatter/diff_detail_formatter/node_utils"
require "canon/diff_formatter/diff_detail_formatter/text_utils"
require "canon/diff_formatter/diff_detail_formatter/location_extractor"
require "canon/diff/diff_node"

RSpec.describe "DiffDetailFormatter helpers" do
  describe Canon::DiffFormatter::DiffDetailFormatterHelpers::NodeUtils do
    describe ".strip_ascii_whitespace" do
      it "preserves non-breaking space (NBSP) when stripping" do
        # NBSP (U+00A0) should NOT be stripped
        result = described_class.strip_ascii_whitespace("\u00a0— ")
        expect(result).to eq("\u00a0—")
      end

      it "strips leading and trailing ASCII whitespace" do
        result = described_class.strip_ascii_whitespace("  hello  ")
        expect(result).to eq("hello")
      end

      it "handles tabs and newlines" do
        result = described_class.strip_ascii_whitespace("\t\nhello\t\n")
        expect(result).to eq("hello")
      end

      it "returns original string if no ASCII whitespace" do
        result = described_class.strip_ascii_whitespace("hello")
        expect(result).to eq("hello")
      end

      it "preserves em-dash and other Unicode characters" do
        result = described_class.strip_ascii_whitespace("—")
        expect(result).to eq("—")
      end

      it "preserves mixed ASCII and Unicode whitespace" do
        # Leading NBSP, trailing regular space
        result = described_class.strip_ascii_whitespace("\u00a0hello ")
        expect(result).to eq("\u00a0hello")
      end
    end

    describe ".get_node_text" do
      it "extracts text from a simple node without stripping NBSP" do
        node = double("node")
        allow(node).to receive(:respond_to?).with(:text).and_return(true)
        allow(node).to receive(:text).and_return("\u00a0— ")
        # No .strip is called, NBSP is preserved, trailing space stripped
        result = described_class.get_node_text(node)
        expect(result).to eq("\u00a0—")
      end
    end
  end

  describe Canon::DiffFormatter::DiffDetailFormatterHelpers::TextUtils do
    describe ".visualize_whitespace" do
      it "shows NBSP as <NBSP>" do
        result = described_class.visualize_whitespace("\u00a0")
        expect(result).to eq("<NBSP>")
      end

      it "shows space as ·" do
        result = described_class.visualize_whitespace(" ")
        expect(result).to eq("·")
      end

      it "shows tab as →" do
        result = described_class.visualize_whitespace("\t")
        expect(result).to eq("→")
      end

      it "shows newline as ¬" do
        result = described_class.visualize_whitespace("\n")
        expect(result).to eq("¬")
      end

      it "shows line separator as <LSEP>" do
        result = described_class.visualize_whitespace("\u2028")
        expect(result).to eq("<LSEP>")
      end

      it "shows paragraph separator as <PSEP>" do
        result = described_class.visualize_whitespace("\u2029")
        expect(result).to eq("<PSEP>")
      end

      it "handles mixed whitespace characters" do
        result = described_class.visualize_whitespace(" \u00a0\t\n")
        expect(result).to eq("·<NBSP>→¬")
      end
    end

    describe ".escape_for_display" do
      it "escapes NBSP as \\u00A0" do
        result = described_class.escape_for_display("\u00a0")
        expect(result).to eq("\\u00A0")
      end

      it "escapes em-dash as \\u2014" do
        result = described_class.escape_for_display("—")
        expect(result).to eq("\\u2014")
      end

      it "preserves ASCII printable characters" do
        result = described_class.escape_for_display("hello world")
        expect(result).to eq("hello world")
      end

      it "escapes double quote" do
        result = described_class.escape_for_display('"')
        expect(result).to eq("\\u0022")
      end

      it "escapes backslash" do
        result = described_class.escape_for_display("\\")
        expect(result).to eq("\\u005C")
      end

      it "escapes control characters" do
        result = described_class.escape_for_display("\x00")
        expect(result).to eq("\\u0000")
      end

      it "handles mixed ASCII and Unicode" do
        result = described_class.escape_for_display("\u00a0— ")
        expect(result).to eq("\\u00A0\\u2014 ")
      end

      it "returns empty string for nil" do
        result = described_class.escape_for_display(nil)
        expect(result).to eq("")
      end
    end

    describe ".needs_escaping?" do
      it "returns true for text containing NBSP" do
        result = described_class.needs_escaping?("\u00a0")
        expect(result).to be true
      end

      it "returns true for text containing em-dash" do
        result = described_class.needs_escaping?("—")
        expect(result).to be true
      end

      it "returns false for pure ASCII text" do
        result = described_class.needs_escaping?("hello world")
        expect(result).to be false
      end

      it "returns false for nil" do
        result = described_class.needs_escaping?(nil)
        expect(result).to be false
      end

      it "returns true for text with double quote" do
        result = described_class.needs_escaping?('"')
        expect(result).to be true
      end
    end
  end

  describe Canon::DiffFormatter::DiffDetailFormatterHelpers::LocationExtractor do
    describe ".extract_location" do
      it "uses diff.path when available" do
        diff = Canon::Diff::DiffNode.new(
          node1: nil,
          node2: nil,
          dimension: :text_content,
          reason: "text content differs",
          path: "/root[0]/span[2]/text()[0]",
        )
        result = described_class.extract_location(diff)
        expect(result).to eq("Location: /root[0]/span[2]/text()[0]")
      end

      it "returns empty string when diff is nil" do
        result = described_class.extract_location(nil)
        expect(result).to eq("")
      end

      it "returns empty string when diff has no path and no nodes" do
        diff = Canon::Diff::DiffNode.new(
          node1: nil,
          node2: nil,
          dimension: :text_content,
          reason: "text content differs",
        )
        result = described_class.extract_location(diff)
        expect(result).to eq("")
      end

      it "prefers diff.path over node extraction" do
        node = double("node")
        allow(node).to receive(:respond_to?).with(:name).and_return(false)

        diff = Canon::Diff::DiffNode.new(
          node1: node,
          node2: nil,
          dimension: :text_content,
          reason: "text content differs",
          path: "/preferred/path[0]",
        )
        result = described_class.extract_location(diff)
        expect(result).to eq("Location: /preferred/path[0]")
      end
    end
  end

  describe "Issue #52 scenario: text content with NBSP difference" do
    it "preserves NBSP in text content for diff display" do
      # This test verifies the fix for:
      # https://github.com/lutaml/canon/issues/52
      #
      # When comparing text nodes that differ by NBSP (non-breaking space),
      # the diff should show the actual content, not empty strings.
      # The NBSP should be visualized (in by_line mode it shows as ␣).

      xml1 = <<~XML
        <root>
          <span class="delim">\u00a0— </span>
        </root>
      XML

      xml2 = <<~XML
        <root>
          <span class="delim"> — </span>
        </root>
      XML

      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true,
        use_color: false
      )

      # The texts are different (NBSP vs regular space + em-dash)
      expect(result.equivalent?).to be false

      diff_output = result.diff(use_color: false)

      # The diff should show the whitespace difference using character
      # visualization (␣ for NBSP). The by_line formatter visualizes
      # NBSP as '␣' which is shown in the legend as NO-Break-Space
      expect(diff_output).to include("␣") # NBSP visualization
    end
  end
end
