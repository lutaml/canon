# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Canon::DiffFormatter, "character map customization" do
  describe ".load_custom_character_map" do
    it "loads character map from custom YAML file" do
      yaml_content = <<~YAML
        characters:
          - unicode: "2005"
            visualization: "⏓"
            category: whitespace
            name: "Four-Per-Em Space"

          - character: " "
            visualization: "·"
            category: whitespace
            name: "Space"
      YAML

      Tempfile.create(["custom_map", ".yml"]) do |file|
        file.write(yaml_content)
        file.flush

        map = described_class.load_custom_character_map(file.path)

        expect(map["\u2005"]).to eq("⏓")
        expect(map[" "]).to eq("·")
        expect(map.size).to eq(2)
      end
    end

    it "handles unicode code points correctly" do
      yaml_content = <<~YAML
        characters:
          - unicode: "00A0"
            visualization: "␣"
            category: whitespace
            name: "No-Break Space"
      YAML

      Tempfile.create(["custom_map", ".yml"]) do |file|
        file.write(yaml_content)
        file.flush

        map = described_class.load_custom_character_map(file.path)

        expect(map["\u00A0"]).to eq("␣")
      end
    end
  end

  describe ".build_character_definition" do
    context "with unicode code point" do
      it "builds character definition from unicode" do
        definition = {
          unicode: "2005",
          visualization: "⏓",
          category: "whitespace",
          name: "Four-Per-Em Space",
        }

        result = described_class.build_character_definition(definition)

        expect(result["\u2005"]).to eq("⏓")
      end
    end

    context "with character field" do
      it "builds character definition from character" do
        definition = {
          character: " ",
          visualization: "·",
          category: "whitespace",
          name: "Space",
        }

        result = described_class.build_character_definition(definition)

        expect(result[" "]).to eq("·")
      end
    end

    context "with invalid input" do
      it "raises error when neither character nor unicode is provided" do
        definition = {
          visualization: "·",
          category: "whitespace",
          name: "Space",
        }

        expect do
          described_class.build_character_definition(definition)
        end.to raise_error(ArgumentError, /must include :character or :unicode/)
      end

      it "raises error when visualization is missing" do
        definition = {
          character: " ",
          category: "whitespace",
          name: "Space",
        }

        expect do
          described_class.build_character_definition(definition)
        end.to raise_error(ArgumentError, /must include :visualization/)
      end

      it "raises error when category is missing" do
        definition = {
          character: " ",
          visualization: "·",
          name: "Space",
        }

        expect do
          described_class.build_character_definition(definition)
        end.to raise_error(ArgumentError, /must include :category/)
      end

      it "raises error when name is missing" do
        definition = {
          character: " ",
          visualization: "·",
          category: "whitespace",
        }

        expect do
          described_class.build_character_definition(definition)
        end.to raise_error(ArgumentError, /must include :name/)
      end
    end
  end

  describe "#initialize with character map customization" do
    let(:doc1) { "Hello\u2005World" }
    let(:doc2) { "Hello World" }

    context "with visualization_map parameter (highest priority)" do
      it "uses provided visualization map completely" do
        custom_map = { "\u2005" => "★" }
        formatter = described_class.new(
          mode: :by_line,
          visualization_map: custom_map
        )

        output = formatter.format([], :simple, doc1: doc1, doc2: doc2)

        expect(output).to include("★")
        expect(output).not_to include("⏓")
      end

      it "ignores other customization parameters when visualization_map is provided" do
        custom_map = { "\u2005" => "★" }
        custom_definitions = [
          { unicode: "2005", visualization: "☆" },
        ]

        formatter = described_class.new(
          mode: :by_line,
          visualization_map: custom_map,
          character_definitions: custom_definitions
        )

        output = formatter.format([], :simple, doc1: doc1, doc2: doc2)

        expect(output).to include("★")
        expect(output).not_to include("☆")
      end
    end

    context "with character_map_file parameter" do
      it "loads and merges custom character map from file" do
        yaml_content = <<~YAML
          characters:
            - unicode: "2005"
              visualization: "✦"
              category: whitespace
              name: "Four-Per-Em Space"
        YAML

        Tempfile.create(["custom_map", ".yml"]) do |file|
          file.write(yaml_content)
          file.flush

          formatter = described_class.new(
            mode: :by_line,
            character_map_file: file.path
          )

          output = formatter.format([], :simple, doc1: doc1, doc2: doc2)

          expect(output).to include("✦")
          expect(output).not_to include("⏓")
        end
      end

      it "preserves default mappings for non-overridden characters" do
        yaml_content = <<~YAML
          characters:
            - unicode: "2005"
              visualization: "✦"
        YAML

        doc_with_tab = "Hello\tWorld\u2005Test"
        doc_plain = "Hello World Test"

        Tempfile.create(["custom_map", ".yml"]) do |file|
          file.write(yaml_content)
          file.flush

          formatter = described_class.new(
            mode: :by_line,
            character_map_file: file.path
          )

          output = formatter.format([], :simple,
                                    doc1: doc_with_tab, doc2: doc_plain)

          # Custom mapping for U+2005
          expect(output).to include("✦")
          # Default mapping for tab should still work
          expect(output).to include("⇥")
        end
      end
    end

    context "with character_definitions parameter" do
      it "applies individual character definitions" do
        custom_definitions = [
          {
            unicode: "2005",
            visualization: "◆",
            category: "whitespace",
            name: "Four-Per-Em Space",
          },
        ]

        formatter = described_class.new(
          mode: :by_line,
          character_definitions: custom_definitions
        )

        output = formatter.format([], :simple, doc1: doc1, doc2: doc2)

        expect(output).to include("◆")
        expect(output).not_to include("⏓")
      end

      it "applies multiple character definitions" do
        doc_multi = "Hello\u2005World\tTest"
        doc_plain = "Hello World Test"

        custom_definitions = [
          {
            unicode: "2005",
            visualization: "◆",
            category: "whitespace",
            name: "Four-Per-Em Space",
          },
          {
            character: "\t",
            visualization: "→→",
            category: "whitespace",
            name: "Tab",
          },
        ]

        formatter = described_class.new(
          mode: :by_line,
          character_definitions: custom_definitions
        )

        output = formatter.format([], :simple,
                                  doc1: doc_multi, doc2: doc_plain)

        expect(output).to include("◆")
        expect(output).to include("→→")
      end

      it "preserves default mappings for non-overridden characters" do
        doc_with_nbsp = "Hello\u00A0World\u2005Test"
        doc_plain = "Hello World Test"

        custom_definitions = [
          {
            unicode: "2005",
            visualization: "◆",
            category: "whitespace",
            name: "Four-Per-Em Space",
          },
        ]

        formatter = described_class.new(
          mode: :by_line,
          character_definitions: custom_definitions
        )

        output = formatter.format([], :simple,
                                  doc1: doc_with_nbsp, doc2: doc_plain)

        # Custom mapping for U+2005
        expect(output).to include("◆")
        # Default mapping for nbsp should still work
        expect(output).to include("␣")
      end
    end

    context "with combined customizations" do
      it "applies character_map_file then character_definitions (in order)" do
        yaml_content = <<~YAML
          characters:
            - unicode: "2005"
              visualization: "✦"
            - character: "\t"
              visualization: "TAB"
        YAML

        doc_multi = "Hello\u2005World\tTest"
        doc_plain = "Hello World Test"

        Tempfile.create(["custom_map", ".yml"]) do |file|
          file.write(yaml_content)
          file.flush

          custom_definitions = [
            {
              unicode: "2005",
              visualization: "◆",
              category: "whitespace",
              name: "Four-Per-Em Space",
            }, # Overrides file definition
          ]

          formatter = described_class.new(
            mode: :by_line,
            character_map_file: file.path,
            character_definitions: custom_definitions
          )

          output = formatter.format([], :simple,
                                    doc1: doc_multi, doc2: doc_plain)

          # character_definitions takes precedence over character_map_file
          expect(output).to include("◆")
          expect(output).not_to include("✦")
          # But file definition for tab still applies
          expect(output).to include("TAB")
        end
      end
    end

    context "with no customization" do
      it "uses default character map" do
        formatter = described_class.new(mode: :by_line)

        output = formatter.format([], :simple, doc1: doc1, doc2: doc2)

        # Should use default mapping
        expect(output).to include("⏓")
      end
    end
  end

  describe "integration with formatters" do
    let(:doc1) { "Hello\u2005World" }
    let(:doc2) { "Hello World" }

    it "works with XML formatter" do
      custom_definitions = [
        {
          unicode: "2005",
          visualization: "★",
          category: "whitespace",
          name: "Four-Per-Em Space",
        },
      ]

      formatter = described_class.new(
        mode: :by_line,
        character_definitions: custom_definitions
      )

      output = formatter.format([], :xml, doc1: doc1, doc2: doc2)

      expect(output).to include("★")
    end

    it "works with JSON formatter" do
      custom_definitions = [
        {
          unicode: "2005",
          visualization: "★",
          category: "whitespace",
          name: "Four-Per-Em Space",
        },
      ]

      formatter = described_class.new(
        mode: :by_line,
        character_definitions: custom_definitions
      )

      output = formatter.format([], :json, doc1: doc1, doc2: doc2)

      expect(output).to include("★")
    end

    it "works with YAML formatter" do
      custom_definitions = [
        {
          unicode: "2005",
          visualization: "★",
          category: "whitespace",
          name: "Four-Per-Em Space",
        },
      ]

      formatter = described_class.new(
        mode: :by_line,
        character_definitions: custom_definitions
      )

      output = formatter.format([], :yaml, doc1: doc1, doc2: doc2)

      expect(output).to include("★")
    end
  end
end
