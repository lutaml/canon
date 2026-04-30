# frozen_string_literal: true

require "spec_helper"
require "canon/comparison/html_parser"

RSpec.describe Canon::Comparison::HtmlParser do
  describe ".normalize_html_for_parsing" do
    # Issue #122: HTML5 fragment parsing treats <?xml ?> as a bogus
    # comment, breaking fragment-length comparisons.
    it "strips a leading <?xml ?> processing instruction" do
      input = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><html><body><p/></body></html>"
      expect(described_class.normalize_html_for_parsing(input))
        .to eq("<html><body><p/></body></html>")
    end

    it "tolerates whitespace before the leading PI" do
      input = "   \n<?xml version='1.0'?>\n<html><body/></html>"
      expect(described_class.normalize_html_for_parsing(input))
        .to eq("\n<html><body/></html>")
    end

    it "leaves a non-leading <?xml ?> alone" do
      input = "<html><body><p>see <?xml hi?></p></body></html>"
      expect(described_class.normalize_html_for_parsing(input)).to eq(input)
    end

    it "still collapses whitespace between </head> and <body>" do
      input = "<?xml version='1.0'?><html><head></head>\n  <body></body></html>"
      expect(described_class.normalize_html_for_parsing(input))
        .to eq("<html><head></head><body></body></html>")
    end

    it "is a no-op for plain HTML with no PI and no head/body whitespace" do
      input = "<div><p>hi</p></div>"
      expect(described_class.normalize_html_for_parsing(input)).to eq(input)
    end
  end

  describe ".parse with a leading <?xml ?> (issue #122)" do
    it "produces the same fragment children as the same input without the PI" do
      with_pi = "<?xml version=\"1.0\"?><html><body>" \
                "<div class=\"a\"/><div class=\"b\"/></body></html>"
      without_pi = "<html><body><div class=\"a\"/><div class=\"b\"/></body></html>"

      a = described_class.parse(with_pi, :html5).children.map(&:class)
      b = described_class.parse(without_pi, :html5).children.map(&:class)
      expect(a).to eq(b)
      expect(a).not_to include(Nokogiri::XML::Comment)
    end
  end
end
