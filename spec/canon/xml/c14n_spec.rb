# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Xml::C14n do
  describe ".canonicalize" do
    it "produces canonical form for simple XML" do
      input = "<root><a>1</a><b>2</b></root>"
      result = described_class.canonicalize(input)
      expect(result).to eq("<root><a>1</a><b>2</b></root>")
    end

    it "removes XML declaration" do
      input = '<?xml version="1.0" encoding="UTF-8"?><root/>'
      result = described_class.canonicalize(input)
      expect(result).not_to include("<?xml")
      expect(result).to eq("<root></root>")
    end

    it "converts empty elements to start-end tag pairs" do
      input = "<root/>"
      result = described_class.canonicalize(input)
      expect(result).to eq("<root></root>")
    end

    it "encodes special characters in text content" do
      input = "<root>Text with &amp; &lt; &gt; symbols</root>"
      result = described_class.canonicalize(input)
      expect(result).to include("&amp;")
      expect(result).to include("&lt;")
      expect(result).to include("&gt;")
    end

    it "encodes special characters in attribute values" do
      input = '<root attr="value with &quot; &amp; &lt;"/>'
      result = described_class.canonicalize(input)
      expect(result).to include('attr="value with &quot; &amp; &lt;"')
    end

    it "normalizes whitespace in attribute values per XML spec" do
      # Per XML spec, attribute value normalization converts tabs, newlines,
      # and carriage returns to spaces during parsing
      input = "<root attr=\"value\twith\nwhitespace\r\"/>"
      result = described_class.canonicalize(input)
      # After normalization by XML parser, whitespace becomes spaces
      expect(result).to include('attr="value with whitespace "')
    end

    it "sorts attributes lexicographically by namespace URI then local name" do
      input = '<root z="3" a="1" b="2"/>'
      result = described_class.canonicalize(input)
      # Attributes with empty namespace URI are sorted by local name
      expect(result).to eq('<root a="1" b="2" z="3"></root>')
    end

    it "sorts namespace declarations lexicographically" do
      input = '<root xmlns:z="http://z.com" xmlns:a="http://a.com"/>'
      result = described_class.canonicalize(input)
      expect(result.index("xmlns:a")).to be < result.index("xmlns:z")
    end

    it "removes superfluous namespace declarations" do
      input = '<root xmlns:a="http://a.com"><child xmlns:a="http://a.com"/></root>'
      result = described_class.canonicalize(input)
      # Child should not repeat parent's namespace declaration
      expect(result).to eq('<root xmlns:a="http://a.com"><child></child></root>')
    end

    it "omits xml namespace with standard URI" do
      input = '<root xmlns:xml="http://www.w3.org/XML/1998/namespace"/>'
      result = described_class.canonicalize(input)
      # xml namespace with standard URI should be omitted
      expect(result).not_to include("xmlns:xml")
    end

    it "processes processing instructions" do
      input = "<?pi-target pi-data?><root/>"
      result = described_class.canonicalize(input)
      expect(result).to include("<?pi-target pi-data?>")
    end

    it "adds line breaks around PIs outside document element" do
      input = "<?pi-before?><root/><?pi-after?>"
      result = described_class.canonicalize(input)
      # PIs outside the document element get line breaks
      expect(result).to include("<?pi-before?>\n")
      expect(result).to include("\n<?pi-after?>")
    end

    context "with comments" do
      it "excludes comments by default" do
        input = "<root><!-- comment --><a>1</a></root>"
        result = described_class.canonicalize(input)
        expect(result).not_to include("<!--")
        expect(result).to eq("<root><a>1</a></root>")
      end

      it "includes comments when with_comments is true" do
        input = "<root><!-- comment --><a>1</a></root>"
        result = described_class.canonicalize(input, with_comments: true)
        expect(result).to include("<!-- comment -->")
      end

      it "adds line breaks around comments outside document element" do
        input = "<!-- before --><root/><!-- after -->"
        result = described_class.canonicalize(input, with_comments: true)
        # Comments outside the document element get line breaks
        expect(result).to include("<!-- before -->\n")
        expect(result).to include("\n<!-- after -->")
      end
    end

    context "namespace handling" do
      it "handles default namespace" do
        input = '<root xmlns="http://example.com"><child/></root>'
        result = described_class.canonicalize(input)
        expect(result).to include('xmlns="http://example.com"')
      end

      it "emits xmlns=\"\" for empty default namespace when parent has non-empty default" do
        input = '<root xmlns="http://example.com"><child xmlns=""/></root>'
        result = described_class.canonicalize(input)
        expect(result).to include('<child xmlns="">')
      end

      it "handles multiple namespace prefixes" do
        input = <<~XML
          <root xmlns:a="http://a.com" xmlns:b="http://b.com">
            <a:child/>
            <b:child/>
          </root>
        XML
        result = described_class.canonicalize(input)
        expect(result).to include('xmlns:a="http://a.com"')
        expect(result).to include('xmlns:b="http://b.com"')
        expect(result).to include("<a:child>")
        expect(result).to include("<b:child>")
      end
    end

    context "character encoding" do
      it "outputs UTF-8" do
        input = "<root>©</root>"
        result = described_class.canonicalize(input)
        expect(result.encoding).to eq(Encoding::UTF_8)
        expect(result).to include("©")
      end

      it "normalizes line endings per XML spec" do
        # Per XML spec, CR and CRLF are normalized to LF during parsing
        # C14N then encodes remaining CR characters
        input = "<root>line1&#xD;&#xA;line2</root>"
        result = described_class.canonicalize(input)
        # The &#xD; entity becomes an actual CR which then gets encoded
        expect(result).to include("&#xD;")
      end
    end

    context "error handling" do
      it "raises error for relative namespace URIs" do
        input = '<root xmlns:bad="relative/uri"/>'
        expect do
          described_class.canonicalize(input)
        end.to raise_error(Canon::Error, /Relative namespace URI/)
      end
    end
  end
end
