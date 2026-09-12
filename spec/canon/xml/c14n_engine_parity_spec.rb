# frozen_string_literal: true

require "spec_helper"

# Native leptris C14N 1.1 vs canon's Ruby processor: byte-identical
# output is the gate for the native lane in C14n.canonicalize
# (opt-in via CANON_C14N_BACKEND=leptris until leptris#1015 closes).
CORPUS = {
  "simple doc" => %(<?xml version="1.0"?><root><a>1</a><b>2</b></root>),
  "escapes basic" => %(<r a="&lt;&amp;&quot;">t &amp; u</r>),
  "cdata" => %(<r><![CDATA[raw < & stuff]]></r>),
  "comments" => %(<r><!-- c -->a<!-- d --></r>),
  "doctype defaults" => %(<!DOCTYPE r [<!ATTLIST a def CDATA "dv">]><r><a/></r>),
  "cr references" => %(<r>a&#xD;b&#xA;c</r>),
  "empty default ns" => %(<r xmlns=""><a/><inner xmlns="urn:i"/></r>),
  "mixed content" => %(<r>text <b>bold</b> more <i>it</i> tail</r>),
  "empty elements" => %(<r><a/><b></b><c/></r>),
  "xml attributes" => %(<r xml:lang="en" xml:space="default"><a xml:id="x1"/></r>),
  "attribute ordering" => %(<e z="1" a="2" m="3" x:n="4" xmlns:x="urn:x"/>),
}.freeze

# rubocop:disable-next Style/StringConcatenation -- fixture assembly
BIG_DOC = '<?xml version="1.0"?><root xmlns="urn:r" xmlns:x="urn:x">' +
  Array.new(500) { |i| %(<item i="#{i}" x:k="v">text &amp; content #{i} <b>m</b></item>) }.join +
  "</root>"

# Upstream-tracked divergences (leptris native C14N 1.1 vs canon's
# Ruby processor). When these pass, the default flips per the gate.
# "attribute ordering" moved to CORPUS: fixed in libleptris 1.9.144.1.
PENDING_UPSTREAM = {
  "prefixed element under mixed default+prefixed ns" => ['<root xmlns="urn:r" xmlns:x="urn:x"><x:b/></root>',
                                                         "leptris#1015 — native serializes <b> losing the x: prefix"],
  "right angle escaping" => ["<r>t &gt; w</r>",
                             "leptris#1015 — native emits raw > in text; C14N escapes it"],
  "tab escaping in attributes" => ['<unicode><x y="&#9;">z</x></unicode>',
                                   "leptris#1015 — native emits raw \\t; C14N writes &#x9;"],
  "prefix rebinding" => ['<r xmlns:p="urn:1"><p:a><b xmlns:p="urn:2"><p:c/></b></p:a></r>',
                         "leptris#1015 — prefix-loss family: <p:a>/<p:c> serialized unprefixed"],
  "document-level PIs" => ['<?xml version="1.0"?><?target data?><r/><?after d2?>',
                           "leptris#1015 — native drops prolog/epilog PIs"],
  "CR reference preservation" => ["<r><e>&#xD;</e>text</r>",
                                  "canon-side: the DOM records parse drops the CR text node (SAX keeps it) — native preserves &#xD; correctly per C14N"],
}.freeze

RSpec.describe "C14N engine parity" do
  def native_lane_forced?
    ENV["CANON_C14N_BACKEND"].to_s.casecmp("leptris").zero? &&
      Canon::XmlBackend.moxml? &&
      Canon::XmlParsing.moxml_adapter_name == :leptris
  end

  def ruby_canonicalize(xml)
    old = ENV.fetch("CANON_C14N_BACKEND", nil)
    ENV["CANON_C14N_BACKEND"] = "ruby"
    begin
      Canon::Xml::C14n.canonicalize(xml)
    ensure
      ENV["CANON_C14N_BACKEND"] = old
    end
  end

  CORPUS.each do |name, xml|
    it "canonicalizes #{name} byte-identically" do
      skip "native lane not forced (CANON_C14N_BACKEND=leptris)" unless native_lane_forced?

      native = Canon::Xml::C14n.native_canonicalize(xml, false)
      expect(native).not_to be_nil
      expect(native).to eq(ruby_canonicalize(xml))
    end
  end

  it "canonicalizes a large document byte-identically" do
    skip "native lane not forced" unless native_lane_forced?

    native = Canon::Xml::C14n.native_canonicalize(BIG_DOC, false)
    expect(native).to eq(ruby_canonicalize(BIG_DOC))
    expect(native.length).to be > 10_000
  end

  PENDING_UPSTREAM.each do |name, (xml, reason)|
    xit "#{name} (#{reason})" do
      native = Canon::Xml::C14n.native_canonicalize(xml, false)
      skip "native lane not forced" if native.nil?
      expect(native).to eq(ruby_canonicalize(xml))
    end
  end

  it "keeps the Ruby processor for with_comments" do
    expect(Canon::Xml::C14n.native_canonicalize("<r/>", true)).to be_nil
  end

  it "is not active unless forced" do
    old = ENV.fetch("CANON_C14N_BACKEND", nil)
    ENV["CANON_C14N_BACKEND"] = nil
    begin
      expect(Canon::Xml::C14n.native_canonicalize("<r/>", false)).to be_nil
    ensure
      ENV["CANON_C14N_BACKEND"] = old
    end
  end
end
