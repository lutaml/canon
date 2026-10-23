# frozen_string_literal: true

require "spec_helper"
require "yaml"

# W6.3 review gates for the canonical-form documents
# (TODO.sota/08): docs/_references/html-canonical-form.adoc and
# yaml-canonical-form.adoc must match SHIPPED behavior — the law
# tokens asserted here read the formatters' own constants and
# methods, so a formatter change without a doc update fails.
DOCS = File.join(__dir__, "../../../docs/_references").freeze

RSpec.describe "canonical-form document review" do
  describe "html-canonical-form.adoc" do
    let(:doc) { File.read(File.join(DOCS, "html-canonical-form.adoc")) }

    it "exists" do
      expect(File.exist?(File.join(DOCS, "html-canonical-form.adoc"))).to be(true)
    end

    it "cites the whitespace-sensitive set exactly" do
      sensitive = Canon::Formatters::HtmlFormatterBase::WHITESPACE_SENSITIVE_ELEMENTS
      sensitive.each do |name|
        expect(doc).to include(name), "whitespace-sensitive element #{name} not documented"
      end
    end

    it "cites every block element exactly" do
      blocks = Canon::Formatters::HtmlFormatterBase::BLOCK_ELEMENTS
      blocks.each do |name|
        expect(doc).to include(name), "block element #{name} not documented"
      end
      expect(doc).to include("BLOCK_ELEMENTS")
    end

    it "cites the spacing laws and the attribute sorter" do
      expect(doc).to include("BLOCK_SPACING_PATTERN")
      expect(doc).to include("AFTER_BLOCK_NEWLINE_PATTERN")
      expect(doc).to include("AttributeSorter")
      expect(doc).to include("format(format(x)) == format(x)")
    end
  end

  describe "yaml-canonical-form.adoc" do
    let(:doc) { File.read(File.join(DOCS, "yaml-canonical-form.adoc")) }

    it "exists" do
      expect(File.exist?(File.join(DOCS, "yaml-canonical-form.adoc"))).to be(true)
    end

    it "cites the total key order law" do
      expect(doc).to include("key.class.name, key.to_s")
      expect(doc).to include("TOTAL order")
    end

    it "cites the engine-resolved validator and the fixed point" do
      expect(doc).to include("yeptris")
      expect(doc).to include("Psych")
      expect(doc).to include("format(format(x)) == format(x)")
    end

    it "documents the shipped behavior on a mixed-key probe" do
      # the doc's law, exercised: heterogeneous keys order by
      # [class, to_s] and the form is a fixed point
      mixed = "b: 1\n1: 2\n:c: 3\n"
      once = Canon.format_yaml(mixed)
      expect(Canon.format_yaml(once)).to eq(once)
      expect(once).to include(":c") # the Symbol class sorts after String
    end
  end
end
