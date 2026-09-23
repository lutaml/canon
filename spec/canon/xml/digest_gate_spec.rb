# frozen_string_literal: true

require "spec_helper"

# Document-level Merkle-digest gate (libleptris #869): equal root
# digests + identical document-level skeletons imply content
# identity, which implies equivalence under every canon match
# behavior. The one unsounded restriction — attribute order, which
# the digest cannot see — skips the gate.
RSpec.describe "XML digest-gate fast path" do
  def equivalent?(left, right, **opts)
    Canon::Comparison.equivalent?(left, right, { format: :xml }.merge(opts))
  end

  let(:compact_doc) { %(<catalog><item id="1">Content 1</item><item id="2">Content 2</item></catalog>) }
  let(:pretty_doc) do
    <<~XML
      <catalog>
        <item id="1">Content 1</item>
        <item id="2">Content 2</item>
      </catalog>
    XML
  end

  it "answers formatting-only differences via the digest" do
    expect(Canon::Xml::DigestGate.available?).to be true unless
      Canon::XmlBackend.nokogiri?
    expect(equivalent?(compact_doc, pretty_doc)).to be true
  end

  it "still answers content differences correctly" do
    changed = compact_doc.sub("Content 1", "CHANGED")
    expect(equivalent?(compact_doc, changed)).to be false
  end

  it "does not false-positive when digests are unavailable" do
    # Adapter-level nil digest (Opal / non-leptris) must never make two
    # different documents look equal via [nil, skeleton] == [nil, skeleton].
    a = %(<root><a>1</a></root>)
    b = %(<root><a>2</a></root>)
    expect(Canon::Xml::DigestGate.equal?(a, b)).to be false
    expect(equivalent?(a, b)).to be false
  end

  it "sees document-level comment differences (skeleton)" do
    expect(equivalent?(%(<!--c--><r><a/></r>), %(<r><a/></r>))).to be false
  end

  it "sees document-level PI differences (skeleton)" do
    expect(equivalent?(%(<?pi d?><r><a/></r>), %(<r><a/></r>))).to be false
  end

  it "sees comments inside the root (digest coverage)" do
    expect(equivalent?(%(<r><!--c--><a/></r>), %(<r><a/></r>))).to be false
  end

  it "skips the gate under strict attribute order" do
    expect(equivalent?(%(<r a="1" b="2"/>), %(<r b="2" a="1"/>))).to be true
    expect(
      equivalent?(%(<r a="1" b="2"/>), %(<r b="2" a="1"/>),
                  match: { attribute_order: :strict }),
    ).to be false
  end

  it "does not bypass verbose results" do
    result = equivalent?(compact_doc, pretty_doc, verbose: true)
    expect(result).to be_a(Canon::Comparison::ComparisonResult)
    expect(result.equivalent?).to be true
  end

  it "certifies digest-equal clean documents and declines the rest" do
    expect(Canon::Xml::DigestGate.certify(compact_doc, pretty_doc)).to be_truthy
    expect(
      Canon::Xml::DigestGate.certify(compact_doc,
                                     compact_doc.sub("Content 1", "CHANGED")),
    ).to be_nil
    # Recover-error documents decline so verbose reports keep the
    # parse-error banner.
    junk = "  <catalog/>  trailing"
    expect(Canon::Xml::DigestGate.certify(junk, junk.dup)).to be_nil
  end

  it "serves verbose equivalent results through the gate" do
    result = equivalent?(compact_doc, pretty_doc, verbose: true)
    expect(result.differences).to be_empty
    expect(result.equivalent?).to be true
    expect(result.parse_errors?).to be false

    # Materialized display strings match the full pipeline's own
    # serialization (gate declined via strict attribute order, which
    # these single-attribute documents ignore).
    declined = equivalent?(compact_doc, pretty_doc, verbose: true,
                                                    match: { attribute_order: :strict })
    expect(result.preprocessed_strings).to eq(declined.preprocessed_strings)
  end

  it "skips the signature probe when the host enables order-sensitive digests" do
    ENV["LEPTRIS_DIGEST_ATTR_ORDER"] = "1"
    begin
      result = equivalent?(compact_doc, pretty_doc, verbose: true)
      expect(result.equivalent?).to be true
      expect(result.differences).to be_empty
      expect(Canon::Xml::DigestGate.attr_order_digest?).to be true
    ensure
      ENV.delete("LEPTRIS_DIGEST_ATTR_ORDER")
    end
    expect(Canon::Xml::DigestGate.attr_order_digest?).to be false
  end

  it "routes error-bearing verbose pairs through the pipeline" do
    junk = "  <catalog/>  trailing"
    result = equivalent?(junk, junk.dup, verbose: true)
    expect(result.parse_errors?).to be true
    expect(result.equivalent?).to be true
  end

  it "keeps the parse-error banner for byte-equal malformed documents" do
    # Byte-equal input skips the signature comparison, but the SAX
    # error scan still runs: the banner must survive the shortcut.
    dup_lang = %(<body lang="en" xml:lang="en" xml:lang="en"><div>x</div></body>)
    result = equivalent?(dup_lang, dup_lang.dup, verbose: true)
    expect(result.parse_errors?).to be true
    expect(result.equivalent?).to be true
  end

  it "falls through on unparseable input with normal error behavior" do
    expect(equivalent?("<r>", "<r/>")).to be true
  end

  it "is inert under the nokogiri engine" do
    old_env = ENV.fetch("CANON_XML_BACKEND", nil)
    ENV["CANON_XML_BACKEND"] = "nokogiri"
    Canon::XmlBackend.reset!
    begin
      expect(Canon::Xml::DigestGate.available?).to be false
      expect(equivalent?(compact_doc, pretty_doc)).to be true
    ensure
      ENV["CANON_XML_BACKEND"] = old_env
      Canon::XmlBackend.reset!
    end
  end
end
