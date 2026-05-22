# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::XmlBackend do
  describe ".active" do
    it "returns :nokogiri when Nokogiri is loaded" do
      expect(described_class.active).to eq(:nokogiri) if defined?(Nokogiri)
    end
  end

  describe ".nokogiri?" do
    it "returns true under MRI with Nokogiri" do
      expect(described_class.nokogiri?).to be true if defined?(Nokogiri)
    end
  end

  describe ".moxml?" do
    it "returns false under MRI with Nokogiri" do
      expect(described_class.moxml?).to be false if defined?(Nokogiri)
    end

    it "returns true when moxml backend is forced" do
      described_class.reset!
      allow(described_class).to receive(:detect).and_return(:moxml)
      expect(described_class.moxml?).to be true
      described_class.reset!
    end
  end

  describe ".reset!" do
    it "clears the cached backend" do
      original = described_class.active
      described_class.reset!
      expect(described_class.active).to eq(original)
    end
  end
end
