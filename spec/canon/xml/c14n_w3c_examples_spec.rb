# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Xml::C14n do
  describe "W3C C14N 1.1 Specification Examples" do
    context "Example 3.1: PIs, Comments, and Outside of Document Element" do
      it "canonicalizes without comments" do
        # The fixture pins the spec-correct document order (prolog PI
        # first). The Ruby processor emits root-first for document-level
        # PIs — a known non-conformance — so this example requires the
        # native lane (leptris; the default when available).
        native_lane = !ENV["CANON_C14N_BACKEND"].to_s.casecmp("ruby").zero? &&
          Canon::XmlBackend.moxml? &&
          Canon::XmlParsing.moxml_adapter_name == :leptris
        skip "document-order PIs need the native lane" unless native_lane

        input = File.read("spec/fixtures/c14n/example-3.1-pis-comments.input.xml")
        expected = File.read("spec/fixtures/c14n/example-3.1-pis-comments.canonical.xml")

        result = described_class.canonicalize(input, with_comments: false)

        expect(result.strip).to eq(expected.strip)
      end
    end

    context "Example 3.3: Start and End Tags" do
      it "canonicalizes with proper namespace and attribute ordering" do
        input = File.read("spec/fixtures/c14n/example-3.3-start-end-tags.input.xml")
        expected = File.read("spec/fixtures/c14n/example-3.3-start-end-tags.canonical.xml")

        result = described_class.canonicalize(input, with_comments: false)

        expect(result.strip).to eq(expected.strip)
      end
    end
  end
end
