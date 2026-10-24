# frozen_string_literal: true

require "spec_helper"
require "openssl"

# W6.3 review gate for the canonical-digests document: the law
# tokens asserted here read the implementation's own methods, so a
# digest-lane change without a doc update fails.
RSpec.describe Canon::Digest do
  let(:doc) { File.read(File.join(__dir__, "../../../docs/_references/canonical-digests.adoc")) }

  it "exists" do
    expect(File.exist?(File.join(__dir__, "../../../docs/_references/canonical-digests.adoc"))).to be(true)
  end

  it "cites the entry points and the default algorithm" do
    expect(doc).to include("Canon::Digest.digest(content, format")
    expect(doc).to include(described_class::DEFAULT_ALGORITHM)
    expect(doc).to include("canonical_form(content, format)")
  end

  it "cites the XML lane's C14N form and rejects the pretty form" do
    expect(doc).to include("Canonical XML 1.1")
    expect(doc).to include("pretty: false")
    expect(described_class.canonical_form("<a b='1' c='2'/>", :xml))
      .to eq(Canon::Xml::C14n.canonicalize("<a b='1' c='2'/>", with_comments: false))
  end

  it "exercises the equivalence law the doc states" do
    # attribute order insignificant in XML
    expect(described_class.digest("<r x='1' y='2'/>", :xml))
      .to eq(described_class.digest("<r y='2' x='1'/>", :xml))
    # element order significant
    expect(described_class.digest("<r><a/><b/></r>", :xml))
      .not_to eq(described_class.digest("<r><b/><a/></r>", :xml))
    # mapping key order insignificant in JSON and YAML
    expect(described_class.digest('{"a":1,"b":2}', :json))
      .to eq(described_class.digest('{"b":2,"a":1}', :json))
    expect(described_class.digest("a: 1\nb: 2\n", :yaml))
      .to eq(described_class.digest("b: 2\na: 1\n", :yaml))
  end

  it "keeps digest(canonical form) == digest(source) on every lane" do
    %i[xml html yaml json].each do |format|
      source = case format
               when :xml then "<r><a x='1'>t</a></r>"
               when :html then "<html><body><p>Hello</p></body></html>"
               when :yaml then "a: 1\nb: [x, y]\n"
               else "{\"a\":1,\"b\":[\"x\",\"y\"]}"
               end
      form = described_class.canonical_form(source, format)
      expect(described_class.digest(form, format))
        .to eq(described_class.digest(source, format))
    end
  end
end
