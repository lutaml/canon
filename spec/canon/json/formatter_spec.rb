# frozen_string_literal: true

RSpec.describe Canon::Formatters::JsonFormatter do
  it "formats JSON with sorted keys" do
    input = <<~JSON
      {
        "z": 3,
        "a": 1,
        "nested": {
          "z": 3,
          "a": 1
        },
        "b": 2
      }
    JSON

    expected = <<~JSON
      {
        "a": 1,
        "b": 2,
        "nested": {
          "a": 1,
          "z": 3
        },
        "z": 3
      }
    JSON

    result = described_class.format(input)
    expect(result).to eq(expected.strip)
  end

  it "parses JSON into Ruby objects" do
    input = <<~JSON
      {
        "a": 1,
        "b": 2,
        "nested": {
          "a": 1,
          "z": 3
        }
      }
    JSON

    result = described_class.parse(input)

    expect(result).to be_a(Hash)
    expect(result["a"]).to eq(1)
    expect(result["b"]).to eq(2)
    expect(result["nested"]["a"]).to eq(1)
    expect(result["nested"]["z"]).to eq(3)
  end

  Dir.glob("spec/fixtures/json/*.raw.json").each do |f|
    c14n_filename = f.gsub(".raw.", ".c14n.")

    it "canonicalizes #{File.basename(f)}" do
      json_raw = File.read(f)
      json_c14n = File.read(c14n_filename)

      input = Canon.format(json_raw, :json)
      output = Canon.format(json_c14n, :json)

      expect(output).to be_json_equivalent_to(input)
    end
  end
end
