# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Match Profiles Integration" do
  let(:actual_xml) do
    File.read("spec/fixtures/xml/isodoc-blockquotes-actual.xml")
  end

  let(:expected_xml) do
    File.read("spec/fixtures/xml/isodoc-blockquotes-expected.xml")
  end

  let(:actual_html) do
    File.read("spec/fixtures/html/blocks-notes-actual.html")
  end

  let(:expected_html) do
    File.read("spec/fixtures/html/blocks-notes-expected.html")
  end

  describe "XML comparison with match profiles" do
    context "without any profile (strict matching)" do
      it "fails because of whitespace differences" do
        expect(actual_xml).not_to be_xml_equivalent_to(expected_xml)
      end
    end

    context "with spec_friendly profile" do
      it "matches despite whitespace and formatting differences" do
        expect(actual_xml).to be_xml_equivalent_to(expected_xml,
                                                   match_profile: :spec_friendly)
      end
    end

    context "with content_only profile" do
      it "matches despite whitespace and formatting differences" do
        expect(actual_xml).to be_xml_equivalent_to(expected_xml,
                                                   match_profile: :content_only)
      end
    end

    context "with explicit match options" do
      it "matches when text_content is normalized and structural_whitespace ignored" do
        expect(actual_xml).to be_xml_equivalent_to(
          expected_xml,
          match_options: {
            text_content: :normalize,
            structural_whitespace: :ignore,
            attribute_whitespace: :strict,
            comments: :ignore,
          },
        )
      end
    end
  end

  describe "HTML comparison with match profiles" do
    context "without any profile" do
      it "matches (HTML already uses collapse_whitespace and ignore_comments)" do
        # HTML comparison already has default flexible behavior
        expect(actual_html).to be_html_equivalent_to(expected_html)
      end
    end

    context "with spec_friendly profile" do
      it "matches with explicit profile" do
        expect(actual_html).to be_html_equivalent_to(expected_html,
                                                     match_profile: :spec_friendly)
      end
    end
  end

  describe "global configuration" do
    around do |example|
      original_xml_profile = Canon::RSpecMatchers.xml_match_profile
      original_html_profile = Canon::RSpecMatchers.html_match_profile
      example.run
      Canon::RSpecMatchers.xml_match_profile = original_xml_profile
      Canon::RSpecMatchers.html_match_profile = original_html_profile
    end

    it "applies global XML match profile to all tests" do
      Canon::RSpecMatchers.configure do |config|
        config.xml_match_profile = :spec_friendly
      end

      expect(actual_xml).to be_xml_equivalent_to(expected_xml)
    end

    it "test-level profile overrides global profile" do
      Canon::RSpecMatchers.configure do |config|
        config.xml_match_profile = :spec_friendly
      end

      # This should still use strict behavior at test level
      expect(actual_xml).not_to be_xml_equivalent_to(expected_xml,
                                                     match_profile: :strict)
    end
  end

  describe "match option dimensions" do
    let(:xml_with_different_whitespace) do
      <<~XML
        <root>
          <element>  text with  spaces  </element>
        </root>
      XML
    end

    let(:xml_normalized) do
      <<~XML
        <root>
          <element>text with spaces</element>
        </root>
      XML
    end

    context "text_content dimension" do
      it "strict behavior fails on whitespace differences" do
        expect(xml_with_different_whitespace).not_to be_xml_equivalent_to(
          xml_normalized,
          match_options: {
            text_content: :strict,
            structural_whitespace: :ignore,
            attribute_whitespace: :strict,
            comments: :ignore,
          },
        )
      end

      it "normalize behavior matches despite whitespace differences" do
        expect(xml_with_different_whitespace).to be_xml_equivalent_to(
          xml_normalized,
          match_options: {
            text_content: :normalize,
            structural_whitespace: :ignore,
            attribute_whitespace: :strict,
            comments: :ignore,
          },
        )
      end
    end

    context "structural_whitespace dimension" do
      let(:compact_xml) { "<root><a><b>text</b></a></root>" }
      let(:formatted_xml) do
        <<~XML
          <root>
            <a>
              <b>text</b>
            </a>
          </root>
        XML
      end

      it "ignore behavior matches despite formatting differences" do
        expect(compact_xml).to be_xml_equivalent_to(
          formatted_xml,
          match_options: {
            text_content: :normalize,
            structural_whitespace: :ignore,
            attribute_whitespace: :strict,
            comments: :ignore,
          },
        )
      end
    end

    context "comments dimension" do
      let(:xml_with_comment) { "<root><!-- comment --><a>text</a></root>" }
      let(:xml_different_comment) do
        "<root><!-- different --><a>text</a></root>"
      end
      let(:xml_no_comment) { "<root><a>text</a></root>" }

      it "ignore behavior matches despite comment differences" do
        expect(xml_with_comment).to be_xml_equivalent_to(
          xml_different_comment,
          match_options: {
            text_content: :normalize,
            structural_whitespace: :ignore,
            attribute_whitespace: :strict,
            comments: :ignore,
          },
        )
      end

      it "ignore behavior matches when one has comments and other doesn't" do
        expect(xml_with_comment).to be_xml_equivalent_to(
          xml_no_comment,
          match_options: {
            text_content: :normalize,
            structural_whitespace: :ignore,
            attribute_whitespace: :strict,
            comments: :ignore,
          },
        )
      end
    end

    context "attribute_whitespace dimension" do
      let(:xml_attr_spaces) { '<root><a id=" value ">text</a></root>' }
      let(:xml_attr_no_spaces) { '<root><a id="value">text</a></root>' }

      it "strict behavior fails on attribute whitespace differences" do
        expect(xml_attr_spaces).not_to be_xml_equivalent_to(
          xml_attr_no_spaces,
          match_options: {
            text_content: :normalize,
            structural_whitespace: :ignore,
            attribute_whitespace: :strict,
            comments: :ignore,
          },
        )
      end

      it "normalize behavior matches despite attribute whitespace" do
        expect(xml_attr_spaces).to be_xml_equivalent_to(
          xml_attr_no_spaces,
          match_options: {
            text_content: :normalize,
            structural_whitespace: :ignore,
            attribute_whitespace: :normalize,
            comments: :ignore,
          },
        )
      end
    end
  end
end
