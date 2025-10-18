# frozen_string_literal: true

require "spec_helper"
require "canon/validators/yaml_validator"

RSpec.describe Canon::Validators::YamlValidator do
  describe ".validate!" do
    context "with valid YAML" do
      it "does not raise error for valid YAML" do
        yaml = "key: value"
        expect { described_class.validate!(yaml) }.not_to raise_error
      end

      it "does not raise error for nested YAML" do
        yaml = <<~YAML
          parent:
            child: value
        YAML
        expect { described_class.validate!(yaml) }.not_to raise_error
      end

      it "does not raise error for empty/nil input" do
        expect { described_class.validate!("") }.not_to raise_error
        expect { described_class.validate!(nil) }.not_to raise_error
      end
    end

    context "with malformed YAML" do
      it "raises ValidationError for unclosed bracket" do
        yaml = "key: {unclosed"
        expect { described_class.validate!(yaml) }.to raise_error(
          Canon::ValidationError,
        ) do |error|
          expect(error.format).to eq(:yaml)
          expect(error.message).to match(/YAML Validation Error/)
        end
      end

      it "raises ValidationError with line information" do
        yaml = "key: [unclosed"
        expect { described_class.validate!(yaml) }.to raise_error(
          Canon::ValidationError,
        ) do |error|
          expect(error.line).to be_a(Integer) if error.line
        end
      end
    end
  end
end
