# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Xml::C14n do
  describe "W3C C14N 1.1 Specification Examples" do
    context "Example 3.1: PIs, Comments, and Outside of Document Element" do
      it "canonicalizes without comments" do
        input = File.read("spec/fixtures/c14n/example-3.1-pis-comments.input.xml")
        expected = File.read("spec/fixtures/c14n/example-3.1-pis-comments.canonical.xml")

        result = described_class.canonicalize(input, with_comments: false)

        expect(result.strip).to eq(expected.strip)
      end
    end

    context "Example 3.3: Start and End Tags" do
      it "canonicalizes with proper namespace and attribute ordering" do
        pending "libleptris 1.9.7 applies DTD ATTLIST default attributes by " \
                "default (e9 gains attr=\"default\"), diverging from libxml2's " \
                "no-DTDATTR default and the W3C canonical form" if Canon::XmlBackend.moxml?
        input = File.read("spec/fixtures/c14n/example-3.3-start-end-tags.input.xml")
        expected = File.read("spec/fixtures/c14n/example-3.3-start-end-tags.canonical.xml")

        result = described_class.canonicalize(input, with_comments: false)

        expect(result.strip).to eq(expected.strip)
      end
    end
  end
end
