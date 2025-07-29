# frozen_string_literal: true

RSpec.describe Canon do
  let(:xml_input) { "<root><a>1</a><b>2</b></root>" }
  let(:yaml_input) { "---\na: 1\nb: 2\n" }
  let(:json_input) { '{"a":1,"b":2}' }

  describe ".format" do
    it "formats XML content when format is :xml" do
      expect(Canon::Formatters::XmlFormatter).to receive(:format)
        .with(xml_input)
      Canon.format(xml_input, :xml)
    end

    it "formats YAML content when format is :yaml" do
      expect(Canon::Formatters::YamlFormatter).to receive(:format)
        .with(yaml_input)
      Canon.format(yaml_input, :yaml)
    end

    it "formats JSON content when format is :json" do
      expect(Canon::Formatters::JsonFormatter).to receive(:format)
        .with(json_input)
      Canon.format(json_input, :json)
    end

    it "raises an error for unsupported formats" do
      expect do
        Canon.format("content", :unsupported)
      end.to raise_error(Canon::Error, "Unsupported format: unsupported")
    end
  end

  describe ".parse" do
    it "parses XML content when format is :xml" do
      expect(Canon::Formatters::XmlFormatter).to receive(:parse)
        .with(xml_input)
      Canon.parse(xml_input, :xml)
    end

    it "parses YAML content when format is :yaml" do
      expect(Canon::Formatters::YamlFormatter).to receive(:parse)
        .with(yaml_input)
      Canon.parse(yaml_input, :yaml)
    end

    it "parses JSON content when format is :json" do
      expect(Canon::Formatters::JsonFormatter).to receive(:parse)
        .with(json_input)
      Canon.parse(json_input, :json)
    end

    it "raises an error for unsupported formats" do
      expect do
        Canon.parse("content", :unsupported)
      end.to raise_error(Canon::Error, "Unsupported format: unsupported")
    end
  end

  describe "shorthand methods" do
    describe "parse shorthand methods" do
      it "parse_xml delegates to parse with :xml format" do
        expect(Canon).to receive(:parse).with(xml_input, :xml)
        Canon.parse_xml(xml_input)
      end

      it "parse_yaml delegates to parse with :yaml format" do
        expect(Canon).to receive(:parse).with(yaml_input, :yaml)
        Canon.parse_yaml(yaml_input)
      end

      it "parse_json delegates to parse with :json format" do
        expect(Canon).to receive(:parse).with(json_input, :json)
        Canon.parse_json(json_input)
      end
    end

    describe "format shorthand methods" do
      it "format_xml delegates to format with :xml format" do
        expect(Canon).to receive(:format).with(xml_input, :xml)
        Canon.format_xml(xml_input)
      end

      it "format_yaml delegates to format with :yaml format" do
        expect(Canon).to receive(:format).with(yaml_input, :yaml)
        Canon.format_yaml(yaml_input)
      end

      it "format_json delegates to format with :json format" do
        expect(Canon).to receive(:format).with(json_input, :json)
        Canon.format_json(json_input)
      end
    end
  end
end
