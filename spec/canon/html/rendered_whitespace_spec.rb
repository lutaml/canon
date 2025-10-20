# frozen_string_literal: true

require "spec_helper"

RSpec.describe "HTML rendered whitespace normalization" do
  describe "with :rendered preprocessing" do
    it "treats multi-line and single-line text content as equivalent" do
      # Multi-line HTML with newlines between inline elements
      multiline_html = <<~HTML
        <p class="TableTitle" style="text-align:center;">
        Table 1 — Repeatability and reproducibility of
        <i>husked</i>
        rice yield
        </p>
      HTML

      # Single-line HTML with same content
      singleline_html = '<p class="TableTitle" style="text-align:center;">Table 1 — Repeatability and reproducibility of <i>husked</i> rice yield</p>'

      expect(singleline_html).to be_html_equivalent_to(multiline_html,
                                                        preprocessing: :rendered)
    end

    it "collapses whitespace sequences in text nodes" do
      html1 = <<~HTML
        <div>
          <p>Multiple    spaces   and
          newlines    should
          collapse</p>
        </div>
      HTML

      html2 = "<div><p>Multiple spaces and newlines should collapse</p></div>"

      expect(html1).to be_html_equivalent_to(html2, preprocessing: :rendered)
    end

    it "preserves whitespace in pre elements" do
      html1 = <<~HTML
        <pre>Multiple    spaces   and
        newlines    should
        be preserved</pre>
      HTML

      html2 = <<~HTML
        <pre>Multiple    spaces   and
        newlines    should
        be preserved</pre>
      HTML

      expect(html1).to be_html_equivalent_to(html2, preprocessing: :rendered)

      # Should NOT match if whitespace is different in pre
      html3 = "<pre>Multiple spaces and newlines should be preserved</pre>"

      expect(html1).not_to be_html_equivalent_to(html3,
                                                  preprocessing: :rendered)
    end

    it "preserves whitespace in code elements" do
      html1 = "<code>const x    =    5;</code>"
      html2 = "<code>const x    =    5;</code>"

      expect(html1).to be_html_equivalent_to(html2, preprocessing: :rendered)

      # Should NOT match if whitespace is different in code
      html3 = "<code>const x = 5;</code>"

      expect(html1).not_to be_html_equivalent_to(html3,
                                                  preprocessing: :rendered)
    end

    it "handles complex nested structures with mixed whitespace" do
      multiline_html = <<~HTML
        <div class="WordSection2">
          <p class="page-break">
          <br clear="all" style="mso-special-character:line-break;page-break-before:always"></p>
          <div>
            <h1 class="ForewordTitle">Foreword</h1>
            <p class="TableTitle" style="text-align:center;">
            Repeatability and reproducibility of
            <i>husked</i>
            rice yield
            </p>
          </div>
        </div>
      HTML

      singleline_html = '<div class="WordSection2"><p class="page-break"><br clear="all" style="mso-special-character:line-break;page-break-before:always"></p><div><h1 class="ForewordTitle">Foreword</h1><p class="TableTitle" style="text-align:center;">Repeatability and reproducibility of <i>husked</i> rice yield</p></div></div>'

      expect(multiline_html).to be_html_equivalent_to(singleline_html,
                                                       preprocessing: :rendered)
    end

    it "handles text nodes at different positions in parent" do
      # Text at start of parent
      html1 = "<p>   Leading spaces</p>"
      html2 = "<p>Leading spaces</p>"

      expect(html1).to be_html_equivalent_to(html2, preprocessing: :rendered)

      # Text at end of parent
      html3 = "<p>Trailing spaces   </p>"
      html4 = "<p>Trailing spaces</p>"

      expect(html3).to be_html_equivalent_to(html4, preprocessing: :rendered)

      # Text in middle (between siblings)
      html5 = "<p><span>A</span>   middle text   <span>B</span></p>"
      html6 = "<p><span>A</span> middle text <span>B</span></p>"

      expect(html5).to be_html_equivalent_to(html6, preprocessing: :rendered)
    end

    it "handles empty text nodes and whitespace-only nodes" do
      html1 = <<~HTML
        <div>
          <p>Content</p>

          <p>More content</p>
        </div>
      HTML

      html2 = "<div><p>Content</p><p>More content</p></div>"

      expect(html1).to be_html_equivalent_to(html2, preprocessing: :rendered)
    end

    it "reproduces IsoDoc table spec scenario" do
      # This is the actual failing case from IsoDoc
      expected = <<~HTML
        <!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN" "http://www.w3.org/TR/REC-html40/loose.dtd">
        <html xmlns:epub="http://www.idpf.org/2007/ops">
        <head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8"></head>
        <body>
        <div class="WordSection2">
        <p class="page-break"><br clear="all" style="mso-special-character:line-break;page-break-before:always"></p>
        <div>
        <h1 class="ForewordTitle">Foreword</h1>
        <p class="TableTitle" style="text-align:center;">
        Repeatability and reproducibility of
        <i>husked</i>
        rice yield
        </p>
        </div>
        </div>
        </body>
        </html>
      HTML

      actual = '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN" "http://www.w3.org/TR/REC-html40/loose.dtd"><html xmlns:epub="http://www.idpf.org/2007/ops"><head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8"></head><body><div class="WordSection2"><p class="page-break"><br clear="all" style="mso-special-character:line-break;page-break-before:always"></p><div><h1 class="ForewordTitle">Foreword</h1><p class="TableTitle" style="text-align:center;">Repeatability and reproducibility of <i>husked</i> rice yield</p></div></div></body></html>'

      expect(actual).to be_html_equivalent_to(expected,
                                               preprocessing: :rendered)
    end
  end
end
