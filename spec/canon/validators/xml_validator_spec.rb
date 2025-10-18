# frozen_string_literal: true

require "spec_helper"
require "canon/validators/xml_validator"

RSpec.describe Canon::Validators::XmlValidator do
  describe ".validate!" do
    context "with valid XML" do
      it "does not raise error for well-formed XML" do
        xml = "<root><child>value</child></root>"
        expect { described_class.validate!(xml) }.not_to raise_error
      end

      it "does not raise error for XML with attributes" do
        xml = '<root attr="value"><child>text</child></root>'
        expect { described_class.validate!(xml) }.not_to raise_error
      end

      it "does not raise error for complex nested XML" do
        xml = <<~XML
          <?xml version="1.0"?>
          <root>
            <parent>
              <child id="1">value1</child>
              <child id="2">value2</child>
            </parent>
          </root>
        XML
        expect { described_class.validate!(xml) }.not_to raise_error
      end

      it "does not raise error for empty string" do
        expect { described_class.validate!("") }.not_to raise_error
      end

      it "does not raise error for nil" do
        expect { described_class.validate!(nil) }.not_to raise_error
      end
    end

    context "with malformed XML" do
      it "raises ValidationError for unclosed tag" do
        xml = "<root><child>value"
        expect { described_class.validate!(xml) }.to raise_error(
          Canon::ValidationError,
          /XML Validation Error/
        )
      end

      it "raises ValidationError for mismatched tags" do
        xml = "<root><child>value</wrong></root>"
        expect { described_class.validate!(xml) }.to raise_error(
          Canon::ValidationError
        ) do |error|
          expect(error.format).to eq(:xml)
          expect(error.message).to match(/XML Validation Error/)
        end
      end

      it "raises ValidationError with line information" do
        xml = <<~XML
          <root>
            <child>value
          </root>
        XML
        expect { described_class.validate!(xml) }.to raise_error(
          Canon::ValidationError
        ) do |error|
          expect(error.line).to be_a(Integer)
        end
      end

      it "raises ValidationError for missing closing bracket" do
        xml = "<root<child>value</child></root>"
        expect { described_class.validate!(xml) }.to raise_error(
          Canon::ValidationError,
          /XML Validation Error/
        )
      end
    end
  end
end
