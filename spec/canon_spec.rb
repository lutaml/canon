# frozen_string_literal: true

RSpec.describe Canon do
  it "has a version number" do
    expect(Canon::VERSION).not_to be nil
  end

  describe ".format" do
    it "formats XML content when format is :xml" do
      input = "<root><a>1</a><b>2</b></root>"
      expect(Canon::Formatters::XmlFormatter).to receive(:format).with(input)
      Canon.format(input, :xml)
    end

    it "formats YAML content when format is :yaml" do
      input = "---\na: 1\nb: 2\n"
      expect(Canon::Formatters::YamlFormatter).to receive(:format).with(input)
      Canon.format(input, :yaml)
    end

    it "formats JSON content when format is :json" do
      input = '{"a":1,"b":2}'
      expect(Canon::Formatters::JsonFormatter).to receive(:format).with(input)
      Canon.format(input, :json)
    end

    it "raises an error for unsupported formats" do
      expect do
        Canon.format("content",
                     :unsupported)
      end.to raise_error(Canon::Error, "Unsupported format: unsupported")
    end
  end

  describe ".parse" do
    it "parses XML content when format is :xml" do
      input = "<root><a>1</a><b>2</b></root>"
      expect(Canon::Formatters::XmlFormatter).to receive(:parse).with(input)
      Canon.parse(input, :xml)
    end

    it "parses YAML content when format is :yaml" do
      input = "---\na: 1\nb: 2\n"
      expect(Canon::Formatters::YamlFormatter).to receive(:parse).with(input)
      Canon.parse(input, :yaml)
    end

    it "parses JSON content when format is :json" do
      input = '{"a":1,"b":2}'
      expect(Canon::Formatters::JsonFormatter).to receive(:parse).with(input)
      Canon.parse(input, :json)
    end

    it "raises an error for unsupported formats" do
      expect do
        Canon.parse("content",
                    :unsupported)
      end.to raise_error(Canon::Error, "Unsupported format: unsupported")
    end
  end

  describe "shorthand methods" do
    let(:xml_input) { "<root><a>1</a><b>2</b></root>" }
    let(:yaml_input) { "---\na: 1\nb: 2\n" }
    let(:json_input) { '{"a":1,"b":2}' }

    describe "parse shorthand methods" do
      it "delegates to parse with correct format" do
        expect(Canon).to receive(:parse).with(xml_input, :xml)
        Canon.parse_xml(xml_input)

        expect(Canon).to receive(:parse).with(yaml_input, :yaml)
        Canon.parse_yaml(yaml_input)

        expect(Canon).to receive(:parse).with(json_input, :json)
        Canon.parse_json(json_input)
      end
    end

    describe "format shorthand methods" do
      it "delegates to format with correct format" do
        expect(Canon).to receive(:format).with(xml_input, :xml)
        Canon.format_xml(xml_input)

        expect(Canon).to receive(:format).with(yaml_input, :yaml)
        Canon.format_yaml(yaml_input)

        expect(Canon).to receive(:format).with(json_input, :json)
        Canon.format_json(json_input)
      end
    end
  end
end
