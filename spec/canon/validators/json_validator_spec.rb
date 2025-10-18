# frozen_string_literal: true

require "spec_helper"
require "canon/validators/json_validator"

RSpec.describe Canon::Validators::JsonValidator do
  describe ".validate!" do
    context "with valid JSON" do
      it "does not raise error for valid JSON object" do
        json = '{"key": "value"}'
        expect { described_class.validate!(json) }.not_to raise_error
      end

      it "does not raise error for valid JSON array" do
        json = "[1, 2, 3]"
        expect { described_class.validate!(json) }.not_to raise_error
      end

      it "does not raise error for empty/nil input" do
        expect { described_class.validate!("") }.not_to raise_error
        expect { described_class.validate!(nil) }.not_to raise_error
      end
    end

    context "with malformed JSON" do
      it "raises ValidationError for missing closing brace" do
        json = '{"key": "value"'
        expect { described_class.validate!(json) }.to raise_error(
          Canon::ValidationError,
        ) do |error|
          expect(error.format).to eq(:json)
          expect(error.message).to match(/JSON Validation Error/)
        end
      end

      it "raises ValidationError for trailing comma" do
        json = '{"key": "value",}'
        expect { described_class.validate!(json) }.to raise_error(
          Canon::ValidationError,
        )
      end
    end
  end
end
