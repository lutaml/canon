# frozen_string_literal: true

require "spec_helper"
require "canon/comparison"

RSpec.describe "Space Background Differentiation - Integration" do
  # This tests the ACTUAL end-to-end rendering to verify that
  # formatting-only diff lines properly differentiate background colors
  # for unchanged vs inserted vs removed spaces.
  #
  # When space visualization is ON (space -> ░):
  #   - Unchanged spaces: ░ with NO background
  #   - Inserted spaces: ░ with CYAN background (\e[46m)
  #   - Removed spaces: ░ with BLUE background (\e[44m)

  # Scenario: leading whitespace changed from 2 spaces to 4 spaces
  # The extra 2 spaces are "added" and should show cyan bg
  describe "leading whitespace changes" do
    let(:xml1) do
      <<~XML
        <root>
          <p>  content</p>
        </root>
      XML
    end

    let(:xml2) do
      <<~XML
        <root>
          <p>    content</p>
        </root>
      XML
    end

    it "shows CYAN background on added leading spaces" do
      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true,
        use_color: true,
        match: { text_content: :normalize, structural_whitespace: :normalize }
      )

      # This SHOULD detect a difference since we're comparing with normalization
      # but the key is to see what the diff shows
      diff_output = result.diff(use_color: true)

      # The diff should show cyan background for added spaces
      # Look for the cyan background escape sequence
      expect(diff_output).to include("\e[46m"),
                             "Expected cyan background (\\e[46m) for added leading spaces in: #{diff_output}"
    end
  end

  # Scenario: leading whitespace REMOVED (from 4 spaces to 2)
  # The removed 2 spaces should show blue bg
  describe "leading whitespace removal" do
    let(:xml1) do
      <<~XML
        <root>
          <p>    content</p>
        </root>
      XML
    end

    let(:xml2) do
      <<~XML
        <root>
          <p>  content</p>
        </root>
      XML
    end

    it "shows BLUE background on removed leading spaces" do
      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true,
        use_color: true,
        match: { text_content: :normalize, structural_whitespace: :normalize }
      )

      diff_output = result.diff(use_color: true)

      # The diff should show blue background for removed spaces
      expect(diff_output).to include("\e[44m"),
                             "Expected blue background (\\e[44m) for removed leading spaces in: #{diff_output}"
    end
  end

  # The REAL test: formatting-only continuation lines
  # In the ISO document, the continuation line (line 4249) shows:
  # [ | ░░░░░░░░░░░░░░░░░░be░reviewed░...
  # All the spaces are shown as ░ but they should have DIFFERENT backgrounds
  # for unchanged vs changed
  describe "continuation lines with mixed unchanged/changed spaces" do
    let(:xml1) do
      <<~XML
        <root>
          <p>Hello World</p>
        </root>
      XML
    end

    let(:xml2) do
      <<~XML
        <root>
          <p>Hello  World</p>
        </root>
      XML
    end

    it "differentiates unchanged vs changed intra-word spaces" do
      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true,
        use_color: true,
        match: { text_content: :normalize } # Don't normalize - we want to see the diff
      )

      diff_output = result.diff(use_color: true)

      # For a space change:
      # - If the space is INSERTED (exists in xml2 but not xml1): cyan bg
      # - If the space is REMOVED (exists in xml1 but not xml2): blue bg
      # - Unchanged spaces: no bg

      # At minimum, we should see SOME background color differentiation
      # if the space change is being detected properly
      has_cyan = diff_output.include?("\e[46m")
      has_blue = diff_output.include?("\e[44m")

      # We expect at least one of them to be true if the diff is working
      expect(has_cyan || has_blue).to be(true),
                                      "Expected at least cyan or blue background for space change. Diff: #{diff_output}"
    end
  end
end
