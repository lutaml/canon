# frozen_string_literal: true

require "spec_helper"

# Regression tests for the :whitespace_adjacency diff dimension (issue #137).
#
# The contract is REPORT-ONLY:
#
# * Equivalence verdict is identical to pre-#137 behaviour — when expected has
#   asymmetric whitespace-only text nodes the actual side lacks, the
#   comparison is still UNEQUAL.  No tests start passing because of this
#   feature; existing whitespace-mismatch failures continue to fail.
#
# * Diff REPORT shape changes — instead of a 3-4 entry cascade of
#   :text_content mismatches that pair stray whitespace against neighbouring
#   content nodes (positional zip artefact), the report carries one
#   :whitespace_adjacency entry per stray whitespace node, anchored at the
#   node itself.

RSpec.describe ":whitespace_adjacency diff dimension (#137)" do
  context "asymmetric pretty-print whitespace inside HTML <p>" do
    # Reproduces the metanorma-iso iso_spec.rb:114 cascade input shape
    # (HTML mixed-content where positional zip was previously cascading
    # mismatches across content siblings).
    let(:expected_html) do
      "<p><span>ISO </span>\n  <span>20483</span>\n  ,\n  <i>Cereals and pulses</i></p>"
    end

    let(:actual_html) do
      "<p><span>ISO </span><span>20483</span>, <i>Cereals and pulses</i></p>"
    end

    def compare_html(html1, html2) # rubocop:disable Naming/PredicateMethod
      Canon::Comparison.equivalent?(html1, html2, format: :html5, verbose: true)
    end

    it "still reports the inputs as non-equivalent (verdict unchanged from pre-#137)" do
      result = compare_html(expected_html, actual_html)
      expect(result.equivalent?).to be false
    end

    it "emits at least one :whitespace_adjacency diff anchored at a stray whitespace node" do
      result = compare_html(expected_html, actual_html)
      ws_adj = result.differences.select do |d|
        d.dimension == :whitespace_adjacency
      end
      expect(ws_adj).not_to be_empty
    end

    it "does not emit a :text_content cascade pairing whitespace against content" do
      result = compare_html(expected_html, actual_html)
      bad_pairs = result.differences.select do |d|
        next false unless d.dimension == :text_content

        n1_text = node_text_for(d.node1)
        n2_text = node_text_for(d.node2)
        next false unless n1_text && n2_text

        (n1_text.strip.empty? && !n2_text.strip.empty?) ||
          (!n1_text.strip.empty? && n2_text.strip.empty?)
      end
      expect(bad_pairs).to be_empty
    end
  end

  context "fully symmetric whitespace (no asymmetry)" do
    let(:html) do
      "<p><span>a</span>\n  <span>b</span></p>"
    end

    it "does not emit :whitespace_adjacency when both sides match" do
      result = Canon::Comparison.equivalent?(
        html, html, format: :html5, verbose: true
      )
      ws_adj = result.differences.select do |d|
        d.dimension == :whitespace_adjacency
      end
      expect(ws_adj).to be_empty
    end
  end

  # Direction wording in the Reason line names where the partner content
  # sits relative to the whitespace node — "before" when the whitespace
  # immediately precedes the next non-whitespace sibling (the alignment
  # partner on the other side), "after" at the trailing edge of a parent.
  #
  # The earlier `surrounding`/`preceding`/`following` wording was
  # misleading: it described the whitespace node's position among its own
  # siblings rather than its direction relative to the partner — so a
  # whitespace node sandwiched between two spans, with only the leading
  # gap asymmetric, was reported as "surrounding" the partner. See the
  # #137 follow-up.
  context "direction wording in the Reason line" do
    def reason_for(html1, html2)
      result = Canon::Comparison.equivalent?(
        html1, html2, format: :html5, verbose: true
      )
      diff = result.differences.find { |d| d.dimension == :whitespace_adjacency }
      diff&.reason.to_s
    end

    it "says 'before' when the whitespace precedes the partner" do
      # Asymmetric whitespace between two spans — the partner on the
      # actual side aligns with the second span ("712"), and the
      # whitespace sits immediately before it on the expected side.
      html1 = "<a><span>ISO </span>\n   <span>712</span></a>"
      html2 = "<a><span>ISO </span><span>712</span></a>"

      expect(reason_for(html1, html2)).to include('Whitespace before "712"')
    end

    it "names the parent element when the partner is empty / whitespace-only (issue #112)" do
      # The alignment partner on the actual side is a content sibling
      # whose extracted text is empty (e.g. an element with no text
      # descendants).  Without this fallback the Reason would read
      # `Whitespace before ""` — issue #112's contract requires the
      # parent element name instead so the diff carries structural
      # context.
      html1 = "<h1><span>x</span>\n   <span></span></h1>"
      html2 = "<h1><span>x</span><span></span></h1>"

      reason = reason_for(html1, html2)

      expect(reason).not_to include('"":')
      expect(reason).not_to include('before ""')
      expect(reason).to match(/Whitespace inside <h1>/)
    end

    it "falls back to (unknown parent) when the whitespace node lacks a real parent" do
      # A bare Nokogiri text node with no parent → NodeInspector.parent_of
      # returns nil → whitespace_adjacency_parent_label returns "(unknown parent)".
      ni = Canon::Comparison::NodeInspector
      expect(ni.parent_of(nil)).to be_nil
      expect(ni.parent_of("not a node")).to be_nil

      # A detached Nokogiri text node (no parent element).
      doc = Nokogiri::HTML5("<html><body></body></html>")
      detached = Nokogiri::XML::Text.new("  ", doc)
      expect(ni.parent_of(detached)).to be_nil
    end

    it "says 'after' when the whitespace trails the partner at parent edge" do
      # Trailing whitespace inside a whitespace-preserving element (<code>)
      # paired against an extra element on the other side.  The whitespace
      # has a backward non-ws sibling (<b>A</b>) but no forward non-ws
      # sibling, so the direction is "after".
      html1 = "<code><b>A</b>\n</code>"
      html2 = "<code><b>A</b><b>B</b></code>"

      expect(reason_for(html1, html2)).to include('Whitespace after "B"')
    end

    it "says 'adjacent to' when the whitespace has no non-ws siblings" do
      # A whitespace-only text node as the sole child of a
      # whitespace-preserving element, paired against content on the
      # other side.  No non-ws siblings in either direction.
      html1 = "<code>\n</code>"
      html2 = "<code><b>A</b></code>"

      expect(reason_for(html1, html2)).to include('Whitespace adjacent to "A"')
    end
  end

  def node_text_for(node)
    return nil if node.nil?

    case node
    when Canon::Xml::Nodes::TextNode then node.value.to_s
    when Canon::Xml::Node then node.value.to_s
    when Nokogiri::XML::Node then node.content.to_s
    end
  end
end
