# frozen_string_literal: true

RSpec.describe Canon::Formatters::YamlFormatter do
  it "formats YAML with sorted keys" do
    input = <<~YAML
      ---
      z: 3
      a: 1
      nested:
        z: 3
        a: 1
      b: 2
    YAML

    expected = <<~YAML
      ---
      a: 1
      b: 2
      nested:
        a: 1
        z: 3
      z: 3
    YAML

    result = described_class.format(input)
    expect(result).to eq(expected)
  end

  it "parses YAML into Ruby objects" do
    input = <<~YAML
      ---
      a: 1
      b: 2
      nested:
        a: 1
        z: 3
    YAML

    result = described_class.parse(input)

    expect(result).to be_a(Hash)
    expect(result["a"]).to eq(1)
    expect(result["b"]).to eq(2)
    expect(result["nested"]["a"]).to eq(1)
    expect(result["nested"]["z"]).to eq(3)
  end

  Dir.glob("spec/fixtures/yaml/*.raw.yaml").each do |f|
    c14n_filename = f.gsub(".raw.", ".c14n.")

    it "canonicalizes #{File.basename(f)}" do
      yaml_raw = File.read(f)
      yaml_c14n = File.read(c14n_filename)

      input = Canon.format(yaml_raw, :yaml)
      output = Canon.format(yaml_c14n, :yaml)

      expect(output).to be_yaml_equivalent_to(input)
    end
  end
end
