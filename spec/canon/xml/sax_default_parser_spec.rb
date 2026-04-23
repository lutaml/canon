# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SAX parser as default" do
  after do
    Canon::Config.instance.xml.diff.reset!
  end

  describe "config option" do
    it "defaults to :sax" do
      expect(Canon::Config.instance.xml.diff.parser).to eq(:sax)
    end

    it "can be set to :dom" do
      Canon::Config.instance.xml.diff.parser = :dom
      expect(Canon::Config.instance.xml.diff.parser).to eq(:dom)
    end

    it "validates the value" do
      expect {
        Canon::Config.instance.xml.diff.parser = :invalid
      }.to raise_error(ArgumentError, /Invalid value/)
    end
  end

  describe "comparison results match" do
    let(:xml1) { "<root><item>Hello</item></root>" }
    let(:xml2) { "<root><item>World</item></root>" }

    it "SAX and DOM produce equivalent? results" do
      Canon::Config.instance.xml.diff.parser = :sax
      sax_result = Canon::Comparison.equivalent?(xml1, xml2)

      Canon::Config.instance.xml.diff.parser = :dom
      dom_result = Canon::Comparison.equivalent?(xml1, xml2)

      expect(sax_result).to eq(dom_result)
    end

    it "SAX produces correct equivalence for identical documents" do
      expect(Canon::Comparison.equivalent?(xml1, xml1)).to be true
    end

    it "SAX produces correct non-equivalence for differing documents" do
      expect(Canon::Comparison.equivalent?(xml1, xml2)).to be false
    end

    it "SAX produces same verbose differences as DOM" do
      Canon::Config.instance.xml.diff.parser = :sax
      sax_result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true)

      Canon::Config.instance.xml.diff.parser = :dom
      dom_result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true)

      expect(sax_result.equivalent?).to eq(dom_result.equivalent?)
      expect(sax_result.differences.size).to eq(dom_result.differences.size)
    end
  end

  describe "C14N uses DOM regardless of parser config" do
    it "canonicalizes correctly even with SAX as default" do
      Canon::Config.instance.xml.diff.parser = :sax
      xml = '<root attr="value"><child>text</child></root>'
      result = Canon::Xml::C14n.canonicalize(xml, with_comments: false)
      expect(result).to include("<root")
      expect(result).to include("<child>text</child>")
    end
  end
end
