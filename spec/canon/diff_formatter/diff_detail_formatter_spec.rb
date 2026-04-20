# frozen_string_literal: true

require "spec_helper"
require "canon/diff_formatter/diff_detail_formatter/dimension_formatter"
require "canon/diff_formatter/diff_detail_formatter/node_utils"
require "canon/diff_formatter/diff_detail_formatter/text_utils"
require "canon/diff_formatter/diff_detail_formatter/location_extractor"
require "canon/diff/diff_node"
require "canon/xml/nodes/element_node"
require "canon/xml/nodes/text_node"
require "canon/xml/nodes/attribute_node"
require "canon/xml/nodes/comment_node"

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

  # ── compact XML rendering (compact_semantic_report) ────────────────────────

  describe Canon::DiffFormatter::DiffDetailFormatterHelpers::NodeUtils,
           "compact rendering" do
    let(:nu) { described_class }

    # helpers for building Canon nodes
    def text_node(str)
      Canon::Xml::Nodes::TextNode.new(value: str)
    end

    def element_node(name, children: [], attributes: [])
      n = Canon::Xml::Nodes::ElementNode.new(name: name)
      attributes.each { |a| n.add_attribute(a) }
      children.each { |c| n.add_child(c) }
      n
    end

    def attr_node(name, value)
      Canon::Xml::Nodes::AttributeNode.new(name: name, value: value)
    end

    describe ".serialize_node_compact" do
      context "with a TextNode" do
        it "returns the escaped text value" do
          expect(nu.serialize_node_compact(text_node("Cereals"))).to eq("Cereals")
        end

        it "escapes HTML entities in text content" do
          expect(nu.serialize_node_compact(text_node("<>&"))).to eq("&lt;&gt;&amp;")
        end
      end

      context "with an ElementNode with no children" do
        it "produces a self-closing tag" do
          expect(nu.serialize_node_compact(element_node("br"))).to eq("<br/>")
        end

        it "includes attributes" do
          node = element_node("bibitem",
                              attributes: [attr_node("id", "ISO712"),
                                           attr_node("type", "standard")])
          expect(nu.serialize_node_compact(node)).to \
            eq('<bibitem id="ISO712" type="standard"/>')
        end
      end

      context "with an ElementNode with text children" do
        it "wraps text content between open and close tags" do
          node = element_node("em",
                              children: [text_node("Cereals and cereal products")])
          expect(nu.serialize_node_compact(node)).to eq("<em>Cereals and cereal products</em>")
        end

        it "escapes HTML entities in attribute values" do
          node = element_node("a",
                              attributes: [attr_node("href", "x&y")],
                              children: [text_node("link")])
          expect(nu.serialize_node_compact(node)).to eq('<a href="x&amp;y">link</a>')
        end
      end

      context "with nested ElementNodes" do
        it "serializes nested structure inline" do
          inner = element_node("strong", children: [text_node("bold")])
          outer = element_node("p", children: [inner])
          expect(nu.serialize_node_compact(outer)).to eq("<p><strong>bold</strong></p>")
        end
      end

      context "with a non-Canon node" do
        it "falls back to get_node_text" do
          node = double("generic_node")
          allow(node).to receive(:respond_to?).with(:text).and_return(true)
          allow(node).to receive(:text).and_return("  fallback  ")
          # get_node_text strips ASCII whitespace
          expect(nu.serialize_node_compact(node)).to eq("fallback")
        end
      end

      context "with nil" do
        it "returns an empty string" do
          expect(nu.serialize_node_compact(nil)).to eq("")
        end
      end
    end

    describe ".node_to_display" do
      context "with compact: false (default)" do
        it "returns get_node_text result for an ElementNode" do
          node = element_node("em", children: [text_node("Cereals")])
          # get_node_text calls node.node_info or text; for ElementNode there's no
          # :text method, so it falls through to :node_info
          result = nu.node_to_display(node, compact: false)
          # ElementNode doesn't have .text, so node_info is used
          expect(result).to include("name: em")
        end
      end

      context "with compact: true" do
        it "returns compact XML for an ElementNode" do
          node = element_node("em", children: [text_node("Cereals")])
          expect(nu.node_to_display(node,
                                    compact: true)).to eq("<em>Cereals</em>")
        end

        it "still returns get_node_text for a TextNode" do
          node = text_node("plain text")
          result = nu.node_to_display(node, compact: true)
          # TextNode is not an ElementNode; node_to_display uses get_node_text
          expect(result).to eq("plain text")
        end
      end
    end
  end

  describe Canon::DiffFormatter::DiffDetailFormatterHelpers::DimensionFormatter do
    let(:df) { described_class }

    def text_node(str)
      Canon::Xml::Nodes::TextNode.new(value: str)
    end

    def element_node(name, children: [], attributes: [])
      n = Canon::Xml::Nodes::ElementNode.new(name: name)
      attributes.each { |a| n.add_attribute(a) }
      children.each { |c| n.add_child(c) }
      n
    end

    describe ".format_text_content_details with compact:" do
      let(:node1) { element_node("em", children: [text_node("old")]) } # rubocop:disable RSpec/IndexedLet
      let(:node2) { element_node("em", children: [text_node("new")]) } # rubocop:disable RSpec/IndexedLet
      let(:diff) do
        Canon::Diff::DiffNode.new(node1: node1, node2: node2,
                                  dimension: :text_content,
                                  reason: "content differs")
      end

      it "with compact: false returns node_info-style text in details" do
        detail1, detail2, = df.format_text_content_details(diff, false,
                                                           compact: false)
        # Without compact, get_node_text falls through to node_info for ElementNode
        expect(detail1).to include("name: em")
        expect(detail2).to include("name: em")
      end

      it "with compact: true returns compact XML in details" do
        detail1, detail2, = df.format_text_content_details(diff, false,
                                                           compact: true)
        expect(detail1).to eq("<em>old</em>")
        expect(detail2).to eq("<em>new</em>")
      end

      it "with compact: true the changes summary contains compact XML" do
        _, _, changes = df.format_text_content_details(diff, false,
                                                       compact: true)
        expect(changes).to include("<em>old</em>")
        expect(changes).to include("<em>new</em>")
      end
    end

    describe ".format_fallback_details with compact:" do
      let(:node1) { element_node("strong", children: [text_node("A")]) } # rubocop:disable RSpec/IndexedLet
      let(:node2) { element_node("strong", children: [text_node("B")]) } # rubocop:disable RSpec/IndexedLet
      let(:diff) do
        Canon::Diff::DiffNode.new(node1: node1, node2: node2,
                                  dimension: :unknown,
                                  reason: "fallback")
      end

      it "with compact: false uses format_node_brief (name + text)" do
        detail1, detail2, = df.format_fallback_details(diff, false,
                                                       compact: false)
        # format_node_brief returns "name(\"text\")" style
        expect(detail1).to match(/strong/)
        expect(detail2).to match(/strong/)
      end

      it "with compact: true returns compact XML" do
        detail1, detail2, = df.format_fallback_details(diff, false,
                                                       compact: true)
        expect(detail1).to eq("<strong>A</strong>")
        expect(detail2).to eq("<strong>B</strong>")
      end
    end
  end

  # ── End-to-end: compact_semantic_report through DiffDetailFormatter ─────────

  describe "compact_semantic_report integration" do
    # Comparing two documents where the element type differs so that node1/node2
    # in the diff are ElementNodes (not TextNodes).  The element_structure
    # dimension is used for the name change, but we also use text_content on
    # two different elements so that the nodes themselves are ElementNodes.
    #
    # We use a hand-built diff with ElementNodes to verify the compact flag
    # at the DiffDetailFormatter level.

    def element_node_for_int(name, text_value)
      n = Canon::Xml::Nodes::ElementNode.new(name: name)
      n.add_child(Canon::Xml::Nodes::TextNode.new(value: text_value))
      n
    end

    it "with compact_semantic_report: false the detail for an ElementNode uses node_info style" do
      node1 = element_node_for_int("em", "old text")
      node2 = element_node_for_int("em", "new text")
      diff = Canon::Diff::DiffNode.new(node1: node1, node2: node2,
                                       dimension: :text_content,
                                       reason: "text content differs")
      require "canon/diff_formatter/diff_detail_formatter"
      report = Canon::DiffFormatter::DiffDetailFormatter.format_report(
        [diff],
        use_color: false,
        compact_semantic_report: false,
      )
      # Without compact, format_text_content_details calls get_node_text on an
      # ElementNode, which falls through to node_info → "name: em …"
      expect(report).to include("name: em")
    end

    it "with compact_semantic_report: true the detail for an ElementNode uses compact XML" do
      node1 = element_node_for_int("em", "old text")
      node2 = element_node_for_int("em", "new text")
      diff = Canon::Diff::DiffNode.new(node1: node1, node2: node2,
                                       dimension: :text_content,
                                       reason: "text content differs")
      require "canon/diff_formatter/diff_detail_formatter"
      report = Canon::DiffFormatter::DiffDetailFormatter.format_report(
        [diff],
        use_color: false,
        compact_semantic_report: true,
      )
      # With compact, format_text_content_details calls serialize_node_compact
      expect(report).to include("<em>old text</em>")
      expect(report).to include("<em>new text</em>")
    end

    it "with compact: true via DiffFormatter.new the report uses compact XML" do
      # Full wiring: xml1/xml2 differ at text node level; we build diffs manually
      # so ElementNodes end up as diff nodes
      node1 = element_node_for_int("strong", "Annex A")
      node2 = element_node_for_int("strong", "Annex B")
      diff = Canon::Diff::DiffNode.new(node1: node1, node2: node2,
                                       dimension: :text_content,
                                       reason: "text content differs")
      formatter = Canon::DiffFormatter.new(
        use_color: false,
        compact_semantic_report: true,
      )
      # Simulate comparison_result
      comparison_result = double("comparison_result")
      allow(comparison_result).to receive(:is_a?).with(Canon::Comparison::ComparisonResult).and_return(true)
      allow(comparison_result).to receive_messages(algorithm: :dom,
                                                   differences: [diff], equivalent?: false, original_strings: ["<root/>", "<root/>"], html_version: nil, match_options: nil)

      output = formatter.format_comparison_result(comparison_result, "<root/>",
                                                  "<root/>")
      expect(output).to include("<strong>Annex A</strong>")
      expect(output).to include("<strong>Annex B</strong>")
    end
  end

  # ── End-to-end: expand_difference through DiffDetailFormatter ──────────────

  describe "expand_difference integration" do
    def element_node_for_expand(name, text_value)
      n = Canon::Xml::Nodes::ElementNode.new(name: name)
      n.add_child(Canon::Xml::Nodes::TextNode.new(value: text_value))
      n
    end

    it "with expand_difference: false shows compact XML with content" do
      node1 = element_node_for_expand("biblio-tag", "ISO 712, ")
      node2 = element_node_for_expand("span", "ISO 712, ")
      diff = Canon::Diff::DiffNode.new(node1: node1, node2: node2,
                                       dimension: :element_structure,
                                       reason: "element name differs")
      require "canon/diff_formatter/diff_detail_formatter"
      report = Canon::DiffFormatter::DiffDetailFormatter.format_report(
        [diff],
        use_color: false,
        expand_difference: false,
      )
      expect(report).to include("<biblio-tag>ISO 712, </biblio-tag>")
      expect(report).to include("<span>ISO 712, </span>")
    end

    it "with expand_difference: true shows compact XML with content" do
      node1 = element_node_for_expand("biblio-tag", "ISO 712, ")
      node2 = element_node_for_expand("span", "ISO 712, ")
      diff = Canon::Diff::DiffNode.new(node1: node1, node2: node2,
                                       dimension: :element_structure,
                                       reason: "element name differs")
      require "canon/diff_formatter/diff_detail_formatter"
      report = Canon::DiffFormatter::DiffDetailFormatter.format_report(
        [diff],
        use_color: false,
        expand_difference: true,
      )
      expect(report).to include("<biblio-tag>ISO 712, </biblio-tag>")
      expect(report).to include("<span>ISO 712, </span>")
      expect(report).to include("Element structure changed:")
    end

    it "with expand_difference: true via DiffFormatter.new the report uses full content" do
      node1 = element_node_for_expand("biblio-tag", "ISO 712, ")
      node2 = element_node_for_expand("span", "ISO 712, ")
      diff = Canon::Diff::DiffNode.new(node1: node1, node2: node2,
                                       dimension: :element_structure,
                                       reason: "element name differs")
      formatter = Canon::DiffFormatter.new(
        use_color: false,
        expand_difference: true,
      )
      comparison_result = double("comparison_result")
      allow(comparison_result).to receive(:is_a?).with(Canon::Comparison::ComparisonResult).and_return(true)
      allow(comparison_result).to receive_messages(algorithm: :dom,
                                                   differences: [diff], equivalent?: false, original_strings: ["<root/>", "<root/>"], html_version: nil, match_options: nil)

      output = formatter.format_comparison_result(comparison_result, "<root/>",
                                                  "<root/>")
      expect(output).to include("<biblio-tag>ISO 712, </biblio-tag>")
      expect(output).to include("<span>ISO 712, </span>")
    end
  end

  # ── Element structure diff display ──────────────────────────────────────────

  describe "element_structure diff display" do
    require "canon/diff_formatter/diff_detail_formatter"
    require "canon/diff_formatter/diff_detail_formatter/dimension_formatter"

    def element_node(name, text_value = nil, attrs: {})
      n = Canon::Xml::Nodes::ElementNode.new(name: name)
      attrs.each do |k, v|
        attr_node = Canon::Xml::Nodes::AttributeNode.new(name: k, value: v)
        n.add_attribute(attr_node)
      end
      n.add_child(Canon::Xml::Nodes::TextNode.new(value: text_value)) if text_value
      n
    end

    describe "both elements present, different names" do
      it "shows compact XML for both sides" do
        node1 = element_node("biblio-tag", "ISO 712, ")
        node2 = element_node("span", "ISO 712, ")
        diff = Canon::Diff::DiffNode.new(
          node1: node1, node2: node2,
          dimension: :element_structure, reason: "element name differs",
        )

        detail1, detail2, changes = Canon::DiffFormatter::DiffDetailFormatterHelpers::DimensionFormatter.format_element_structure_details(diff, false)

        expect(detail1).to eq("<biblio-tag>ISO 712, </biblio-tag>")
        expect(detail2).to eq("<span>ISO 712, </span>")
        expect(changes).to include("Element structure changed:")
        expect(changes).to include("<biblio-tag>ISO 712, </biblio-tag>")
        expect(changes).to include("<span>ISO 712, </span>")
      end

      it "shows attributes in compact XML" do
        node1 = element_node("div", "text", attrs: { "class" => "old" })
        node2 = element_node("span", "text", attrs: { "class" => "new" })
        diff = Canon::Diff::DiffNode.new(
          node1: node1, node2: node2,
          dimension: :element_structure, reason: "element name differs",
        )

        detail1, detail2, _changes = Canon::DiffFormatter::DiffDetailFormatterHelpers::DimensionFormatter.format_element_structure_details(diff, false)

        expect(detail1).to include("class=\"old\"")
        expect(detail2).to include("class=\"new\"")
      end
    end

    describe "both elements present, same name (children differ)" do
      it "shows children-differ message" do
        node1 = element_node("div", "old text")
        node2 = element_node("div", "new text")
        diff = Canon::Diff::DiffNode.new(
          node1: node1, node2: node2,
          dimension: :element_structure, reason: "element structure mismatch",
        )

        detail1, detail2, changes = Canon::DiffFormatter::DiffDetailFormatterHelpers::DimensionFormatter.format_element_structure_details(diff, false)

        expect(detail1).to eq("<div>old text</div>")
        expect(detail2).to eq("<div>new text</div>")
        expect(changes).to eq("Element <div> structure changed (children differ)")
      end
    end

    describe "element deleted (node2 is nil)" do
      it "shows removed element with (not present) for the new side" do
        node1 = element_node("removed", "content")
        diff = Canon::Diff::DiffNode.new(
          node1: node1, node2: nil,
          dimension: :element_structure, reason: "element removed",
        )

        detail1, detail2, changes = Canon::DiffFormatter::DiffDetailFormatterHelpers::DimensionFormatter.format_element_structure_details(diff, false)

        expect(detail1).to eq("<removed>content</removed>")
        expect(detail2).to eq("(not present)")
        expect(changes).to include("Element removed:")
        expect(changes).to include("<removed>content</removed>")
      end
    end

    describe "element inserted (node1 is nil)" do
      it "shows added element with (not present) for the old side" do
        node2 = element_node("added", "content")
        diff = Canon::Diff::DiffNode.new(
          node1: nil, node2: node2,
          dimension: :element_structure, reason: "element inserted",
        )

        detail1, detail2, changes = Canon::DiffFormatter::DiffDetailFormatterHelpers::DimensionFormatter.format_element_structure_details(diff, false)

        expect(detail1).to eq("(not present)")
        expect(detail2).to eq("<added>content</added>")
        expect(changes).to include("Element added:")
        expect(changes).to include("<added>content</added>")
      end
    end

    describe "element with no text content" do
      it "serializes as self-closing tag" do
        node1 = element_node("empty")
        node2 = element_node("br")
        diff = Canon::Diff::DiffNode.new(
          node1: node1, node2: node2,
          dimension: :element_structure, reason: "element name differs",
        )

        detail1, detail2, _changes = Canon::DiffFormatter::DiffDetailFormatterHelpers::DimensionFormatter.format_element_structure_details(diff, false)

        expect(detail1).to eq("<empty/>")
        expect(detail2).to eq("<br/>")
      end
    end
  end

  # ── Issue #91: diff report readability for whitespace differences ──────────

  describe Canon::DiffFormatter::DiffDetailFormatter, "Reason line formatting (Issue #91)" do
    def build_diff(reason:, text1: "a", text2: "b")
      n1 = Canon::Xml::Nodes::TextNode.new(value: text1)
      n2 = Canon::Xml::Nodes::TextNode.new(value: text2)
      node = Canon::Diff::DiffNode.new(
        node1: n1, node2: n2,
        dimension: :text_content, reason: reason
      )
      node.normative = true
      node
    end

    it "splits reason into two aligned lines when visualized spaces are present" do
      reason = "Text: \"\u2591\u2591term2\u2591def\u2591\u2591\" " \
               "vs \"\u2591term2\u2591def\u2591\""
      diff = build_diff(reason: reason)
      report = described_class.format_report([diff], use_color: false)
      lines = report.lines.map(&:chomp)

      reason_line = lines.find { |l| l.include?("Reason:") }
      vs_idx = lines.index(reason_line) + 1

      expect(reason_line).to include("Text:")
      expect(reason_line).not_to include(" vs ")
      expect(lines[vs_idx]).to match(/\A\s+vs\.:/)
    end

    it "keeps the reason as a single line when no visualized spaces" do
      diff = build_diff(reason: "only in first: class, id")
      report = described_class.format_report([diff], use_color: false)
      lines = report.lines.map(&:chomp)

      reason_line = lines.find { |l| l.include?("Reason:") }
      expect(reason_line).to include("only in first: class, id")

      vs_idx = lines.index(reason_line) + 1
      expect(lines[vs_idx]).not_to match(/vs\.:/i)
    end
  end

  describe Canon::DiffFormatter::DiffDetailFormatter, "Expected/Actual layout (Issue #91)" do
    def build_diff(text1:, text2:)
      n1 = Canon::Xml::Nodes::TextNode.new(value: text1)
      n2 = Canon::Xml::Nodes::TextNode.new(value: text2)
      node = Canon::Diff::DiffNode.new(
        node1: n1, node2: n2,
        dimension: :text_content, reason: "Text: differs"
      )
      node.normative = true
      node
    end

    context "when both values are short" do
      it "renders Expected and Actual as compact single lines" do
        diff = build_diff(text1: "hello", text2: "world")
        report = described_class.format_report([diff], use_color: false)
        lines = report.lines.map(&:chomp)

        expected_line = lines.find { |l| l.include?("Expected (File 1)") }
        actual_line = lines.find { |l| l.include?("Actual (File 2)") }

        expect(expected_line).to match(/Expected \(File 1\).*:.*"hello"/)
        expect(actual_line).to match(/Actual \(File 2\).*:.*"world"/)
      end

      it "has no blank line between Expected and Actual" do
        diff = build_diff(text1: "hello", text2: "world")
        report = described_class.format_report([diff], use_color: false)
        lines = report.lines.map(&:chomp)

        expected_idx = lines.index { |l| l.include?("Expected (File 1)") }
        actual_idx = lines.index { |l| l.include?("Actual (File 2)") }

        expect(actual_idx).to eq(expected_idx + 1)
      end
    end

    context "when a value is 30+ chars" do
      let(:long_text) { "this is a value that exceeds thirty characters easily" }

      it "renders values on separate indented lines" do
        diff = build_diff(text1: "short", text2: long_text)
        report = described_class.format_report([diff], use_color: false)
        lines = report.lines.map(&:chomp)

        expected_idx = lines.index { |l| l.include?("Expected (File 1)") }
        expect(lines[expected_idx]).to include("Expected (File 1):")
        expect(lines[expected_idx + 1]).to match(/\A\s+"short"/)
      end

      it "has no blank line between Expected and Actual blocks" do
        diff = build_diff(text1: "short", text2: long_text)
        report = described_class.format_report([diff], use_color: false)
        lines = report.lines.map(&:chomp)

        expected_idx = lines.index { |l| l.include?("Expected (File 1)") }
        actual_idx = lines.index { |l| l.include?("Actual (File 2)") }

        # Expected label, Expected value, Actual label (no blank line)
        expect(actual_idx).to eq(expected_idx + 2)
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
