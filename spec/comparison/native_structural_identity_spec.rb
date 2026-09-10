# frozen_string_literal: true

require "spec_helper"

# The accelerator is optional: load the local leptris checkout
# when present so the fast-path specs exercise the real engine.
begin
  require "leptris/xml"
rescue LoadError, NameError
  begin
    require "leptris/xml/diff"
  rescue LoadError, NameError
    nil
  end
end

RSpec.describe Canon::Comparison::NativeStructuralIdentity do
  describe ".available?" do
    it "reflects the leptris diff surface" do
      expected = !defined?(Leptris::XML::Diff).nil?
      expect(described_class.available?).to eq(expected)
    end
  end

  describe ".identical?" do
    it "accepts byte-different but structurally identical trees" do
      # Quote style differs; the parsed trees are identical. (The
      # digest is exact: attribute ORDER and whitespace-only text
      # nodes are significant — canon's looser profiles still get
      # their answers from the normal pipeline.)
      a = "<r a='1'><i>text</i><j/></r>"
      b = '<r a="1"><i>text</i><j/></r>'
      expect(described_class.identical?(a, b)).to be true
    end

    it "rejects structurally different trees" do
      expect(described_class.identical?(
        "<r><i>1</i></r>", "<r><i>2</i></r>")).to be false
    end

    it "returns nil (no opinion) on unparseable input" do
      expect(described_class.identical?("<r>", "<r/>")).to be_nil
    end
  end
end

RSpec.describe "XmlComparator native fast path" do
  it "equivalent? short-circuits structurally identical strings" do
    a = "<r a='1'><i>text</i></r>"
    b = '<r a="1"><i>text</i></r>' 
    expect(
      Canon::Comparison::XmlComparator.equivalent?(a, b)
    ).to be true
  end

  it "still detects real differences through the pipeline" do
    expect(
      Canon::Comparison::XmlComparator.equivalent?(
        "<r><i>1</i></r>", "<r><i>2</i></r>")
    ).to be false
    expect(
      Canon::Comparison::XmlComparator.equivalent?(
        "<r><i>x</i></r>", "<r><i>y</i><j/></r>")
    ).to be false
  end

  it "does not fire in verbose mode" do
    a = "<r><i>1</i></r>"
    b = "<r><i>1</i></r>"
    result = Canon::Comparison::XmlComparator.equivalent?(
      a, b, verbose: true)
    expect(result).to be_truthy
  end
end
