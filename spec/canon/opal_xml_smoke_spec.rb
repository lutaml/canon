# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Canon XML Opal smoke test", if: RUBY_ENGINE == "opal" do
  it "formats XML" do
    xml = "<root><child>text</child></root>"
    result = Canon.format(xml, :xml)
    expect(result).to include("root")
    expect(result).to include("child")
  end

  it "detects equivalent XML as equivalent" do
    xml1 = "<root><child>text</child></root>"
    xml2 = "<root><child>text</child></root>"
    expect(Canon::Comparison.equivalent?(xml1, xml2, format: :xml)).to be true
  end

  it "detects different XML as not equivalent" do
    xml1 = "<root><child>text</child></root>"
    xml2 = "<root><child>different</child></root>"
    expect(Canon::Comparison.equivalent?(xml1, xml2, format: :xml)).to be false
  end

  it "detects missing elements" do
    xml1 = "<root><a/><b/></root>"
    xml2 = "<root><a/></root>"
    expect(Canon::Comparison.equivalent?(xml1, xml2, format: :xml)).to be false
  end

  it "detects attribute differences" do
    xml1 = '<root attr="value1"/>'
    xml2 = '<root attr="value2"/>'
    expect(Canon::Comparison.equivalent?(xml1, xml2, format: :xml)).to be false
  end

  it "handles namespace differences" do
    xml1 = '<root xmlns:ns="http://a.com"><ns:child/></root>'
    xml2 = '<root xmlns:ns="http://b.com"><ns:child/></root>'
    expect(Canon::Comparison.equivalent?(xml1, xml2, format: :xml)).to be false
  end

  it "uses spec_friendly profile for whitespace-insensitive comparison" do
    xml1 = "<root>  text  </root>"
    xml2 = "<root>text</root>"
    expect(Canon::Comparison.equivalent?(xml1, xml2,
                                         format: :xml,
                                         profile: :spec_friendly)).to be true
  end
end
