# frozen_string_literal: true

# Nokogiri-absence CONTRACT: only meaningful when nokogiri is truly
# unavailable, so the suite is defined solely under the simulation (with
# nokogiri installed the absence assertions would be vacuous or false).
if ENV["CANON_SIMULATE_NO_NOKOGIRI"] == "1"
  RSpec.describe "Canon nokogiri optionality contract" do
    it "does not load nokogiri when canon is required" do
      expect(defined?(Nokogiri)).to be_nil
    end

    it "leaves nokogiri unloaded after XML core usage" do
      Canon.format("<a><b>x</b></a>", :xml)
      Canon::Comparison.equivalent?("<a/>", "<a/>")

      expect(defined?(Nokogiri)).to be_nil
    end

    it "raises a helpful Canon::Error for HTML formatting" do
      expect do
        Canon.format("<p>hi</p>", :html)
      end.to raise_error(Canon::Error, /nokogiri/)
    end

    it "raises a helpful Canon::Error for the forced raw-nokogiri engine" do
      stub_const_env = nil
      begin
        prev = ENV.fetch("CANON_XML_BACKEND", nil)
        ENV["CANON_XML_BACKEND"] = "nokogiri"
        described = Canon::XmlBackend
        described.reset!
        stub_const_env = prev

        expect do
          described.active
        end.to raise_error(Canon::Error, /nokogiri/)
      ensure
        ENV["CANON_XML_BACKEND"] = stub_const_env
        Canon::XmlBackend.reset!
      end
    end
  end
end
