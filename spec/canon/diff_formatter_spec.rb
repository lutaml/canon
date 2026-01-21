# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::DiffFormatter do
  describe "initialization" do
    it "accepts use_color option" do
      formatter = described_class.new(use_color: true)
      expect(formatter).to be_a(described_class)
    end

    it "accepts mode option" do
      formatter = described_class.new(mode: :by_line)
      expect(formatter).to be_a(described_class)
    end

    it "accepts context_lines option" do
      formatter = described_class.new(context_lines: 5)
      expect(formatter).to be_a(described_class)
    end

    it "accepts diff_grouping_lines option" do
      formatter = described_class.new(diff_grouping_lines: 10)
      expect(formatter).to be_a(described_class)
    end

    it "accepts visualization_map option" do
      custom_map = { " " => "·" }
      formatter = described_class.new(visualization_map: custom_map)
      expect(formatter).to be_a(described_class)
    end

    it "accepts show_raw_inputs option" do
      formatter = described_class.new(show_raw_inputs: true)
      expect(formatter).to be_a(described_class)
    end

    it "accepts show_preprocessed_inputs option" do
      formatter = described_class.new(show_preprocessed_inputs: true)
      expect(formatter).to be_a(described_class)
    end

    it "accepts show_line_numbered_inputs option" do
      formatter = described_class.new(show_line_numbered_inputs: true)
      expect(formatter).to be_a(described_class)
    end
  end

  describe "#format" do
    context "with by_object mode" do
      let(:formatter) do
        described_class.new(use_color: false, mode: :by_object)
      end

      it "returns success message for no differences" do
        result = formatter.format([], :json)
        expect(result).to include("semantically equivalent")
      end

      it "delegates to by_object formatter for JSON differences" do
        differences = [
          {
            path: "name",
            value1: "old",
            value2: "new",
            diff_code: Canon::Comparison::UNEQUAL_PRIMITIVES,
          },
        ]

        result = formatter.format(differences, :json)
        expect(result).to include("name:")
        expect(result).to include('- "old"')
        expect(result).to include('+ "new"')
      end

      it "delegates to by_object formatter for YAML differences" do
        differences = [
          {
            path: "version",
            value1: 1,
            value2: 2,
            diff_code: Canon::Comparison::UNEQUAL_PRIMITIVES,
          },
        ]

        result = formatter.format(differences, :yaml)
        expect(result).to include("version:")
        expect(result).to include("- 1")
        expect(result).to include("+ 2")
      end
    end

    context "with by_line mode" do
      let(:formatter) { described_class.new(use_color: false, mode: :by_line) }

      it "delegates to by_line formatter for XML" do
        xml1 = "<doc><p>old text</p></doc>"
        xml2 = "<doc><p>new text</p></doc>"

        result = formatter.format([], :xml, doc1: xml1, doc2: xml2)
        expect(result).to include("Line-by-line diff (XML mode):")
      end

      it "delegates to by_line formatter for JSON" do
        json1 = '{"name": "old"}'
        json2 = '{"name": "new"}'

        result = formatter.format([], :json, doc1: json1, doc2: json2)
        expect(result).to include("Line-by-line diff (JSON mode):")
      end

      it "delegates to by_line formatter for YAML" do
        yaml1 = "name: old"
        yaml2 = "name: new"

        result = formatter.format([], :yaml, doc1: yaml1, doc2: yaml2)
        expect(result).to include("Line-by-line diff (YAML mode):")
      end
    end

    context "with comparison integration" do
      let(:formatter) do
        described_class.new(use_color: false, mode: :by_object)
      end

      it "works with Canon::Comparison output" do
        hash1 = {
          "name" => "App",
          "version" => "1.0.0",
        }

        hash2 = {
          "name" => "App",
          "version" => "2.0.0",
        }

        differences = Canon::Comparison.equivalent?(hash1, hash2,
                                                    { verbose: true })

        result = formatter.format(differences, :json)
        expect(result).to include("version:")
        expect(result).to include('- "1.0.0"')
        expect(result).to include('+ "2.0.0"')
      end
    end
  end

  describe "color management" do
    it "includes ANSI codes when use_color is true" do
      formatter = described_class.new(use_color: true, mode: :by_object)
      differences = [
        {
          path: "name",
          value1: "old",
          value2: "new",
          diff_code: Canon::Comparison::UNEQUAL_PRIMITIVES,
        },
      ]

      result = formatter.format(differences, :json)
      expect(result).to match(/\e\[/)
    end

    it "excludes ANSI codes when use_color is false" do
      formatter = described_class.new(use_color: false, mode: :by_object)
      differences = [
        {
          path: "name",
          value1: "old",
          value2: "new",
          diff_code: Canon::Comparison::UNEQUAL_PRIMITIVES,
        },
      ]

      result = formatter.format(differences, :json)
      expect(result).not_to match(/\e\[/)
    end
  end

  describe "input display methods" do
    let(:formatter) { described_class.new(use_color: false) }

    describe "#format_raw_inputs" do
      it "formats raw inputs with EXPECTED and RECEIVED labels" do
        raw1 = "<root>hello</root>"
        raw2 = "<root>goodbye</root>"

        result = formatter.send(:format_raw_inputs, raw1, raw2)

        expect(result).to include("=== ORIGINAL INPUTS (Raw) ===")
        expect(result).to include("EXPECTED:")
        expect(result).to include("RECEIVED:")
        expect(result).to include(raw1)
        expect(result).to include(raw2)
      end

      it "returns empty string for nil inputs" do
        result = formatter.send(:format_raw_inputs, nil, nil)
        expect(result).to eq("")
      end
    end

    describe "#format_preprocessed_inputs" do
      it "formats preprocessed inputs with preprocessing info" do
        preprocessed1 = "<root> hello </root>"
        preprocessed2 = "<root>hello</root>"

        result = formatter.send(:format_preprocessed_inputs, preprocessed1,
                                preprocessed2, :normalize)

        expect(result).to include("=== PREPROCESSED INPUTS (Compared) ===")
        expect(result).to include("Preprocessing: normalize")
        expect(result).to include("EXPECTED:")
        expect(result).to include("RECEIVED:")
        expect(result).to include(preprocessed1)
        expect(result).to include(preprocessed2)
      end

      it "formats preprocessed inputs without preprocessing info" do
        preprocessed1 = "<root>hello</root>"
        preprocessed2 = "<root>hello</root>"

        result = formatter.send(:format_preprocessed_inputs, preprocessed1,
                                preprocessed2, nil)

        expect(result).to include("=== PREPROCESSED INPUTS (Compared) ===")
        expect(result).not_to include("Preprocessing:")
        expect(result).to include("EXPECTED:")
        expect(result).to include("RECEIVED:")
      end

      it "returns empty string for nil inputs" do
        result = formatter.send(:format_preprocessed_inputs, nil, nil, nil)
        expect(result).to eq("")
      end
    end

    describe "#format_line_numbered_inputs" do
      it "formats inputs with line numbers (RSpec-style)" do
        raw1 = "<root>\n  hello\n</root>"
        raw2 = "<root>goodbye</root>"

        result = formatter.send(:format_line_numbered_inputs, raw1, raw2)

        # The header uses ==== (equals signs for borders)
        expect(result).to include("ORIGINAL INPUTS (with line numbers)")
        expect(result).to include("Expected:")
        expect(result).to include("Received:")
        expect(result).to include("    1 | <root>")
        expect(result).to include("    2 |   hello")
      end

      it "returns empty string for nil inputs" do
        result = formatter.send(:format_line_numbered_inputs, nil, nil)
        expect(result).to eq("")
      end
    end
  end
end
