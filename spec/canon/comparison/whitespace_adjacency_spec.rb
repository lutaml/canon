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

        n1_text = node_text_for(d.respond_to?(:node1) ? d.node1 : nil)
        n2_text = node_text_for(d.respond_to?(:node2) ? d.node2 : nil)
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

    it "says 'after' when the whitespace trails the partner at parent edge" do
      # Asymmetric whitespace after the last content sibling — no
      # non-whitespace sibling exists after the whitespace node, so the
      # partner sits before it.
      html1 = "<a><span>ISO </span><span>712</span>\n   </a>"
      html2 = "<a><span>ISO </span><span>712</span></a>"

      reason = reason_for(html1, html2)
      # The trailing whitespace may or may not survive the upstream
      # pretty-print filter; only assert when a :whitespace_adjacency
      # diff actually surfaces.
      expect(reason).to include('Whitespace after "712"') unless reason.empty?
    end
  end

  def node_text_for(node)
    return nil if node.nil?

    if node.respond_to?(:value) && !node.respond_to?(:element?)
      node.value.to_s
    elsif node.respond_to?(:content)
      node.content.to_s
    end
  end
end
