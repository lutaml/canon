# frozen_string_literal: true

require "spec_helper"
require "canon/diff_formatter/by_line/html_formatter"

RSpec.describe Canon::DiffFormatter::ByLine::HtmlFormatter do
  let(:formatter) do
    described_class.new(
      use_color: false,
      context_lines: 3,
      visualization_map: Canon::DiffFormatter::DEFAULT_VISUALIZATION_MAP,
    )
  end

  describe "#format with HTML5 self-closing br tags" do
    context "when comparing HTML with self-closing br tags" do
      # Regression test for bug report: HTML comparison with self-closing <br/> tags
      # was failing because HtmlFormatter was calling wrong class method
      # (Canon::Xml::DataModel.from_html instead of Canon::Html::DataModel.from_html)
      it "correctly handles equivalent HTML with self-closing br tags" do
        html1 = <<~HTML
          <html lang="en">
              <head/>
              <body lang="en">
                 <div class="title-section">
                    <p> </p>
                 </div>
                 <br/>
                 <div class="prefatory-section">
                    <p> </p>
                 </div>
                 <br/>
                 <div class="main-section">
                    <br/>
                    <div id="fwd">
                       <h1 class="ForewordTitle">Foreword</h1>
                    </div>
                 </div>
              </body>
          </html>
        HTML

        html2 = <<~HTML
          <html lang="en"><head/><body lang="en"><div class="title-section"><p> </p></div><br/><div class="prefatory-section"><p> </p></div><br/><div class="main-section"><br/><div id="fwd"><h1 class="ForewordTitle">Foreword</h1></div></div></body></html>
        HTML

        # The HTML should be semantically equivalent (Nokogiri normalizes <br/> to <br>)
        result = Canon::Comparison.equivalent?(html1, html2, format: :html5,
                                                             verbose: true)

        expect(result.equivalent?).to be true
        expect(result.differences).to be_empty

        # Also verify diff formatter works without errors
        diff_formatter = Canon::DiffFormatter.new(use_color: false,
                                                  mode: :by_line)
        output = diff_formatter.format_comparison_result(result, html1, html2)

        # Should show the algorithm and diff mode (or success message)
        # Since documents are equivalent, should show "identical" message
        expect(output).to match(/identical|Algorithm:/)
      end

      it "normalizes br/ to br during HTML5 parsing" do
        html1 = "<html><body><p>Text</p><br/></body></html>"
        html2 = "<html><body><p>Text</p><br></body></html>"

        result = Canon::Comparison.equivalent?(html1, html2, format: :html5)

        expect(result).to be true
      end

      it "handles nested lists with self-closing br tags correctly" do
        html1 = <<~HTML
          <html>
            <body>
              <div>
                <ul id="_">
                  <li id="_">Item 1</li>
                  <li id="_">
                    <p>Item 2</p>
                    <div class="ul_wrap">
                      <ul id="_">
                        <li id="_">Nested 1</li>
                      </ul>
                    </div>
                  </li>
                </ul>
              </div>
            </body>
          </html>
        HTML

        html2 = <<~HTML
          <html><body><div><ul id="_"><li id="_">Item 1</li><li id="_"><p>Item 2</p><div class="ul_wrap"><ul id="_"><li id="_">Nested 1</li></ul></div></li></ul></div></body></html>
        HTML

        result = Canon::Comparison.equivalent?(html1, html2, format: :html5,
                                                             verbose: true)

        expect(result.equivalent?).to be true
        expect(result.differences).to be_empty
      end
    end
  end
end
