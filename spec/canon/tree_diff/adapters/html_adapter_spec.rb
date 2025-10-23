# frozen_string_literal: true

require "spec_helper"
require "nokogiri"
require_relative "../../../../lib/canon/tree_diff"

RSpec.describe Canon::TreeDiff::Adapters::HTMLAdapter do
  let(:adapter) { described_class.new }

  describe "#to_tree" do
    context "with simple HTML element" do
      let(:html) { Nokogiri::HTML("<p>text content</p>") }

      it "converts to TreeNode" do
        tree = adapter.to_tree(html)

        expect(tree).to be_a(Canon::TreeDiff::Core::TreeNode)
        expect(tree.label).to eq("html")

        body = tree.children.find { |c| c.label == "body" }
        expect(body).not_to be_nil

        p_tag = body.children.find { |c| c.label == "p" }
        expect(p_tag.value).to eq("text content")
      end
    end

    context "with nested HTML structure" do
      let(:html) do
        Nokogiri::HTML(<<~HTML)
          <html>
            <body>
              <div id="main">
                <h1>Title</h1>
                <p>Paragraph</p>
              </div>
            </body>
          </html>
        HTML
      end

      it "converts nested structure" do
        tree = adapter.to_tree(html)

        expect(tree.label).to eq("html")

        body = tree.children.find { |c| c.label == "body" }
        div = body.children.find { |c| c.label == "div" }
        expect(div.attributes["id"]).to eq("main")

        h1 = div.children.find { |c| c.label == "h1" }
        expect(h1.value).to eq("Title")

        p_tag = div.children.find { |c| c.label == "p" }
        expect(p_tag.value).to eq("Paragraph")
      end
    end

    context "with attributes" do
      let(:html) do
        Nokogiri::HTML('<a href="https://example.com" class="link">Click</a>')
      end

      it "preserves attributes" do
        tree = adapter.to_tree(html)

        body = tree.children.find { |c| c.label == "body" }
        a_tag = body.children.find { |c| c.label == "a" }

        expect(a_tag.attributes).to include(
          "href" => "https://example.com",
          "class" => "link"
        )
        expect(a_tag.value).to eq("Click")
      end
    end

    context "with list structure" do
      let(:html) do
        Nokogiri::HTML(<<~HTML)
          <ul>
            <li>Item 1</li>
            <li>Item 2</li>
            <li>Item 3</li>
          </ul>
        HTML
      end

      it "converts list to tree" do
        tree = adapter.to_tree(html)

        body = tree.children.find { |c| c.label == "body" }
        ul = body.children.find { |c| c.label == "ul" }
        expect(ul.children.size).to eq(3)

        ul.children.each_with_index do |li, idx|
          expect(li.label).to eq("li")
          expect(li.value).to eq("Item #{idx + 1}")
        end
      end
    end

    context "with form elements" do
      let(:html) do
        Nokogiri::HTML(<<~HTML)
          <form>
            <input type="text" name="username" />
            <input type="password" name="password" />
            <button type="submit">Login</button>
          </form>
        HTML
      end

      it "converts form structure" do
        tree = adapter.to_tree(html)

        body = tree.children.find { |c| c.label == "body" }
        form = body.children.find { |c| c.label == "form" }
        expect(form.children.size).to eq(3)

        input1 = form.children[0]
        expect(input1.label).to eq("input")
        expect(input1.attributes["type"]).to eq("text")
        expect(input1.attributes["name"]).to eq("username")

        button = form.children[2]
        expect(button.label).to eq("button")
        expect(button.value).to eq("Login")
      end
    end

    context "with empty element" do
      let(:html) { Nokogiri::HTML("<div></div>") }

      it "converts to TreeNode with nil value" do
        tree = adapter.to_tree(html)

        body = tree.children.find { |c| c.label == "body" }
        div = body.children.find { |c| c.label == "div" }
        expect(div.value).to be_nil
        expect(div.children).to be_empty
      end
    end
  end

  describe "#from_tree" do
    context "with simple TreeNode" do
      let(:tree_node) do
        Canon::TreeDiff::Core::TreeNode.new(
          label: "p",
          value: "content"
        )
      end

      it "converts back to HTML" do
        result = adapter.from_tree(tree_node)

        expect(result).to be_a(Nokogiri::HTML::Document)
        expect(result.root.name).to eq("p")
        expect(result.root.content).to eq("content")
      end
    end

    context "with nested TreeNode" do
      let(:tree_node) do
        div = Canon::TreeDiff::Core::TreeNode.new(
          label: "div",
          attributes: { "class" => "container" }
        )
        h1 = Canon::TreeDiff::Core::TreeNode.new(
          label: "h1",
          value: "Title"
        )
        p = Canon::TreeDiff::Core::TreeNode.new(
          label: "p",
          value: "Text"
        )
        div.add_child(h1)
        div.add_child(p)
        div
      end

      it "converts nested structure to HTML" do
        result = adapter.from_tree(tree_node)

        expect(result.root.name).to eq("div")
        expect(result.root["class"]).to eq("container")

        children = result.root.element_children
        expect(children[0].name).to eq("h1")
        expect(children[0].content).to eq("Title")
        expect(children[1].name).to eq("p")
        expect(children[1].content).to eq("Text")
      end
    end

    context "with attributes" do
      let(:tree_node) do
        Canon::TreeDiff::Core::TreeNode.new(
          label: "a",
          value: "Link",
          attributes: {
            "href" => "https://example.com",
            "target" => "_blank"
          }
        )
      end

      it "preserves attributes" do
        result = adapter.from_tree(tree_node)

        expect(result.root["href"]).to eq("https://example.com")
        expect(result.root["target"]).to eq("_blank")
        expect(result.root.content).to eq("Link")
      end
    end
  end

  describe "round-trip conversion" do
    let(:html_string) do
      <<~HTML
        <html>
          <head>
            <title>Test Page</title>
          </head>
          <body>
            <header id="top">
              <h1>Main Title</h1>
              <nav>
                <a href="/home">Home</a>
                <a href="/about">About</a>
              </nav>
            </header>
            <main>
              <article>
                <h2>Article Title</h2>
                <p>First paragraph.</p>
                <p>Second paragraph.</p>
              </article>
            </main>
          </body>
        </html>
      HTML
    end

    it "maintains structure through round-trip" do
      original = Nokogiri::HTML(html_string)
      tree = adapter.to_tree(original)
      result = adapter.from_tree(tree)

      # Compare structure
      expect(result.root.name).to eq(original.root.name)

      # Compare specific elements
      original_title = original.at_css("title")
      result_title = result.at_css("title")
      expect(result_title.content).to eq(original_title.content)

      original_h1 = original.at_css("h1")
      result_h1 = result.at_css("h1")
      expect(result_h1.content).to eq(original_h1.content)

      original_header = original.at_css("header")
      result_header = result.at_css("header")
      expect(result_header["id"]).to eq(original_header["id"])

      # Compare navigation links
      original_links = original.css("nav a").map(&:content)
      result_links = result.css("nav a").map(&:content)
      expect(result_links).to eq(original_links)
    end
  end
end
