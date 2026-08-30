# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::XmlBackend do
  # The default engine is :nokogiri on CRuby (conformance — see
  # spec/canon/xml/engine_parity_spec.rb) and :moxml under Opal.
  # CANON_XML_BACKEND forces either engine.
  let(:forced) { ENV.fetch("CANON_XML_BACKEND", nil) }

  after { described_class.reset! }

  describe ".active" do
    it "returns the forced backend when CANON_XML_BACKEND is set" do
      skip "no forced backend" unless forced

      expect(described_class.active).to eq(forced.to_sym)
    end

    it "follows moxml's resolved adapter (leptris default when installed)" do
      skip "backend is forced" if forced
      skip "requires CRuby + Nokogiri" if RUBY_ENGINE == "opal"

      expected = Canon::XmlParsing.moxml_adapter_name == :nokogiri ? :nokogiri : :moxml
      expect(described_class.active).to eq(expected)
    end
  end

  describe ".nokogiri? / .moxml?" do
    it "match the active backend" do
      expect(described_class.nokogiri?).to eq(described_class.active == :nokogiri)
      expect(described_class.moxml?).to eq(described_class.active == :moxml)
    end

    it "returns true when moxml backend is forced" do
      allow(ENV).to receive(:fetch).with("CANON_XML_BACKEND", nil).and_return("moxml")
      described_class.reset!
      expect(described_class.moxml?).to be true
      expect(described_class.nokogiri?).to be false
    end
  end

  describe ".reset!" do
    it "clears the cached backend" do
      original = described_class.active
      described_class.reset!
      expect(described_class.active).to eq(original)
    end
  end

  describe "invalid CANON_XML_BACKEND" do
    around do |example|
      prev = ENV.fetch("CANON_XML_BACKEND", nil)
      ENV["CANON_XML_BACKEND"] = "oga"
      described_class.reset!
      example.run
      ENV["CANON_XML_BACKEND"] = prev
      described_class.reset!
    end

    it "raises" do
      expect { described_class.active }.to raise_error(Canon::Error, /Invalid CANON_XML_BACKEND/)
    end
  end
end
