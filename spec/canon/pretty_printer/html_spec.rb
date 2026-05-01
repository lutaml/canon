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
  end
end
