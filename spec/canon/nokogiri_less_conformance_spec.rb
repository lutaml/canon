# frozen_string_literal: true

# Engine-agnostic conformance: canon's XML core must behave identically
# whether nokogiri is installed or not (moxml + leptris is the shipping
# engine everywhere). This suite runs in BOTH modes — with nokogiri
# present and under CANON_SIMULATE_NO_NOKOGIRI=1.
RSpec.describe "Canon without nokogiri (XML core conformance)" do
  let(:xml) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root xmlns:ns="http://example.com/ns">
        <ns:child id="1" class="a">text one</ns:child>
        <child id="2">text &amp; more</child>
        <empty/>
        <!-- a comment -->
      </root>
    XML
  end

  it "resolves the engine without reference to nokogiri" do
    backend = Canon::XmlBackend.active
    adapter = Canon::XmlParsing.moxml_adapter_name

    expect(Canon::XmlBackend::VALID_BACKENDS).to include(backend)
    if defined?(Nokogiri)
      expect(backend).to eq(:moxml).or eq(:nokogiri)
    else
      # Without nokogiri the only possible engine is moxml.
      expect(backend).to eq(:moxml)
      expect(adapter).not_to eq(:nokogiri)
    end
  end

  it "parses XML into the active engine's document" do
    doc = Canon.format(xml, :xml) && Canon.parse(xml, :xml)
    expect(Canon::XmlParsing.document?(doc)).to be(true)
  end

  it "canonicalizes XML to stable bytes" do
    c14n = Canon::Xml::C14n.canonicalize(xml, with_comments: false)

    expect(c14n).to include("<ns:child")
    expect(c14n).to include("text one")
    expect(c14n).not_to include("\n  ") # pretty whitespace is canonicalized away
    expect(Canon::Xml::C14n.canonicalize(c14n, with_comments: false)).to eq(c14n)
  end

  it "pretty-prints XML" do
    pretty = Canon.format(xml, :xml)

    expect(pretty).to include("<ns:child")
    expect(Canon.format(pretty, :xml)).to eq(pretty) # idempotent
  end

  it "compares equivalent XML documents as equivalent" do
    expect(Canon::Comparison.equivalent?(xml, xml)).to be(true)
  end

  it "compares documents that differ only in attribute order as equivalent" do
    reordered = xml.sub('id="1" class="a"', 'class="a" id="1"')

    expect(Canon::Comparison.equivalent?(xml, reordered)).to be(true)
  end

  it "detects real differences" do
    changed = xml.sub("text one", "TEXT ONE")

    expect(Canon::Comparison.equivalent?(xml, changed)).to be(false)
  end

  it "validates well-formed XML" do
    expect { Canon::Validators::XmlValidator.validate!(xml) }.not_to raise_error
  end

  it "rejects malformed XML with a ValidationError" do
    expect do
      Canon::Validators::XmlValidator.validate!("<root><unclosed></root>")
    end.to raise_error(Canon::ValidationError)
  end

  it "rejects not-well-formed fragments (mismatched tags)" do
    expect do
      Canon::Validators::XmlValidator.validate!("<a><b></a>")
    end.to raise_error(Canon::ValidationError)
  end
end
