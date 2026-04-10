# frozen_string_literal: true

require "spec_helper"
require "canon/diff_formatter/by_line/line_renderers"
require "canon/diff_formatter/theme"

RSpec.describe Canon::DiffFormatter::ByLine do
  describe Canon::DiffFormatter::ByLine::ReflowSummaryLineRenderer do
    subject(:renderer) do
      described_class.new(
        theme: theme,
        use_color: use_color,
        line_num_width: line_num_width,
      )
    end

    let(:theme) { Canon::DiffFormatter::Theme[:dark] }
    let(:use_color) { true }
    let(:line_num_width) { 4 }

    describe "rendering with color" do
      let(:diff_line) do
        Canon::Diff::DiffLine.new(
          line_number: 5,
          new_position: 8,
          content: "... 23 more removed (formatting only) ...",
          type: :reflow_summary,
          formatting: true,
        )
      end

      it "uses theme formatting color (bright_blue for dark theme)" do
        output = renderer.render(diff_line)
        # bright_blue = blue (34) + bold (1)
        expect(output).to include("\e[34m\e[1m")
      end

      it "shows both old and new line numbers with pipes" do
        # line_number: 5 → old_num: 6, new_position: 8 → new_num: 9
        output = renderer.render(diff_line)
        # Format is "   6|   9| ..." so both numbers appear distinctly
        expect(output).to include("6")
        expect(output).to include("9")
      end

      it "includes the content" do
        output = renderer.render(diff_line)
        expect(output).to include("... 23 more removed (formatting only) ...")
      end
    end

    describe "rendering without color" do
      let(:use_color) { false }

      let(:diff_line) do
        Canon::Diff::DiffLine.new(
          line_number: 5,
          content: "... 23 more removed (formatting only) ...",
          type: :reflow_summary,
          formatting: true,
        )
      end

      it "outputs plain text without ANSI codes" do
        output = renderer.render(diff_line)
        expect(output).not_to include("\e[")
        # Format is "    |     | ..." with spaces around pipes
        expect(output).to include("|")
        expect(output).to include("... 23 more removed (formatting only) ...")
      end
    end

    describe "theme variations" do
      it "uses bright_blue for light theme formatting content" do
        light_theme = Canon::DiffFormatter::Theme[:light]
        light_renderer = described_class.new(
          theme: light_theme,
          use_color: true,
          line_num_width: 4,
        )
        diff_line = Canon::Diff::DiffLine.new(
          line_number: 0,
          content: "... 5 more added (formatting only) ...",
          type: :reflow_summary,
          formatting: true,
        )
        output = light_renderer.render(diff_line)
        # light theme uses bright_blue (blue + bold)
        expect(output).to include("\e[34m\e[1m")
      end

      it "uses green for cyberpunk theme formatting content" do
        cyberpunk_theme = Canon::DiffFormatter::Theme[:cyberpunk]
        cyberpunk_renderer = described_class.new(
          theme: cyberpunk_theme,
          use_color: true,
          line_num_width: 4,
        )
        diff_line = Canon::Diff::DiffLine.new(
          line_number: 0,
          content: "... 5 more added (formatting only) ...",
          type: :reflow_summary,
          formatting: true,
        )
        output = cyberpunk_renderer.render(diff_line)
        # cyberpunk theme uses green (32) for formatting content
        expect(output).to include("\e[32m")
      end

      it "uses yellow for retro theme formatting content" do
        retro_theme = Canon::DiffFormatter::Theme[:retro]
        retro_renderer = described_class.new(
          theme: retro_theme,
          use_color: true,
          line_num_width: 4,
        )
        diff_line = Canon::Diff::DiffLine.new(
          line_number: 0,
          content: "... 5 more added (formatting only) ...",
          type: :reflow_summary,
          formatting: true,
        )
        output = retro_renderer.render(diff_line)
        # retro theme uses yellow (33) for formatting content
        expect(output).to include("\e[33m")
      end
    end
  end

  describe Canon::DiffFormatter::ByLine::LineRendererFactory do
    describe "#for_line" do
      let(:factory) do
        described_class.new(
          theme: Canon::DiffFormatter::Theme[:dark],
          use_color: true,
          line_num_width: 4,
        )
      end

      it "creates ReflowSummaryLineRenderer for :reflow_summary lines" do
        diff_line = Canon::Diff::DiffLine.new(
          line_number: 0,
          content: "...",
          type: :reflow_summary,
        )
        renderer = factory.for_line(diff_line)
        expect(renderer).to be_a(Canon::DiffFormatter::ByLine::ReflowSummaryLineRenderer)
      end

      it "creates UnchangedLineRenderer for :unchanged lines" do
        diff_line = Canon::Diff::DiffLine.new(
          line_number: 0,
          content: "<root>",
          type: :unchanged,
        )
        renderer = factory.for_line(diff_line)
        expect(renderer).to be_a(Canon::DiffFormatter::ByLine::UnchangedLineRenderer)
      end

      it "creates RemovedLineRenderer for :removed lines" do
        diff_line = Canon::Diff::DiffLine.new(
          line_number: 0,
          content: "<item>",
          type: :removed,
        )
        renderer = factory.for_line(diff_line)
        expect(renderer).to be_a(Canon::DiffFormatter::ByLine::RemovedLineRenderer)
      end

      it "creates AddedLineRenderer for :added lines" do
        diff_line = Canon::Diff::DiffLine.new(
          line_number: 0,
          content: "<item>",
          type: :added,
        )
        renderer = factory.for_line(diff_line)
        expect(renderer).to be_a(Canon::DiffFormatter::ByLine::AddedLineRenderer)
      end

      it "raises ArgumentError for unknown line types" do
        diff_line = Canon::Diff::DiffLine.new(
          line_number: 0,
          content: "<root>",
          type: :unknown_type,
        )
        expect { factory.for_line(diff_line) }.to raise_error(ArgumentError)
      end
    end
  end

  describe Canon::DiffFormatter::ByLine::UnchangedLineRenderer do
    subject(:renderer) do
      described_class.new(
        theme: Canon::DiffFormatter::Theme[:dark],
        use_color: true,
        line_num_width: 4,
      )
    end

    it "renders unchanged line with both line numbers" do
      diff_line = Canon::Diff::DiffLine.new(
        line_number: 2,
        new_position: 3,
        content: "<root>",
        type: :unchanged,
      )
      output = renderer.render(diff_line)
      # Line numbers are formatted as "   3" (4 chars padded)
      # Check the raw number appears in the output
      expect(output).to include("3")
      expect(output).to include("<root>")
    end
  end

  describe Canon::DiffFormatter::ByLine::RemovedLineRenderer do
    subject(:renderer) do
      described_class.new(
        theme: Canon::DiffFormatter::Theme[:dark],
        use_color: true,
        line_num_width: 4,
      )
    end

    describe "formatting-only removal" do
      it "uses bright_blue for formatting content" do
        diff_line = Canon::Diff::DiffLine.new(
          line_number: 2,
          content: "<item>",
          type: :removed,
          formatting: true,
        )
        output = renderer.render(diff_line)
        # bright_blue = blue (34) + bold (1)
        expect(output).to include("\e[34m\e[1m")
      end
    end

    describe "normative removal" do
      it "uses red for removed content" do
        diff_line = Canon::Diff::DiffLine.new(
          line_number: 2,
          content: "<item>old</item>",
          type: :removed,
        )
        output = renderer.render(diff_line)
        # red = 31
        expect(output).to include("\e[31m")
      end
    end
  end

  describe Canon::DiffFormatter::ByLine::AddedLineRenderer do
    subject(:renderer) do
      described_class.new(
        theme: Canon::DiffFormatter::Theme[:dark],
        use_color: true,
        line_num_width: 4,
      )
    end

    describe "formatting-only addition" do
      it "uses bright_blue for formatting content" do
        diff_line = Canon::Diff::DiffLine.new(
          line_number: 2,
          content: "<item>",
          type: :added,
          formatting: true,
        )
        output = renderer.render(diff_line)
        # bright_blue = blue (34) + bold (1)
        expect(output).to include("\e[34m\e[1m")
      end
    end

    describe "normative addition" do
      it "uses green for added content" do
        diff_line = Canon::Diff::DiffLine.new(
          line_number: 2,
          content: "<item>new</item>",
          type: :added,
        )
        output = renderer.render(diff_line)
        # green = 32
        expect(output).to include("\e[32m")
      end
    end
  end
end
