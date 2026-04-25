# frozen_string_literal: true

require "spec_helper"

# Regression test for https://github.com/lutaml/canon/issues/118
#
# HTML4 and HTML5 share HTML's content-model whitespace rules, so
# be_html4_equivalent_to and be_html5_equivalent_to must return the same
# equivalence verdict for any input where the only divergence is whitespace
# handling at HTML-content-model boundaries.
#
# Prior to the fix, :html / :html4 input was parsed via Nokogiri::XML.fragment
# (XML whitespace rules — every whitespace text node significant) while
# :html5 was parsed via Nokogiri::HTML5.fragment (HTML rules — whitespace at
# block boundaries collapsed). The two matchers disagreed on equivalent
# input.
RSpec.describe "HTML4/HTML5 whitespace-sensitivity parity (#118)" do
  shared_examples "agrees across html4 and html5" do |label, a, b, expected|
    it "#{label} (html, html4, html5 all agree → #{expected})" do
      r_html  = Canon::Comparison.equivalent?(a, b, format: :html)
      r_html4 = Canon::Comparison.equivalent?(a, b, format: :html4)
      r_html5 = Canon::Comparison.equivalent?(a, b, format: :html5)

      expect([r_html, r_html4, r_html5]).to all(eq(expected))
    end
  end

  describe "whitespace at block boundaries is collapsed" do
    include_examples "agrees across html4 and html5",
                     "whitespace between block divs",
                     "<body><div>x</div><div>y</div></body>",
                     "<body>\n  <div>x</div>\n  <div>y</div>\n</body>",
                     true

    include_examples "agrees across html4 and html5",
                     "whitespace flanking inline <br> between block divs",
                     "<body><div>x</div><br><div>y</div></body>",
                     "<body>\n  <div>x</div>\n  <br/>\n  <div>y</div>\n</body>",
                     true

    include_examples "agrees across html4 and html5",
                     "whitespace around html→head/body",
                     "<html><head></head><body><p>x</p></body></html>",
                     "<html>\n  <head/>\n  <body><p>x</p></body>\n</html>",
                     true
  end

  describe "whitespace between adjacent inline siblings is significant" do
    include_examples "agrees across html4 and html5",
                     "space between two <span>s present vs absent",
                     "<body><p><span>A</span><span>B</span></p></body>",
                     "<body><p><span>A</span> <span>B</span></p></body>",
                     false
  end

  describe "NBSP is never collapsed" do
    include_examples "agrees across html4 and html5",
                     "&nbsp; vs empty inside <p>",
                     "<body><p>&nbsp;</p></body>",
                     "<body><p></p></body>",
                     false
  end

  describe "real content differences are still detected" do
    include_examples "agrees across html4 and html5",
                     "different text content",
                     "<body><p>hello</p></body>",
                     "<body><p>world</p></body>",
                     false

    include_examples "agrees across html4 and html5",
                     "extra child element",
                     "<body><div>x</div></body>",
                     "<body><div>x</div><div>y</div></body>",
                     false
  end
end
