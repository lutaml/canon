# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Digest do
  describe ".digest" do
    it "is deterministic for the same document" do
      doc = "<root><a>1</a></root>"
      expect(described_class.digest(doc, :xml)).to eq(described_class.digest(doc.dup, :xml))
    end

    it "is format-aware" do
      expect(described_class.digest("a: 1\n", :yaml))
        .to eq(described_class.digest("a: 1", :yaml))
      expect(described_class.digest("a: 1\n", :yaml))
        .not_to eq(described_class.digest("{\"a\":1}", :json))
    end

    it "matches the format shorthand" do
      doc = "<root><a>1</a></root>"
      expect(Canon.digest_xml(doc)).to eq(described_class.digest(doc, :xml))
      expect(Canon.digest(doc, :xml)).to eq(Canon.digest_xml(doc))
    end

    it "accepts other OpenSSL digest algorithms" do
      doc = "<root><a>1</a></root>"
      require "openssl"
      expected = OpenSSL::Digest.new("sha512")
        .hexdigest(described_class.canonical_form(doc, :xml))
      expect(described_class.digest(doc, :xml, algorithm: "sha512")).to eq(expected)
    end

    it "raises on an unsupported format" do
      expect { described_class.digest("x", :nope) }.to raise_error(Canon::Error)
    end
  end

  describe "the equivalence contract" do
    it "gives one digest to documents equivalent under the canonical form" do
      expect(Canon.digest_yaml("b: 2\na: 1\n")).to eq(Canon.digest_yaml("a: 1\nb: 2\n"))
      expect(Canon.digest_json('{"a":1,"b":[1,2]}'))
        .to eq(Canon.digest_json('{ "b" : [ 1, 2 ], "a" : 1 }'))
      expect(Canon.digest_xml('<root x="1" y="2"><a/></root>'))
        .to eq(Canon.digest_xml('<root y="2" x="1"><a/></root>'))
    end

    it "keeps digests distinct when content differs" do
      expect(Canon.digest_yaml("a: 1\n")).not_to eq(Canon.digest_yaml("a: 2\n"))
      expect(Canon.digest_xml("<a/>")).not_to eq(Canon.digest_xml("<b/>"))
    end

    it "treats XML element order as significant" do
      expect(Canon.digest_xml("<r><a/><b/></r>"))
        .not_to eq(Canon.digest_xml("<r><b/><a/></r>"))
    end
  end
end
