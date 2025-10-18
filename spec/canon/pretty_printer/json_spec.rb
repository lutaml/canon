# frozen_string_literal: true

require "spec_helper"
require "canon/pretty_printer/json"

RSpec.describe Canon::PrettyPrinter::Json do
  describe "#format" do
    let(:json_content) { '{"name":"test","value":123}' }

    context "with default options" do
      subject { described_class.new }

      it "formats JSON with 2-space indentation" do
        result = subject.format(json_content)
        expect(result).to include("  \"name\":")
      end

      it "preserves all data" do
        result = subject.format(json_content)
        parsed = JSON.parse(result)
        expect(parsed["name"]).to eq("test")
        expect(parsed["value"]).to eq(123)
      end
    end

    context "with custom indent" do
      subject { described_class.new(indent: 4) }

      it "formats JSON with 4-space indentation" do
        result = subject.format(json_content)
        expect(result).to include("    \"name\":")
      end
    end

    context "with tab indentation" do
      subject { described_class.new(indent_type: "tab") }

      it "formats JSON with tab indentation" do
        result = subject.format(json_content)
        expect(result).to include("\t\"name\":")
      end
    end

    context "with nested JSON" do
      let(:nested_json) { '{"outer":{"inner":{"deep":"value"}}}' }

      subject { described_class.new(indent: 2) }

      it "formats nested objects correctly" do
        result = subject.format(nested_json)
        expect(result).to include("  \"outer\":")
        expect(result).to include("    \"inner\":")
        expect(result).to include("      \"deep\":")
      end
    end

    context "with arrays" do
      let(:array_json) { '{"items":[1,2,3]}' }

      subject { described_class.new(indent: 2) }

      it "formats arrays correctly" do
        result = subject.format(array_json)
        expect(result).to include("  \"items\": [")
        parsed = JSON.parse(result)
        expect(parsed["items"]).to eq([1, 2, 3])
      end
    end
  end
end
