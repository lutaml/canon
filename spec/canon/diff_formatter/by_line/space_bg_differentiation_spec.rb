# frozen_string_literal: true

require "spec_helper"
require "canon/diff/diff_char_range" # Ensure DiffCharRange is loaded

RSpec.describe "Space Background Differentiation in Formatting Diffs" do
  # This spec tests that formatting-only diff lines properly differentiate
  # background colors for unchanged vs inserted vs removed spaces.
  #
  # When space visualization is ON (space -> ░):
  #   - Unchanged spaces: ░ with NO background
  #   - Inserted spaces: ░ with CYAN background
  #   - Removed spaces: ░ with BLUE background
  #
  # When space visualization is OFF:
  #   - Unchanged spaces: actual space with NO background
  #   - Inserted spaces: actual space with CYAN background
  #   - Removed spaces: actual space with BLUE background

  let(:formatter) do
    Canon::DiffFormatter::ByLine::XmlFormatter.new(
      use_color: true,
      context_lines: 3,
      visualization_map: visualization_map,
      show_diffs: :all,
    )
  end

  let(:visualization_map) do
    # Space visualization ON: space -> ░
    Canon::DiffFormatter::DEFAULT_VISUALIZATION_MAP.merge(" " => "░")
  end

  describe "render_formatting_line (lines without char_ranges)" do
    # When a formatting line has NO char_ranges, it goes through render_formatting_line
    # which applies uniform background to ALL spaces/░ characters

    it "applies CYAN background to all spaces on ] (added formatting) lines" do
      diff_line = Canon::Diff::DiffLine.new(
        line_number: 5,
        new_position: 6,
        content: "   added content",
        type: :added,
        formatting: true,
      )

      output = formatter.send(:render_formatting_line, diff_line, 6, :new, "]")

      # The output should contain ANSI escape sequences for cyan background (46)
      # Background colors in ANSI are 40-47 (black, red, green, yellow, blue, magenta, cyan, white)
      msg = "Expected cyan background (\\e[46m) on formatting ] line but got: #{output.inspect}"
      expect(output).to include("\e[46m"), msg
    end

    it "applies BLUE background to all spaces on [ (removed formatting) lines" do
      diff_line = Canon::Diff::DiffLine.new(
        line_number: 5,
        new_position: nil,
        content: "   removed content",
        type: :removed,
        formatting: true,
      )

      output = formatter.send(:render_formatting_line, diff_line, 5, :old, "[")

      # Blue background is \e[44m
      msg = "Expected blue background (\\e[44m) on formatting [ line but got: #{output.inspect}"
      expect(output).to include("\e[44m"), msg
    end
  end

  describe "render_line_from_char_ranges (lines with char_ranges)" do
    # When a formatting line HAS char_ranges, it goes through render_line_from_char_ranges
    # which differentiates: changed spaces get bg, unchanged spaces don't

    it "applies background only to CHANGED spaces, not unchanged" do
      # Create a diff line with char_ranges that distinguish changed vs unchanged
      diff_line = Canon::Diff::DiffLine.new(
        line_number: 5,
        new_position: 6,
        content: "  Hello World", # Two leading spaces (changed), then unchanged
        type: :added,
        formatting: true,
        char_ranges: [
          # Leading "  " is changed (added)
          Canon::Diff::DiffCharRange.new(
            line_number: 5, start_col: 0, end_col: 2,
            side: :new, status: :added, role: :changed
          ),
          # "Hello World" is unchanged
          Canon::Diff::DiffCharRange.new(
            line_number: 5, start_col: 2, end_col: 13,
            side: :new, status: :unchanged, role: :changed
          ),
        ],
      )

      output = formatter.send(:render_line_from_char_ranges,
                              diff_line.content, diff_line.char_ranges, :new,
                              formatting: true)

      # The output should have BLUE background on first 2 chars (░░) but NOT on rest
      # Unchanged "Hello World" should just be ░ characters without bg

      # Find all escape sequences
      sequences = output.scan(/\e\[[0-9;]*m/)
      bg_sequences = sequences.select do |s|
        s.include?("44") || s.include?("46")
      end

      msg = "Expected background sequences but found none. Output: #{output.inspect}"
      expect(bg_sequences).not_to be_empty, msg
    end

    it "does NOT apply background to unchanged spaces in formatting mode" do
      diff_line = Canon::Diff::DiffLine.new(
        line_number: 5,
        new_position: 6,
        content: "  Hello", # Leading spaces
        type: :added,
        formatting: true,
        char_ranges: [
          # First space is changed (added)
          Canon::Diff::DiffCharRange.new(
            line_number: 5, start_col: 0, end_col: 1,
            side: :new, status: :added, role: :changed
          ),
          # Second space is changed (added)
          Canon::Diff::DiffCharRange.new(
            line_number: 5, start_col: 1, end_col: 2,
            side: :new, status: :added, role: :changed
          ),
          # "Hello" is unchanged
          Canon::Diff::DiffCharRange.new(
            line_number: 5, start_col: 2, end_col: 7,
            side: :new, status: :unchanged, role: :after
          ),
        ],
      )

      output = formatter.send(:render_line_from_char_ranges,
                              diff_line.content, diff_line.char_ranges, :new,
                              formatting: true)

      # Count cyan background (\e[46m) sequences
      # Should have cyan bg for "  " (2 spaces/░) but NOT for "Hello"
      cyan_bg_count = output.scan("\e[46m").count

      msg = "Expected exactly 2 cyan bg sequences for 2 changed spaces, got #{cyan_bg_count}. Output: #{output.inspect}"
      expect(cyan_bg_count).to eq(2), msg

      # Verify "Hello" has NO background styling (no escape sequences around it)
      # After the last cyan bg, we should see "Hello" without \e[...m around it
      hello_section = output.split("\e[0m").last
      msg2 = "Expected 'Hello' to be present after background styling"
      expect(hello_section).to include("Hello"), msg2
    end
  end
end
