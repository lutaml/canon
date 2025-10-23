# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/canon/tree_diff"

RSpec.describe Canon::TreeDiff::Adapters::YAMLAdapter do
  let(:adapter) { described_class.new }

  describe "#to_tree" do
    context "with simple object" do
      let(:yaml) { { "name" => "John", "age" => 30 } }

      it "converts to TreeNode" do
        tree = adapter.to_tree(yaml)

        expect(tree).to be_a(Canon::TreeDiff::Core::TreeNode)
        expect(tree.label).to eq("object")
        expect(tree.children.size).to eq(2)

        name_node = tree.children.find { |c| c.attributes["key"] == "name" }
        expect(name_node.label).to eq("value")
        expect(name_node.value).to eq("John")
        expect(name_node.attributes["type"]).to eq("string")

        age_node = tree.children.find { |c| c.attributes["key"] == "age" }
        expect(age_node.label).to eq("value")
        expect(age_node.value).to eq("30")
        expect(age_node.attributes["type"]).to eq("integer")
      end
    end

    context "with nested object" do
      let(:yaml) do
        {
          "database" => {
            "host" => "localhost",
            "port" => 5432,
            "credentials" => {
              "username" => "admin",
              "password" => "secret"
            }
          }
        }
      end

      it "converts nested structure" do
        tree = adapter.to_tree(yaml)

        expect(tree.label).to eq("object")
        db_node = tree.children[0]
        expect(db_node.attributes["key"]).to eq("database")
        expect(db_node.label).to eq("object")

        creds_node = db_node.children.find do |c|
          c.attributes["key"] == "credentials"
        end
        expect(creds_node.label).to eq("object")

        username_node = creds_node.children.find do |c|
          c.attributes["key"] == "username"
        end
        expect(username_node.value).to eq("admin")
      end
    end

    context "with array" do
      let(:yaml) { ["red", "green", "blue"] }

      it "converts array to TreeNode" do
        tree = adapter.to_tree(yaml)

        expect(tree.label).to eq("array")
        expect(tree.children.size).to eq(3)

        tree.children.each_with_index do |child, index|
          expect(child.label).to eq("value")
          expect(child.attributes["key"]).to eq(index.to_s)
          expect(child.attributes["type"]).to eq("string")
        end
      end
    end

    context "with mixed types" do
      let(:yaml) { ["text", 42, 3.14, true, false, nil] }

      it "preserves type information" do
        tree = adapter.to_tree(yaml)

        expect(tree.children[0].attributes["type"]).to eq("string")
        expect(tree.children[0].value).to eq("text")

        expect(tree.children[1].attributes["type"]).to eq("integer")
        expect(tree.children[1].value).to eq("42")

        expect(tree.children[2].attributes["type"]).to eq("float")
        expect(tree.children[2].value).to eq("3.14")

        expect(tree.children[3].attributes["type"]).to eq("boolean")
        expect(tree.children[3].value).to eq("true")

        expect(tree.children[4].attributes["type"]).to eq("boolean")
        expect(tree.children[4].value).to eq("false")

        expect(tree.children[5].attributes["type"]).to eq("null")
        expect(tree.children[5].value).to eq("")
      end
    end

    context "with symbols" do
      let(:yaml) { { key: "value" } }

      it "handles symbols" do
        tree = adapter.to_tree(yaml)

        key_node = tree.children.find { |c| c.attributes["key"] == "key" }
        expect(key_node).not_to be_nil
        expect(key_node.value).to eq("value")
      end
    end

    context "with dates and times" do
      let(:date) { Date.new(2023, 12, 25) }
      let(:time) { Time.new(2023, 12, 25, 10, 30, 0) }
      let(:yaml) { { "date" => date, "time" => time } }

      it "handles date and time types" do
        tree = adapter.to_tree(yaml)

        date_node = tree.children.find { |c| c.attributes["key"] == "date" }
        expect(date_node.attributes["type"]).to eq("date")

        time_node = tree.children.find { |c| c.attributes["key"] == "time" }
        expect(time_node.attributes["type"]).to eq("time")
      end
    end

    context "with complex YAML structure" do
      let(:yaml) do
        {
          "services" => [
            {
              "name" => "web",
              "image" => "nginx:latest",
              "ports" => ["80:80", "443:443"],
              "environment" => {
                "NODE_ENV" => "production",
                "DEBUG" => false
              }
            },
            {
              "name" => "db",
              "image" => "postgres:14",
              "volumes" => ["/var/lib/postgresql/data"]
            }
          ]
        }
      end

      it "converts complex nested structure" do
        tree = adapter.to_tree(yaml)

        services_node = tree.children.find do |c|
          c.attributes["key"] == "services"
        end
        expect(services_node.label).to eq("array")
        expect(services_node.children.size).to eq(2)

        web_service = services_node.children[0]
        expect(web_service.label).to eq("object")

        ports_node = web_service.children.find do |c|
          c.attributes["key"] == "ports"
        end
        expect(ports_node.label).to eq("array")
        expect(ports_node.children.size).to eq(2)
      end
    end
  end

  describe "#from_tree" do
    context "with simple object TreeNode" do
      let(:tree_node) do
        root = Canon::TreeDiff::Core::TreeNode.new(label: "object")
        name_node = Canon::TreeDiff::Core::TreeNode.new(
          label: "value",
          value: "Alice",
          attributes: { "key" => "name", "type" => "string" }
        )
        age_node = Canon::TreeDiff::Core::TreeNode.new(
          label: "value",
          value: "25",
          attributes: { "key" => "age", "type" => "integer" }
        )
        root.add_child(name_node)
        root.add_child(age_node)
        root
      end

      it "converts back to Hash" do
        result = adapter.from_tree(tree_node)

        expect(result).to eq({
          "name" => "Alice",
          "age" => 25
        })
      end
    end

    context "with array TreeNode" do
      let(:tree_node) do
        root = Canon::TreeDiff::Core::TreeNode.new(label: "array")
        ["a", "b", "c"].each_with_index do |val, idx|
          node = Canon::TreeDiff::Core::TreeNode.new(
            label: "value",
            value: val,
            attributes: { "key" => idx.to_s, "type" => "string" }
          )
          root.add_child(node)
        end
        root
      end

      it "converts back to Array" do
        result = adapter.from_tree(tree_node)

        expect(result).to eq(["a", "b", "c"])
      end
    end

    context "with mixed types TreeNode" do
      let(:tree_node) do
        root = Canon::TreeDiff::Core::TreeNode.new(label: "array")

        string_node = Canon::TreeDiff::Core::TreeNode.new(
          label: "value",
          value: "text",
          attributes: { "key" => "0", "type" => "string" }
        )
        int_node = Canon::TreeDiff::Core::TreeNode.new(
          label: "value",
          value: "99",
          attributes: { "key" => "1", "type" => "integer" }
        )
        float_node = Canon::TreeDiff::Core::TreeNode.new(
          label: "value",
          value: "2.71",
          attributes: { "key" => "2", "type" => "float" }
        )
        bool_true = Canon::TreeDiff::Core::TreeNode.new(
          label: "value",
          value: "true",
          attributes: { "key" => "3", "type" => "boolean" }
        )
        bool_false = Canon::TreeDiff::Core::TreeNode.new(
          label: "value",
          value: "false",
          attributes: { "key" => "4", "type" => "boolean" }
        )
        null_node = Canon::TreeDiff::Core::TreeNode.new(
          label: "value",
          value: "",
          attributes: { "key" => "5", "type" => "null" }
        )

        root.add_child(string_node)
        root.add_child(int_node)
        root.add_child(float_node)
        root.add_child(bool_true)
        root.add_child(bool_false)
        root.add_child(null_node)
        root
      end

      it "restores correct types" do
        result = adapter.from_tree(tree_node)

        expect(result).to eq(["text", 99, 2.71, true, false, nil])
      end
    end

    context "with symbol type" do
      let(:tree_node) do
        root = Canon::TreeDiff::Core::TreeNode.new(label: "object")
        sym_node = Canon::TreeDiff::Core::TreeNode.new(
          label: "value",
          value: "test_key",
          attributes: { "key" => "symbol", "type" => "symbol" }
        )
        root.add_child(sym_node)
        root
      end

      it "converts to symbol" do
        result = adapter.from_tree(tree_node)

        expect(result["symbol"]).to eq(:test_key)
      end
    end
  end

  describe "round-trip conversion" do
    let(:yaml_data) do
      {
        "application" => "MyApp",
        "version" => "1.2.3",
        "server" => {
          "host" => "0.0.0.0",
          "port" => 8080,
          "ssl" => true
        },
        "database" => {
          "adapter" => "postgresql",
          "pool" => 5,
          "timeout" => 5000
        },
        "features" => ["auth", "api", "admin"],
        "metadata" => {
          "created_at" => Date.new(2023, 1, 1),
          "tags" => ["production", "v1"]
        }
      }
    end

    it "maintains structure and types through round-trip" do
      tree = adapter.to_tree(yaml_data)
      result = adapter.from_tree(tree)

      # Compare basic structure
      expect(result["application"]).to eq(yaml_data["application"])
      expect(result["version"]).to eq(yaml_data["version"])

      # Compare nested objects
      expect(result["server"]).to be_a(Hash)
      expect(result["server"]["host"]).to eq("0.0.0.0")
      expect(result["server"]["port"]).to eq(8080)
      expect(result["server"]["ssl"]).to be(true)

      # Compare arrays
      expect(result["features"]).to eq(["auth", "api", "admin"])

      # Compare types
      expect(result["server"]["port"]).to be_an(Integer)
      expect(result["database"]["timeout"]).to be_an(Integer)
      expect(result["server"]["ssl"]).to be(true).or be(false)
    end
  end
end
