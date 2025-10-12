# frozen_string_literal: true

RSpec.describe Canon::Formatters::XmlFormatter do
  it "canonicalizes XML per C14N 1.1 spec" do
    input = "<root><a>1</a><b>2</b></root>"

    result = described_class.format(input)
    # C14N 1.1 produces compact output without indentation
    expect(result).to eq("<root><a>1</a><b>2</b></root>")
  end

  it "parses XML into a Nokogiri document" do
    input = "<root><a>1</a><b>2</b></root>"
    result = described_class.parse(input)

    expect(result).to be_a(Nokogiri::XML::Document)
    expect(result.at_xpath("//a").text).to eq("1")
    expect(result.at_xpath("//b").text).to eq("2")
  end

  Dir.glob("spec/fixtures/xml/*.raw.xml").each do |f|
    c14n_filename = f.gsub(".raw.", ".c14n.")

    it "canonicalizes #{File.basename(f)}" do
      xml_raw = File.read(f)
      xml_c14n = File.read(c14n_filename)

      input = Canon.format(xml_raw, :xml)
      output = Canon.format(xml_c14n, :xml)

      expect(output).to be_xml_equivalent_to(input)

      # backward compatibility
      expect(output).to be_analogous_with(input)
    end
  end
end
