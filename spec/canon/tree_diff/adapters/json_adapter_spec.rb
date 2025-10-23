# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/canon/tree_diff"

RSpec.describe Canon::TreeDiff::Adapters::JSONAdapter do
  let(:adapter) { described_class.new }

  describe "#to_tree" do
    context "with simple object" do
      let(:json) { { "name" => "John", "age" => 30 } }

      it "converts to TreeNode" do
        tree = adapter.to_tree(json)

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
      let(:json) do
        {
          "person" => {
            "name" => "Jane",
            "address" => {
              "city" => "NYC",
              "zip" => "10001"
            }
          }
        }
      end

      it "converts nested structure" do
        tree = adapter.to_tree(json)

        expect(tree.label).to eq("object")
        person_node = tree.children[0]
        expect(person_node.attributes["key"]).to eq("person")
        expect(person_node.label).to eq("object")

        address_node = person_node.children.find do |c|
          c.attributes["key"] == "address"
        end
        expect(address_node.label).to eq("object")

        city_node = address_node.children.find do |c|
          c.attributes["key"] == "city"
        end
        expect(city_node.value).to eq("NYC")
      end
    end

    context "with array" do
      let(:json) { [1, 2, 3] }

      it "converts array to TreeNode" do
        tree = adapter.to_tree(json)

        expect(tree.label).to eq("array")
        expect(tree.children.size).to eq(3)

        tree.children.each_with_index do |child, index|
          expect(child.label).to eq("value")
          expect(child.attributes["key"]).to eq(index.to_s)
          expect(child.value).to eq((index + 1).to_s)
          expect(child.attributes["type"]).to eq("integer")
        end
      end
    end

    context "with mixed array" do
      let(:json) { ["string", 42, true, nil, 3.14] }

      it "preserves type information" do
        tree = adapter.to_tree(json)

        expect(tree.children[0].attributes["type"]).to eq("string")
        expect(tree.children[0].value).to eq("string")

        expect(tree.children[1].attributes["type"]).to eq("integer")
        expect(tree.children[1].value).to eq("42")

        expect(tree.children[2].attributes["type"]).to eq("boolean")
        expect(tree.children[2].value).to eq("true")

        expect(tree.children[3].attributes["type"]).to eq("null")
        expect(tree.children[3].value).to eq("")

        expect(tree.children[4].attributes["type"]).to eq("float")
        expect(tree.children[4].value).to eq("3.14")
      end
    end

    context "with complex structure" do
      let(:json) do
        {
          "users" => [
            { "id" => 1, "name" => "Alice" },
            { "id" => 2, "name" => "Bob" }
          ],
          "count" => 2
        }
      end

      it "converts complex nested structure" do
        tree = adapter.to_tree(json)

        users_node = tree.children.find { |c| c.attributes["key"] == "users" }
        expect(users_node.label).to eq("array")
        expect(users_node.children.size).to eq(2)

        first_user = users_node.children[0]
        expect(first_user.label).to eq("object")

        id_node = first_user.children.find { |c| c.attributes["key"] == "id" }
        expect(id_node.value).to eq("1")
      end
    end
  end

  describe "#from_tree" do
    context "with simple object TreeNode" do
      let(:tree_node) do
        root = Canon::TreeDiff::Core::TreeNode.new(label: "object")
        name_node = Canon::TreeDiff::Core::TreeNode.new(
          label: "value",
          value: "John",
          attributes: { "key" => "name", "type" => "string" }
        )
        age_node = Canon::TreeDiff::Core::TreeNode.new(
          label: "value",
          value: "30",
          attributes: { "key" => "age", "type" => "integer" }
        )
        root.add_child(name_node)
        root.add_child(age_node)
        root
      end

      it "converts back to Hash" do
        result = adapter.from_tree(tree_node)

        expect(result).to eq({
          "name" => "John",
          "age" => 30
        })
      end
    end

    context "with array TreeNode" do
      let(:tree_node) do
        root = Canon::TreeDiff::Core::TreeNode.new(label: "array")
        [1, 2, 3].each_with_index do |val, idx|
          node = Canon::TreeDiff::Core::TreeNode.new(
            label: "value",
            value: val.to_s,
            attributes: { "key" => idx.to_s, "type" => "integer" }
          )
          root.add_child(node)
        end
        root
      end

      it "converts back to Array" do
        result = adapter.from_tree(tree_node)

        expect(result).to eq([1, 2, 3])
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
          value: "42",
          attributes: { "key" => "1", "type" => "integer" }
        )
        float_node = Canon::TreeDiff::Core::TreeNode.new(
          label: "value",
          value: "3.14",
          attributes: { "key" => "2", "type" => "float" }
        )
        bool_node = Canon::TreeDiff::Core::TreeNode.new(
          label: "value",
          value: "true",
          attributes: { "key" => "3", "type" => "boolean" }
        )
        null_node = Canon::TreeDiff::Core::TreeNode.new(
          label: "value",
          value: "",
          attributes: { "key" => "4", "type" => "null" }
        )

        root.add_child(string_node)
        root.add_child(int_node)
        root.add_child(float_node)
        root.add_child(bool_node)
        root.add_child(null_node)
        root
      end

      it "restores correct types" do
        result = adapter.from_tree(tree_node)

        expect(result).to eq(["text", 42, 3.14, true, nil])
      end
    end
  end

  describe "round-trip conversion" do
    let(:json_data) do
      {
        "company" => "ACME Corp",
        "employees" => [
          {
            "id" => 1,
            "name" => "Alice",
            "active" => true,
            "salary" => 75000.50
          },
          {
            "id" => 2,
            "name" => "Bob",
            "active" => false,
            "salary" => 65000.0
          }
        ],
        "founded" => 2010,
        "public" => true,
        "headquarters" => {
          "city" => "San Francisco",
          "state" => "CA",
          "zip" => "94105"
        }
      }
    end

    it "maintains structure and types through round-trip" do
      tree = adapter.to_tree(json_data)
      result = adapter.from_tree(tree)

      expect(result).to eq(json_data)

      # Verify types are preserved
      expect(result["company"]).to be_a(String)
      expect(result["founded"]).to be_a(Integer)
      expect(result["public"]).to be(true)
      expect(result["employees"]).to be_an(Array)
      expect(result["employees"][0]["salary"]).to be_a(Float)
      expect(result["headquarters"]).to be_a(Hash)
    end
  end
end
