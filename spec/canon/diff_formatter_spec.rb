# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::DiffFormatter do
  let(:formatter) { described_class.new(use_color: false, mode: :by_object) }

  describe "#format" do
    context "with no differences" do
      it "returns success message" do
        result = formatter.format([], :json)
        expect(result).to include("semantically equivalent")
      end
    end

    context "with JSON/YAML differences" do
      describe "primitive value changes" do
        it "shows old and new values for string changes" do
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

        it "shows old and new values for number changes" do
          differences = [
            {
              path: "version",
              value1: 1,
              value2: 2,
              diff_code: Canon::Comparison::UNEQUAL_PRIMITIVES,
            },
          ]

          result = formatter.format(differences, :json)
          expect(result).to include("version:")
          expect(result).to include("- 1")
          expect(result).to include("+ 2")
        end

        it "shows old and new values for boolean changes" do
          differences = [
            {
              path: "enabled",
              value1: true,
              value2: false,
              diff_code: Canon::Comparison::UNEQUAL_TYPES,
            },
          ]

          result = formatter.format(differences, :json)
          expect(result).to include("enabled:")
          expect(result).to include("- true")
          expect(result).to include("+ false")
        end
      end

      describe "array differences" do
        it "shows element-by-element comparison with indices" do
          differences = [
            {
              path: "items",
              value1: ["a", "b"],
              value2: ["a", "b", "c"],
              diff_code: Canon::Comparison::UNEQUAL_ARRAY_LENGTHS,
            },
          ]

          result = formatter.format(differences, :json)
          expect(result).to include("items:")
          expect(result).to include('[2] + "c"')
        end

        it "shows changed array elements" do
          differences = [
            {
              path: "tags",
              value1: ["foo", "bar"],
              value2: ["foo", "baz"],
              diff_code: Canon::Comparison::UNEQUAL_ARRAY_ELEMENTS,
            },
          ]

          result = formatter.format(differences, :json)
          expect(result).to include("tags:")
          expect(result).to include('[1] - "bar"')
          expect(result).to include('[1] + "baz"')
        end
      end

      describe "hash additions and removals" do
        it "shows nested structure when hash is added" do
          added_hash = {
            "host" => "localhost",
            "port" => 5432,
          }

          differences = [
            {
              path: "database",
              value1: nil,
              value2: added_hash,
              diff_code: Canon::Comparison::MISSING_HASH_KEY,
            },
          ]

          result = formatter.format(differences, :json)
          expect(result).to include("database:")
          expect(result).to include('+ host: "localhost"')
          expect(result).to include("+ port: 5432")
        end

        it "shows deeply nested structure when hash is added" do
          nested_hash = {
            "credentials" => {
              "username" => "admin",
              "password" => "secret",
            },
            "pool" => {
              "min" => 5,
              "max" => 20,
            },
          }

          differences = [
            {
              path: "database",
              value1: nil,
              value2: nested_hash,
              diff_code: Canon::Comparison::MISSING_HASH_KEY,
            },
          ]

          result = formatter.format(differences, :json)
          expect(result).to include("database:")
          expect(result).to include("+ credentials:")
          expect(result).to include('+ username: "admin"')
          expect(result).to include('+ password: "secret"')
          expect(result).to include("+ pool:")
          expect(result).to include("+ min: 5")
          expect(result).to include("+ max: 20")
        end

        it "shows nested structure when hash is removed" do
          removed_hash = {
            "host" => "localhost",
            "port" => 5432,
          }

          differences = [
            {
              path: "database",
              value1: removed_hash,
              value2: nil,
              diff_code: Canon::Comparison::MISSING_HASH_KEY,
            },
          ]

          result = formatter.format(differences, :json)
          expect(result).to include("database:")
          expect(result).to include('- host: "localhost"')
          expect(result).to include("- port: 5432")
        end
      end

      describe "multi-level nested structures" do
        it "captures all differences in deeply nested structures" do
          differences = [
            {
              path: "app.settings.database.host",
              value1: "localhost",
              value2: "db.example.com",
              diff_code: Canon::Comparison::UNEQUAL_PRIMITIVES,
            },
            {
              path: "app.settings.database.pool",
              value1: nil,
              value2: { "min" => 5, "max" => 20 },
              diff_code: Canon::Comparison::MISSING_HASH_KEY,
            },
            {
              path: "app.version",
              value1: "1.0.0",
              value2: "2.0.0",
              diff_code: Canon::Comparison::UNEQUAL_PRIMITIVES,
            },
          ]

          result = formatter.format(differences, :json)

          # Check all differences are present
          expect(result).to include("app.settings.database.host:")
          expect(result).to include('- "localhost"')
          expect(result).to include('+ "db.example.com"')

          expect(result).to include("app.settings.database.pool:")
          expect(result).to include("+ min: 5")
          expect(result).to include("+ max: 20")

          expect(result).to include("app.version:")
          expect(result).to include('- "1.0.0"')
          expect(result).to include('+ "2.0.0"')
        end
      end

      describe "tree structure rendering" do
        it "uses proper box-drawing characters" do
          differences = [
            {
              path: "settings.debug",
              value1: true,
              value2: false,
              diff_code: Canon::Comparison::UNEQUAL_PRIMITIVES,
            },
          ]

          result = formatter.format(differences, :json)
          # Check for tree connectors (├──, └──)
          expect(result).to match(/[├└]──/)
        end

        it "shows proper indentation for nested paths" do
          differences = [
            {
              path: "app.settings.database.host",
              value1: "localhost",
              value2: "remote",
              diff_code: Canon::Comparison::UNEQUAL_PRIMITIVES,
            },
          ]

          result = formatter.format(differences, :json)
          # Check that path hierarchy is rendered
          expect(result).to include("app:")
          expect(result).to include("settings:")
          expect(result).to include("database:")
          expect(result).to include("app.settings.database.host:")
        end
      end
    end

    context "with comparison integration" do
      it "captures all differences in a hash with both missing keys and value changes" do
        hash1 = {
          "name" => "App",
          "version" => "1.0.0",
          "debug" => true,
        }

        hash2 = {
          "name" => "App",
          "version" => "2.0.0",
          "features" => ["logging"],
        }

        differences = Canon::Comparison.equivalent?(hash1, hash2,
                                                    { verbose: true })

        result = formatter.format(differences, :json)

        # Should show both the changed version AND the missing/added keys
        expect(result).to include("version:")
        expect(result).to include('- "1.0.0"')
        expect(result).to include('+ "2.0.0"')

        expect(result).to include("debug:")
        expect(result).to include("- true")

        expect(result).to include("features:")
        expect(result).to include('["logging"]')
      end

      it "captures all differences in nested structures" do
        obj1 = {
          "app" => {
            "settings" => {
              "database" => {
                "host" => "localhost",
                "port" => 5432,
              },
              "features" => {
                "auth" => true,
              },
            },
            "version" => "1.0.0",
          },
        }

        obj2 = {
          "app" => {
            "settings" => {
              "database" => {
                "host" => "remote",
                "port" => 5432,
              },
              "features" => {
                "auth" => true,
                "logging" => true,
              },
            },
            "version" => "2.0.0",
          },
        }

        differences = Canon::Comparison.equivalent?(obj1, obj2,
                                                    { verbose: true })

        result = formatter.format(differences, :json)

        # All differences should be captured
        expect(result).to include("database.host:")
        expect(result).to include("version:")
        expect(result).to include("logging:")
      end
    end
  end

  describe "colorization" do
    let(:color_formatter) do
      described_class.new(use_color: true, mode: :by_object)
    end
    let(:no_color_formatter) do
      described_class.new(use_color: false, mode: :by_object)
    end

    it "includes ANSI codes when color is enabled" do
      differences = [
        {
          path: "name",
          value1: "old",
          value2: "new",
          diff_code: Canon::Comparison::UNEQUAL_PRIMITIVES,
        },
      ]

      result = color_formatter.format(differences, :json)
      # Check for ANSI escape sequences (color codes)
      expect(result).to match(/\e\[/)
    end

    it "excludes ANSI codes when color is disabled" do
      differences = [
        {
          path: "name",
          value1: "old",
          value2: "new",
          diff_code: Canon::Comparison::UNEQUAL_PRIMITIVES,
        },
      ]

      result = no_color_formatter.format(differences, :json)
      # Should not contain ANSI escape sequences
      expect(result).not_to match(/\e\[/)
    end
  end
end
