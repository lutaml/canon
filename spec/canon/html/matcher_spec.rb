# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Canon HTML matchers" do
  let(:actual_html) do
    File.read(File.join(__dir__,
                        "../../fixtures/html/blocks-notes-actual.html"))
  end
  let(:expected_html) do
    File.read(File.join(__dir__,
                        "../../fixtures/html/blocks-notes-expected.html"))
  end

  describe "be_html4_equivalent_to" do
    it "matches semantically equivalent HTML despite comment differences" do
      expect(actual_html).to be_html4_equivalent_to(expected_html)
    end

    it "provides helpful diff when HTML does not match" do
      different_html = expected_html.gsub("Foreword", "Introduction")
      expect(actual_html).not_to be_html4_equivalent_to(different_html)
    end
  end

  describe "be_html5_equivalent_to" do
    it "matches semantically equivalent HTML despite comment differences" do
      expect(actual_html).to be_html5_equivalent_to(expected_html)
    end

    it "provides helpful diff when HTML does not match" do
      different_html = expected_html.gsub("Foreword", "Introduction")
      expect(actual_html).not_to be_html5_equivalent_to(different_html)
    end
  end

  describe "DOM comparison details" do
    it "ignores whitespace differences in text nodes" do
      html_with_spaces = expected_html.gsub(
        "Table of contents",
        "Table  of   contents",
      )
      expect(html_with_spaces).to be_html4_equivalent_to(expected_html)
    end

    it "ignores comment nodes entirely" do
      html_with_comments = expected_html.gsub(
        "<!--\n      -->",
        "<!-- This is a different comment with lots of content -->",
      )
      expect(html_with_comments).to be_html4_equivalent_to(expected_html)
    end

    it "compares element names" do
      html_different_element = expected_html.gsub("<h1", "<h2").gsub("</h1>",
                                                                     "</h2>")
      expect(html_different_element).not_to be_html4_equivalent_to(expected_html)
    end

    it "compares attributes" do
      html_different_attr = expected_html.gsub('id="A"', 'id="C"')
      expect(html_different_attr).not_to be_html4_equivalent_to(expected_html)
    end

    it "compares text content after normalization" do
      html_different_text = expected_html.gsub("Foreword", "Introduction")
      expect(html_different_text).not_to be_html4_equivalent_to(expected_html)
    end
  end

  describe "namespace handling" do
    it "handles xmlns attributes correctly" do
      # Both fixtures have xmlns attributes, they should match
      expect(actual_html).to be_html4_equivalent_to(expected_html)
    end
  end
end
