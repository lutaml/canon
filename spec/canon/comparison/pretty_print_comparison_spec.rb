# frozen_string_literal: true

require "spec_helper"
require "canon/comparison"

# Tests for the pretty_printed_expected / pretty_printed_received match options.
#
# When either flag is true, whitespace-only text nodes that begin with "\n"
# inside :normalize-classified elements are treated as structural indentation
# from the pretty-printer and excluded from the comparison.  Nodes under
# :strict elements are always respected; nodes under :insensitive elements are
# already dropped.
#
# The flags are asymmetric: pretty_printed_expected only strips structural
# whitespace from the expected (first) document; pretty_printed_received only
# strips it from the received (second) document.

RSpec.describe "pretty_printed_expected / pretty_printed_received match options" do
  # Helper: compare two XML strings with optional match options.
  # Returns true iff the comparison is equivalent.
  def equivalent?(expected_xml, received_xml, match_opts = {})
    result = Canon::Comparison.equivalent?(
      expected_xml,
      received_xml,
      verbose: false,
      match: match_opts,
    )
    case result
    when Canon::Comparison::ComparisonResult then result.equivalent?
    when Array then result.empty?
    else result
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # :insensitive context (default for XML, no whitespace lists configured)
  # ──────────────────────────────────────────────────────────────────────────

  context "in :insensitive elements (default XML behaviour)" do
    let(:compact)  { "<root><clause><a/><b/></clause></root>" }
    let(:indented) { "<root><clause>\n  <a/>\n  <b/>\n</clause></root>" }

    it "is already equivalent without any flags (whitespace dropped by default)" do
      expect(equivalent?(compact, indented)).to be true
    end

    it "remains equivalent with pretty_printed_expected: true" do
      expect(equivalent?(indented, compact,
                         pretty_printed_expected: true)).to be true
    end

    it "remains equivalent with pretty_printed_received: true" do
      expect(equivalent?(compact, indented,
                         pretty_printed_received: true)).to be true
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # :normalize context
  # ──────────────────────────────────────────────────────────────────────────

  context "in :normalize elements" do
    # fmt-title and semx are classified as :normalize by the test options
    let(:norm_opts) do
      { collapse_whitespace_elements: %w[fmt-title semx] }
    end

    let(:compact_xml) do
      "<root><fmt-title><semx>Foreword</semx></fmt-title></root>"
    end

    let(:indented_xml) do
      "<root><fmt-title>\n  <semx>Foreword</semx>\n</fmt-title></root>"
    end

    it "is NOT equivalent by default (whitespace nodes present in one side)" do
      expect(equivalent?(indented_xml, compact_xml, **norm_opts)).to be false
    end

    it "is equivalent when pretty_printed_expected: true (strip from expected)" do
      expect(equivalent?(indented_xml, compact_xml,
                         **norm_opts,
                         pretty_printed_expected: true)).to be true
    end

    it "is equivalent when pretty_printed_received: true (strip from received)" do
      expect(equivalent?(compact_xml, indented_xml,
                         **norm_opts,
                         pretty_printed_received: true)).to be true
    end

    it "is equivalent when both flags are true" do
      expect(equivalent?(indented_xml, indented_xml,
                         **norm_opts,
                         pretty_printed_expected: true,
                         pretty_printed_received: true)).to be true
    end

    it "detects real content differences even when pretty_printed_expected: true" do
      changed_xml = "<root><fmt-title>\n  <semx>DIFFERENT</semx>\n</fmt-title></root>"
      expect(equivalent?(changed_xml, compact_xml,
                         **norm_opts,
                         pretty_printed_expected: true)).to be false
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Asymmetry: flags only strip from their respective side
  # ──────────────────────────────────────────────────────────────────────────

  context "asymmetric behaviour" do
    let(:norm_opts) do
      { collapse_whitespace_elements: %w[p] }
    end

    let(:compact_xml)  { "<root><p><em>text</em></p></root>" }
    let(:indented_xml) { "<root><p>\n  <em>text</em>\n</p></root>" }

    it "pretty_printed_expected: true strips from expected but not received" do
      # expected=indented (stripped), received=compact → equivalent
      expect(equivalent?(indented_xml, compact_xml,
                         **norm_opts,
                         pretty_printed_expected: true,
                         pretty_printed_received: false)).to be true
    end

    it "pretty_printed_received: true strips from received but not expected" do
      # expected=compact, received=indented (stripped) → equivalent
      expect(equivalent?(compact_xml, indented_xml,
                         **norm_opts,
                         pretty_printed_expected: false,
                         pretty_printed_received: true)).to be true
    end

    it "pretty_printed_expected: true does NOT strip from received" do
      # expected=compact (no \n nodes), received=indented (\n nodes present)
      # Flag is only for expected → received \n nodes are kept → NOT equivalent
      expect(equivalent?(compact_xml, indented_xml,
                         **norm_opts,
                         pretty_printed_expected: true,
                         pretty_printed_received: false)).to be false
    end

    it "pretty_printed_received: true does NOT strip from expected" do
      # expected=indented (\n nodes present), received=compact (no \n nodes)
      # Flag is only for received → expected \n nodes are kept → NOT equivalent
      expect(equivalent?(indented_xml, compact_xml,
                         **norm_opts,
                         pretty_printed_expected: false,
                         pretty_printed_received: true)).to be false
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # :strict context — whitespace always preserved
  # ──────────────────────────────────────────────────────────────────────────

  context "in :strict elements" do
    let(:strict_opts) do
      { preserve_whitespace_elements: %w[pre] }
    end

    let(:compact_xml)  { "<root><pre><code>text</code></pre></root>" }
    let(:indented_xml) { "<root><pre>\n  <code>text</code>\n</pre></root>" }

    it "is NOT equivalent even with pretty_printed_expected: true (strict preserves whitespace)" do
      expect(equivalent?(indented_xml, compact_xml,
                         **strict_opts,
                         pretty_printed_expected: true)).to be false
    end

    it "is NOT equivalent even with pretty_printed_received: true (strict preserves whitespace)" do
      expect(equivalent?(compact_xml, indented_xml,
                         **strict_opts,
                         pretty_printed_received: true)).to be false
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Space-only nodes (no newline) are NOT treated as structural
  # ──────────────────────────────────────────────────────────────────────────

  context "space-only (non-newline) whitespace nodes in :normalize elements" do
    let(:norm_opts) do
      { collapse_whitespace_elements: %w[p] }
    end

    # " <em>text</em>" → has a TextNode " " (space only, no \n)
    let(:space_xml)   { "<root><p> <em>text</em></p></root>" }
    let(:compact_xml) { "<root><p><em>text</em></p></root>" }

    it "retains space-only nodes even with pretty_printed_expected: true" do
      # A " " node does not start with "\n" → kept → the two sides differ
      expect(equivalent?(space_xml, compact_xml,
                         **norm_opts,
                         pretty_printed_expected: true)).to be false
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Multi-level nesting
  # ──────────────────────────────────────────────────────────────────────────

  context "multi-level nesting with :normalize elements at different depths" do
    let(:norm_opts) do
      {
        collapse_whitespace_elements: %w[title semx],
        pretty_printed_expected: true,
      }
    end

    let(:indented_xml) do
      <<~XML
        <root>
          <clause>
            <title>
              <semx>Hello</semx>
            </title>
          </clause>
        </root>
      XML
    end

    let(:compact_xml) do
      "<root><clause><title><semx>Hello</semx></title></clause></root>"
    end

    it "strips structural newlines at every :normalize level" do
      expect(equivalent?(indented_xml, compact_xml, **norm_opts)).to be true
    end
  end
end
