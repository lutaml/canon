# frozen_string_literal: true

require "spec_helper"
require "canon/comparison"
require "canon/comparison/xml_comparator"
require "canon/comparison/html_comparator"
require "canon/comparison/json_comparator"
require "canon/comparison/yaml_comparator"

RSpec.describe Canon::Comparison do
  describe "format detection" do
    describe ".detect_format" do
      it "detects XML from Moxml node" do
        xml = Moxml.new.parse("<root/>")
        expect(described_class.send(:detect_format, xml)).to eq(:xml)
      end

      it "detects XML from Nokogiri XML document" do
        xml = Nokogiri::XML("<root/>")
        expect(described_class.send(:detect_format, xml)).to eq(:xml)
      end

      it "detects HTML from Nokogiri HTML document" do
        html = Nokogiri::HTML("<html><body>test</body></html>")
        expect(described_class.send(:detect_format, html)).to eq(:html)
      end

      it "detects HTML5 from Nokogiri HTML5 document" do
        html = Nokogiri::HTML5("<!DOCTYPE html><html><body>test</body></html>")
        expect(described_class.send(:detect_format, html)).to eq(:html)
      end

      it "detects ruby_object from Hash" do
        obj = { "key" => "value" }
        expect(described_class.send(:detect_format, obj)).to eq(:ruby_object)
      end

      it "detects ruby_object from Array" do
        obj = [1, 2, 3]
        expect(described_class.send(:detect_format, obj)).to eq(:ruby_object)
      end

      it "raises error for unknown object type" do
        expect do
          described_class.send(:detect_format, Object.new)
        end.to raise_error(Canon::Error, /Unknown format for object/)
      end
    end

    describe ".detect_string_format" do
      it "detects YAML from --- prefix" do
        yaml = "---\nkey: value"
        expect(described_class.send(:detect_string_format, yaml)).to eq(:yaml)
      end

      it "detects YAML from key: value pattern" do
        yaml = "key: value"
        expect(described_class.send(:detect_string_format, yaml)).to eq(:yaml)
      end

      it "detects JSON from { prefix" do
        json = '{"key":"value"}'
        expect(described_class.send(:detect_string_format, json)).to eq(:json)
      end

      it "detects JSON from [ prefix" do
        json = "[1, 2, 3]"
        expect(described_class.send(:detect_string_format, json)).to eq(:json)
      end

      it "detects HTML from <!DOCTYPE html prefix" do
        html = "<!DOCTYPE html><html></html>"
        expect(described_class.send(:detect_string_format, html)).to eq(:html)
      end

      it "detects HTML from <html prefix" do
        html = "<html><body>test</body></html>"
        expect(described_class.send(:detect_string_format, html)).to eq(:html)
      end

      it "detects HTML from <HTML prefix (case insensitive)" do
        html = "<HTML><BODY>test</BODY></HTML>"
        expect(described_class.send(:detect_string_format, html)).to eq(:html)
      end

      it "defaults to XML for unknown strings" do
        xml = "<root><child/></root>"
        expect(described_class.send(:detect_string_format, xml)).to eq(:xml)
      end
    end
  end

  describe "format mismatch detection" do
    it "raises error when comparing XML with JSON" do
      xml = "<root/>"
      json = '{"key":"value"}'

      expect do
        described_class.equivalent?(xml, json)
      end.to raise_error(Canon::CompareFormatMismatchError,
                         /Cannot compare different formats: xml vs json/)
    end

    it "raises error when comparing HTML with YAML" do
      html = "<html><body>test</body></html>"
      yaml = "key: value"

      expect do
        described_class.equivalent?(html, yaml)
      end.to raise_error(Canon::CompareFormatMismatchError,
                         /Cannot compare different formats: html vs yaml/)
    end

    it "raises error when comparing JSON with YAML" do
      json = '{"key":"value"}'
      yaml = "key: value"

      expect do
        described_class.equivalent?(json, yaml)
      end.to raise_error(Canon::CompareFormatMismatchError,
                         /Cannot compare different formats: json vs yaml/)
    end

    it "allows comparing ruby objects with JSON" do
      obj1 = { "key" => "value" }
      obj2 = '{"key":"value"}'

      # This should work because JSON strings are parsed to ruby objects
      expect(described_class.equivalent?(obj2, obj1)).to be true
    end
  end

  describe "delegation to format-specific modules" do
    describe "XML comparison" do
      it "delegates to Xml module for XML strings" do
        xml1 = "<root><a>1</a></root>"
        xml2 = "<root><a>1</a></root>"

        expect(described_class.equivalent?(xml1, xml2)).to be true
      end

      it "delegates to Xml module for Moxml nodes" do
        xml1 = Moxml.new.parse("<root><a>1</a></root>")
        xml2 = Moxml.new.parse("<root><a>1</a></root>")

        expect(described_class.equivalent?(xml1, xml2)).to be true
      end
    end

    describe "HTML comparison" do
      it "delegates to Html module for HTML strings" do
        html1 = "<html><body><p>test</p></body></html>"
        html2 = "<html><body>  <p>  test  </p>  </body></html>"

        expect(described_class.equivalent?(html1, html2)).to be true
      end

      it "delegates to Html module for Nokogiri HTML documents" do
        html1 = Nokogiri::HTML("<html><body>test</body></html>")
        html2 = Nokogiri::HTML("<html><body>  test  </body></html>")

        expect(described_class.equivalent?(html1, html2)).to be true
      end
    end

    describe "JSON comparison" do
      it "delegates to Json module for JSON strings" do
        json1 = '{"a":1,"b":2}'
        json2 = '{"b":2,"a":1}'

        expect(described_class.equivalent?(json1, json2)).to be true
      end

      it "delegates to Json module for Ruby Hash objects" do
        obj1 = { "a" => 1, "b" => 2 }
        obj2 = { "b" => 2, "a" => 1 }

        expect(described_class.equivalent?(obj1, obj2)).to be true
      end

      it "delegates to Json module for Ruby Array objects" do
        obj1 = [1, 2, 3]
        obj2 = [1, 2, 3]

        expect(described_class.equivalent?(obj1, obj2)).to be true
      end
    end

    describe "YAML comparison" do
      it "delegates to Yaml module for YAML strings" do
        yaml1 = "---\na: 1\nb: 2\n"
        yaml2 = "---\nb: 2\na: 1\n"

        expect(described_class.equivalent?(yaml1, yaml2)).to be true
      end
    end
  end

  describe Canon::Comparison::XmlComparator do
    describe ".equivalent?" do
      it "compares XML strings" do
        xml1 = "<root><a>1</a></root>"
        xml2 = "<root><a>1</a></root>"

        expect(described_class.equivalent?(xml1, xml2)).to be true
      end

      it "returns false for different XML" do
        xml1 = "<root><a>1</a></root>"
        xml2 = "<root><a>2</a></root>"

        expect(described_class.equivalent?(xml1, xml2)).to be false
      end

      it "supports verbose mode" do
        xml1 = "<root><a>1</a></root>"
        xml2 = "<root><a>2</a></root>"

        result = described_class.equivalent?(xml1, xml2, verbose: true)
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
      end
    end
  end

  describe Canon::Comparison::HtmlComparator do
    describe ".equivalent?" do
      it "compares HTML strings" do
        html1 = "<div><p>test</p></div>"
        html2 = "<div>  <p>  test  </p>  </div>"

        expect(described_class.equivalent?(html1, html2)).to be true
      end

      it "returns false for different HTML" do
        html1 = "<div><p>hello</p></div>"
        html2 = "<div><p>goodbye</p></div>"

        expect(described_class.equivalent?(html1, html2)).to be false
      end

      it "supports verbose mode" do
        html1 = "<div><p>hello</p></div>"
        html2 = "<div><p>goodbye</p></div>"

        result = described_class.equivalent?(html1, html2, verbose: true)
        expect(result).to be_a(Hash)
        expect(result[:differences]).not_to be_empty
      end
    end
  end

  describe Canon::Comparison::JsonComparator do
    describe ".equivalent?" do
      it "compares JSON strings" do
        json1 = '{"a":1,"b":2}'
        json2 = '{"b":2,"a":1}'

        expect(described_class.equivalent?(json1, json2)).to be true
      end

      it "compares Ruby Hash objects" do
        obj1 = { "a" => 1, "b" => 2 }
        obj2 = { "b" => 2, "a" => 1 }

        expect(described_class.equivalent?(obj1, obj2)).to be true
      end

      it "returns false for different JSON" do
        json1 = '{"a":1}'
        json2 = '{"a":2}'

        expect(described_class.equivalent?(json1, json2)).to be false
      end

      it "supports verbose mode" do
        json1 = '{"a":1}'
        json2 = '{"a":2}'

        result = described_class.equivalent?(json1, json2, verbose: true)
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.first[:diff_code]).to eq(Canon::Comparison::UNEQUAL_PRIMITIVES)
      end
    end
  end

  describe Canon::Comparison::YamlComparator do
    describe ".equivalent?" do
      it "compares YAML strings" do
        yaml1 = "---\na: 1\nb: 2\n"
        yaml2 = "---\nb: 2\na: 1\n"

        expect(described_class.equivalent?(yaml1, yaml2)).to be true
      end

      it "compares Ruby Hash objects" do
        obj1 = { "a" => 1, "b" => 2 }
        obj2 = { "b" => 2, "a" => 1 }

        expect(described_class.equivalent?(obj1, obj2)).to be true
      end

      it "returns false for different YAML" do
        yaml1 = "a: 1"
        yaml2 = "a: 2"

        expect(described_class.equivalent?(yaml1, yaml2)).to be false
      end

      it "supports verbose mode" do
        yaml1 = "a: 1"
        yaml2 = "a: 2"

        result = described_class.equivalent?(yaml1, yaml2, verbose: true)
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
      end
    end
  end

  describe "backward compatibility" do
    it "maintains backward compatibility for XML comparison" do
      xml1 = "<root><a b='2' c='1'>text</a></root>"
      xml2 = "<root><a c='1' b='2'>text</a></root>"

      expect(described_class.equivalent?(xml1, xml2)).to be true
    end

    it "maintains backward compatibility for HTML comparison" do
      html1 = "<html><body><p>test</p></body></html>"
      html2 = "<html><body>  <p>  test  </p>  </body></html>"

      expect(described_class.equivalent?(html1, html2)).to be true
    end

    it "maintains backward compatibility with verbose mode" do
      xml1 = "<root><a>1</a></root>"
      xml2 = "<root><a>2</a></root>"

      result = described_class.equivalent?(xml1, xml2, verbose: true)
      expect(result).to be_an(Array)
      expect(result).not_to be_empty
    end
  end
end
