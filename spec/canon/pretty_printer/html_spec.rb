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
      let(:xhtml_content) do
        <<~XHTML
          <?xml version="1.0"?>
          <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
            "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
          <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Test</title></head><body><div>content</div></body></html>
        XHTML
      end

      subject { described_class.new(indent: 2) }

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
      let(:nested_html) do
        <<~HTML
          <!DOCTYPE html>
          <html><body><div><p><span>nested content</span></p></div></body></html>
        HTML
      end

      subject { described_class.new(indent: 2) }

      it "preserves nested structure" do
        result = subject.format(nested_html)
        expect(result).to include("<body>")
        expect(result).to include("<div>")
        expect(result).to include("<p>")
        expect(result).to include("<span>")
        expect(result).to include("nested content")
      end
    end
  end
end
