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

    context "pretty: true (fixture-ready output, regression #135)" do
      subject { described_class.new(indent: 2, pretty: true) }

      let(:mixed_html) do
        '<div class="index"><div class="ul_wrap"><p class="y"><a href="#a">A</a><i>Eman</i>c, <a href="#_">Clause 1</a></p><p>second</p></div></div>'
      end

      it "puts each block element on its own line" do
        result = subject.format(mixed_html)
        expect(result).to include("</p>\n    <p>")
        expect(result).to include("</div>\n</div>")
      end

      it "keeps inline mixed content on the same line as the parent block" do
        result = subject.format(mixed_html)
        expect(result).to include('<p class="y"><a href="#a">A</a><i>Eman</i>c, <a href="#_">Clause 1</a></p>')
      end

      it "emits XHTML shape: void self-closed, non-void paired" do
        result = subject.format('<div><a href="#"></a><br><img src="y"><hr></div>')
        expect(result).to include('<a href="#"></a>')
        expect(result).to match(%r{<br\s*/>})
        expect(result).to match(%r{<img src="y"\s*/>})
        expect(result).to match(%r{<hr\s*/>})
        expect(result).not_to match(%r{<a [^>]*/>})
      end

      it "produces no <html><body> wrapper or <?xml?> prologue" do
        result = subject.format(mixed_html)
        expect(result).not_to include("<html>")
        expect(result).not_to include("<body>")
        expect(result).not_to include("<?xml")
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
  end
end
