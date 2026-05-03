# frozen_string_literal: true

require "spec_helper"
require "canon/pretty_printer/html"

RSpec.describe Canon::PrettyPrinter::Html do
  describe "#format" do
    let(:html_content) do
      <<~HTML
        <!DOCTYPE html>
        <html><head><title>Test</title></head><body><div>content</div></body></html>
      HTML
    end

    context "with default options" do
      subject { described_class.new }

      it "formats HTML successfully" do
        result = subject.format(html_content)
        expect(result).to be_a(String)
        expect(result).not_to be_empty
      end

      it "preserves DOCTYPE" do
        result = subject.format(html_content)
        expect(result).to match(/<!DOCTYPE html>/i)
      end

      it "preserves all HTML elements" do
        result = subject.format(html_content)
        expect(result).to include("<head>")
        expect(result).to include("<title>")
        expect(result).to include("<body>")
        expect(result).to include("<div>")
      end
    end

    context "with XHTML" do
      subject { described_class.new(indent: 2) }

      let(:xhtml_content) do
        <<~XHTML
          <?xml version="1.0"?>
          <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
            "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
          <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Test</title></head><body><div>content</div></body></html>
        XHTML
      end

      it "formats XHTML correctly" do
        result = subject.format(xhtml_content)
        expect(result).to include('xmlns="http://www.w3.org/1999/xhtml"')
      end

      it "uses XML formatting for XHTML" do
        result = subject.format(xhtml_content)
        expect(result).to match(/^<\?xml version/)
      end
    end

    context "with nested elements" do
      subject { described_class.new(indent: 2) }

      let(:nested_html) do
        <<~HTML
          <!DOCTYPE html>
          <html><body><div><p><span>nested content</span></p></div></body></html>
        HTML
      end

      it "preserves nested structure" do
        result = subject.format(nested_html)
        expect(result).to include("<body>")
        expect(result).to include("<div>")
        expect(result).to include("<p>")
        expect(result).to include("<span>")
        expect(result).to include("nested content")
      end
    end

    # Issue #133: Nokogiri::HTML5#to_html silently ignored the
    # +indent:+ option, producing a single-line blob inside the
    # PRETTY-PRINTED INPUTS section.  These specs lock the new
    # +fixture_ready: true+ mode that uses
    # +write_to(save_with: FORMAT|AS_XHTML|NO_DECLARATION)+ to
    # actually indent.  The default (non-fixture-ready) mode is
    # untouched -- existing callers that depend on its
    # structurally-faithful behaviour are unaffected.
    context "indentation behaviour (issue #133)" do
      subject { described_class.new(indent: 2, fixture_ready: true) }

      it "indents Word-flavoured HTML5 input (no XHTML doctype, no default xmlns)" do
        # Real-world reproducer: Word output starts with
        # `<html xmlns:epub="..." lang="en">` — no XHTML DOCTYPE, no
        # `xmlns="http://www.w3.org/1999/xhtml"` declaration.  Before
        # the fix, this took the broken format_as_html branch.
        input = '<html xmlns:epub="http://www.idpf.org/2007/ops" ' \
                'lang="en"><head><meta http-equiv="Content-Type" ' \
                'content="text/html; charset=UTF-8"/></head>' \
                '<body><div class="WordSection2">' \
                '<p class="page-break"><br clear="all"/></p></div></body></html>'

        result = subject.format(input)

        # Multiple lines.
        expect(result.lines.length).to be > 5
        # At least one indented child element.
        expect(result).to match(/\n  </)
        # The original <body>'s children appear on separate lines
        # rather than as a single blob.
        expect(result).to match(/<body[^>]*>\s*\n\s+</)
      end

      it "indents plain HTML5 doctype input" do
        input = "<!DOCTYPE html>\n" \
                "<html><body><div><p>x</p></div></body></html>"

        result = subject.format(input)

        expect(result.lines.length).to be > 5
        expect(result).to match(/<body>\s*\n\s+<div>/)
        expect(result).to match(/<div>\s*\n\s+<p>/)
      end

      it "indents XHTML-shaped input" do
        input = "<html xmlns=\"http://www.w3.org/1999/xhtml\">" \
                "<body><p>x</p></body></html>"

        result = subject.format(input)

        expect(result.lines.length).to be > 3
        expect(result).to match(/<body>\s*\n\s+<p>/)
      end

      it "preserves element count through the round-trip" do
        # A cheap regression guard: the serializer must not drop
        # content during pretty-print.
        input = "<html xmlns:epub=\"x\" lang=\"en\">" \
                "<body><div><p>a</p><p>b</p><p>c</p></div></body></html>"
        result = subject.format(input)

        out_count = Nokogiri::XML(result).search("p").length
        expect(out_count).to eq(3)
      end
    end

    context "fixture_ready: true — XHTML shape (regression #135)" do
      subject { described_class.new(indent: 2, fixture_ready: true) }

      it "emits XHTML shape: void self-closed, non-void paired" do
        result = subject.format('<html><body><a href="#"></a><br><img src="y"><hr></body></html>')
        expect(result).to include('<a href="#"></a>')
        expect(result).to match(%r{<br\s*/>})
        expect(result).to match(%r{<img src="y"\s*/>})
        expect(result).to match(%r{<hr\s*/>})
        expect(result).not_to match(%r{<a [^>]*/>})
      end
    end

    context "regression #135 — XHTML branch must not self-close non-void elements" do
      subject { described_class.new(indent: 2) }

      let(:xhtml) do
        <<~XHTML
          <?xml version="1.0"?>
          <html xmlns="http://www.w3.org/1999/xhtml"><body><a href="x"></a><span></span><div></div><br/><img src="y"/><hr/></body></html>
        XHTML
      end

      it "writes empty non-void elements as <tag></tag>" do
        result = subject.format(xhtml)
        expect(result).to include('<a href="x"></a>')
        expect(result).to include("<span></span>")
        expect(result).to include("<div></div>")
        expect(result).not_to match(%r{<a [^>]*/>})
        expect(result).not_to include("<span/>")
        expect(result).not_to include("<div/>")
      end

      it "leaves void elements self-closed (XHTML shape)" do
        result = subject.format(xhtml)
        expect(result).to include("<br/>")
        expect(result).to include('<img src="y"/>')
        expect(result).to include("<hr/>")
      end
    end

    # libxml's FORMAT save flag does not insert indentation around the
    # children of an element it sees as mixed content (any
    # non-whitespace-only text node child).  Real-world HTML5 input
    # arriving from upstream pipelines often carries stray whitespace
    # text nodes between block-level siblings (`<body>` -> `<div>`,
    # `<br>`, `<div>`, ...), which libxml then treats as mixed content
    # and emits on a single line.  Issue #133's first fix added
    # FORMAT|AS_XHTML|NO_DECLARATION but did not strip those text
    # nodes; this regression covers the follow-up that does.
    context "fixture_ready: true — strips structural whitespace before FORMAT (#133 follow-up)" do
      subject { described_class.new(indent: 2, fixture_ready: true) }

      it "indents top-level <body> siblings even when source has stray inter-sibling whitespace" do
        # Mimics the metanorma-iso shape: <body> with <div>, <br>, <div>
        # siblings and stray text-node whitespace between them.
        input = "<html><body>\n  <div class=\"a\"><p>x</p></div>\n  <br>\n  <div class=\"b\"><p>y</p></div>\n  <br>\n  <div class=\"c\"><p>z</p></div>\n</body></html>"

        result = subject.format(input)

        expect(result).to match(%r{<body>\s*\n\s+<div class="a">})
        expect(result).to match(%r{</div>\s*\n\s+<br\s*/>\s*\n\s+<div class="b">})
        expect(result).to match(%r{<div class="c">\s*\n\s+<p>z</p>\s*\n\s+</div>})
      end

      it "preserves significant inline whitespace inside mixed-content runs" do
        # The space between \"foo\" and <em>bar</em> is significant and
        # must not be stripped.
        input = "<html><body><p>foo <em>bar</em> baz</p></body></html>"

        result = subject.format(input)

        expect(result).to include("foo <em>bar</em> baz")
      end

      it "preserves whitespace inside <pre>" do
        input = "<html><body><pre>line1\n    line2\n  line3</pre></body></html>"

        result = subject.format(input)

        expect(result).to include("line1\n    line2\n  line3")
      end
    end
  end
end
