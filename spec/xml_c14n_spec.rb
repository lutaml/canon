require_relative "../lib/xml-c14n"

RSpec.describe Xml::C14n do
  describe "backward compatibility" do
    it "delegates Xml::C14n.format to Canon.format" do
      input = "<root><a>1</a><b>2</b></root>"
      expect(Canon::Formatters::XmlFormatter).to receive(:format).with(input)
      Xml::C14n.format(input)
    end

    it "delegates Xml::C14n.parse to Canon.parse" do
      input = "<root><a>1</a><b>2</b></root>"
      expect(Canon::Formatters::XmlFormatter).to receive(:parse).with(input)
      Xml::C14n.parse(input)
    end
  end
end
