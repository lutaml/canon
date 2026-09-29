# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Xml::Nodes::AttributeNode do
  it "compares by value: name, namespace URI, and prefix, never identity" do
    a = described_class.new(name: "id", value: "7")
    b = described_class.new(name: "id", value: "7")
    c = described_class.new(name: "id", value: "8")
    xml_ns = described_class.new(
      name: "space", value: "preserve",
      namespace_uri: "http://www.w3.org/XML/1998/namespace", prefix: "xml"
    )
    expect(a).to eq(b)
    expect(a).not_to eq(c)
    expect(a).not_to eq(xml_ns)
    expect([a]).to eq([described_class.new(name: "id", value: "7")])
  end
end
