# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Xml::C14n do
  describe ".canonicalize_subset" do
    describe "simple element selection" do
      it "selects a single element by name" do
        xml = "<root><a>1</a><b>2</b></root>"
        result = described_class.canonicalize_subset(xml, "//b")
        expect(result).to eq("<b>2</b>")
      end

      it "selects by absolute path" do
        xml = "<root><a>1</a><b>2</b></root>"
        result = described_class.canonicalize_subset(xml, "/root/b")
        expect(result).to eq("<b>2</b>")
      end

      it "selects multiple elements" do
        xml = "<root><item>a</item><item>b</item></root>"
        result = described_class.canonicalize_subset(xml, "//item")
        expect(result).to eq("<item>a</item><item>b</item>")
      end

      it "selects by wildcard" do
        xml = "<root><a>1</a><b>2</b></root>"
        result = described_class.canonicalize_subset(xml, "/*")
        expect(result).to include("<a>1</a>")
        expect(result).to include("<b>2</b>")
      end
    end

    describe "nested elements" do
      it "selects deeply nested element" do
        xml = "<root><a><b><c>text</c></b></a></root>"
        result = described_class.canonicalize_subset(xml, "//c")
        expect(result).to eq("<c>text</c>")
      end

      it "inherits namespaces from excluded ancestors" do
        xml = '<root xmlns:ns="http://example.com"><ns:child>text</ns:child></root>'
        result = described_class.canonicalize_subset(xml, "//ns:child")
        expect(result).to include("ns:child")
        expect(result).to include("xmlns:ns")
        expect(result).to include("text")
      end
    end

    describe "predicate support" do
      it "selects by position [1]" do
        xml = "<root><item>first</item><item>second</item><item>third</item></root>"
        result = described_class.canonicalize_subset(xml, "//item[1]")
        expect(result).to eq("<item>first</item>")
      end

      it "selects by attribute existence [@attr]" do
        xml = '<root><item selected="yes">a</item><item>b</item></root>'
        result = described_class.canonicalize_subset(xml, "//item[@selected]")
        expect(result).to eq('<item selected="yes">a</item>')
      end

      it "selects by attribute value [@attr=\'value\']" do
        xml = '<root><item type="a">1</item><item type="b">2</item></root>'
        result = described_class.canonicalize_subset(xml, "//item[@type='a']")
        expect(result).to eq('<item type="a">1</item>')
      end
    end

    describe "union expressions" do
      it "selects nodes matching either expression" do
        xml = "<root><a>1</a><b>2</b><c>3</c></root>"
        result = described_class.canonicalize_subset(xml, "//a | //c")
        expect(result).to include("<a>1</a>")
        expect(result).to include("<c>3</c>")
        expect(result).not_to include("<b>2</b>")
      end
    end

    describe "fallback behavior" do
      it "falls back to full canonicalization when XPath matches root" do
        xml = "<root><a>1</a></root>"
        full = described_class.canonicalize(xml)
        result = described_class.canonicalize_subset(xml, "/root")
        expect(result).to eq(full)
      end

      it "falls back to full canonicalization when XPath matches nothing" do
        xml = "<root><a>1</a></root>"
        full = described_class.canonicalize(xml)
        result = described_class.canonicalize_subset(xml, "//nonexistent")
        expect(result).to eq(full)
      end
    end

    describe "with_comments option" do
      it "excludes comments by default" do
        xml = "<root><!-- comment --><a>text</a></root>"
        result = described_class.canonicalize_subset(xml, "//a")
        expect(result).not_to include("comment")
      end

      it "includes comments when with_comments: true" do
        xml = "<root><a><!-- inner -->text</a></root>"
        result = described_class.canonicalize_subset(xml, "//a", with_comments: true)
        expect(result).to include("<!-- inner -->")
      end
    end
  end
end
