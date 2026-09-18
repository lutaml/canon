# frozen_string_literal: true

require "spec_helper"

# The probe must speak the builder protocol the SAX drivers forward to
# (`cdata`), not the nokogiri callback spelling — CDATA-bearing input
# raised NoMethodError through MoxmlDriver under the flipped leptris
# engine.
RSpec.describe "Sax.probe with CDATA" do
  it "probes documents containing CDATA sections without raising" do
    xml = "<root><a>text</a><b><![CDATA[literal <data> & stuff]]></b></root>"

    probe = Canon::Xml::Sax.probe(xml)
    expect(probe.signature).to include("a")
    expect(probe.signature).to include("b")
  end

  it "ignores content, so CDATA and plain text probe identically" do
    with_cdata = Canon::Xml::Sax.probe(
      "<root><a><![CDATA[ignored]]></a></root>",
    )
    with_text = Canon::Xml::Sax.probe("<root><a>ignored</a></root>")

    expect(with_cdata.signature).to eq(with_text.signature)
  end
end
