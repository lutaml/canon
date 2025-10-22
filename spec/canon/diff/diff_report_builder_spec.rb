# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Diff::DiffReportBuilder do
  let(:diff_node_normative) do
    Canon::Diff::DiffNode.new(
      node1: "old",
      node2: "new",
      dimension: :text_content,
      reason: "Text differs",
    ).tap { |node| node.normative = true }
  end

  let(:diff_node_informative) do
    Canon::Diff::DiffNode.new(
      node1: "a='1' b='2'",
      node2: "b='2' a='1'",
      dimension: :attribute_order,
      reason: "Order differs",
    ).tap { |node| node.normative = false }
  end

  describe ".build" do
    context "with empty diff lines" do
      it "returns empty report" do
        report = described_class.build([])

        expect(report).to be_a(Canon::Diff::DiffReport)
        expect(report.contexts).to be_empty
        expect(report).not_to have_differences
      end
    end

    context "with only unchanged lines" do
      it "returns empty report" do
        diff_lines = Array.new(5) do |i|
          Canon::Diff::DiffLine.new(
            line_number: i,
            type: :unchanged,
            content: "line #{i}",
          )
        end

        report = described_class.build(diff_lines)

        expect(report.contexts).to be_empty
        expect(report).not_to have_differences
      end
    end

    context "with normative diff lines" do
      it "creates report with contexts" do
        diff_lines = Array.new(10) do |i|
          Canon::Diff::DiffLine.new(
            line_number: i,
            type: i == 5 ? :removed : :unchanged,
            content: "line #{i}",
            diff_node: i == 5 ? diff_node_normative : nil,
          )
        end

        report = described_class.build(diff_lines, context_lines: 2)

        expect(report).to have_differences
        expect(report.context_count).to eq(1)
        expect(report.contexts[0].start_idx).to eq(3) # 5 - 2
        expect(report.contexts[0].end_idx).to eq(7)   # 5 + 2
      end
    end

    context "with show_diffs: :normative" do
      it "filters out informative diffs" do
        diff_lines = Array.new(10) do |i|
          type = [3, 7].include?(i) ? :removed : :unchanged
          node = if i == 3
                   diff_node_informative
                 elsif i == 7
                   diff_node_normative
                 end

          Canon::Diff::DiffLine.new(
            line_number: i,
            type: type,
            content: "line #{i}",
            diff_node: node,
          )
        end

        report = described_class.build(diff_lines,
                                       show_diffs: :normative,
                                       context_lines: 1)

        expect(report.context_count).to eq(1)
        expect(report.block_count).to eq(1)
        # Should only have the normative block at line 7
        expect(report.contexts[0].blocks[0].start_idx).to eq(7)
      end
    end

    context "with show_diffs: :informative" do
      it "filters out normative diffs" do
        diff_lines = Array.new(10) do |i|
          type = [3, 7].include?(i) ? :removed : :unchanged
          node = if i == 3
                   diff_node_informative
                 elsif i == 7
                   diff_node_normative
                 end

          Canon::Diff::DiffLine.new(
            line_number: i,
            type: type,
            content: "line #{i}",
            diff_node: node,
          )
        end

        report = described_class.build(diff_lines,
                                       show_diffs: :informative,
                                       context_lines: 1)

        expect(report.context_count).to eq(1)
        expect(report.block_count).to eq(1)
        # Should only have the informative block at line 3
        expect(report.contexts[0].blocks[0].start_idx).to eq(3)
      end
    end

    context "with show_diffs: :all" do
      it "includes all diffs" do
        diff_lines = Array.new(10) do |i|
          type = [3, 7].include?(i) ? :removed : :unchanged
          node = if i == 3
                   diff_node_informative
                 elsif i == 7
                   diff_node_normative
                 end

          Canon::Diff::DiffLine.new(
            line_number: i,
            type: type,
            content: "line #{i}",
            diff_node: node,
          )
        end

        report = described_class.build(diff_lines,
                                       show_diffs: :all,
                                       context_lines: 1,
                                       grouping_lines: nil)

        expect(report.context_count).to eq(2)
        expect(report.block_count).to eq(2)
      end
    end

    context "with grouping_lines option" do
      it "groups nearby contexts" do
        diff_lines = Array.new(20) do |i|
          type = [5, 8].include?(i) ? :removed : :unchanged
          node = [5, 8].include?(i) ? diff_node_normative : nil

          Canon::Diff::DiffLine.new(
            line_number: i,
            type: type,
            content: "line #{i}",
            diff_node: node,
          )
        end

        # Gap between blocks: 8 - 5 - 1 = 2 lines
        # With grouping_lines: 3, they should be grouped
        report = described_class.build(diff_lines,
                                       context_lines: 1,
                                       grouping_lines: 3)

        expect(report.context_count).to eq(1)
        expect(report.contexts[0].blocks.length).to eq(2)
      end
    end

    context "with custom element and file names" do
      it "sets them in the report" do
        diff_lines = [
          Canon::Diff::DiffLine.new(
            line_number: 0,
            type: :removed,
            content: "old",
            diff_node: diff_node_normative,
          ),
        ]

        report = described_class.build(
          diff_lines,
          element_name: "mydoc",
          file1_name: "expected.xml",
          file2_name: "actual.xml",
        )

        expect(report.element_name).to eq("mydoc")
        expect(report.file1_name).to eq("expected.xml")
        expect(report.file2_name).to eq("actual.xml")
      end
    end

    context "pipeline integration" do
      it "correctly flows through all layers" do
        # Create a realistic scenario with multiple blocks
        diff_lines = Array.new(30) do |i|
          type = [5, 8, 20].include?(i) ? :removed : :unchanged
          node = [5, 8, 20].include?(i) ? diff_node_normative : nil

          Canon::Diff::DiffLine.new(
            line_number: i,
            type: type,
            content: "line #{i}",
            diff_node: node,
          )
        end

        report = described_class.build(
          diff_lines,
          show_diffs: :normative,
          context_lines: 2,
          grouping_lines: 5,
        )

        # Verify the pipeline worked correctly
        expect(report).to have_differences

        # Lines 5 and 8 are close (gap = 2), should be grouped
        # Line 20 is far (gap = 11), should be separate
        expect(report.context_count).to eq(2)

        # First context should have 2 blocks
        expect(report.contexts[0].blocks.length).to eq(2)

        # Second context should have 1 block
        expect(report.contexts[1].blocks.length).to eq(1)

        # Verify summary
        expect(report.block_count).to eq(3)
      end
    end

    context "with mixed normative/informative blocks and filtering" do
      it "maintains correct normative/informative state through pipeline" do
        diff_lines = Array.new(20) do |i|
          type = [5, 10, 15].include?(i) ? :removed : :unchanged
          node = case i
                 when 5  then diff_node_normative
                 when 10 then diff_node_informative
                 when 15 then diff_node_normative
                 end

          Canon::Diff::DiffLine.new(
            line_number: i,
            type: type,
            content: "line #{i}",
            diff_node: node,
          )
        end

        # Build with show_diffs: :normative
        normative_report = described_class.build(
          diff_lines,
          show_diffs: :normative,
          context_lines: 1,
        )

        # Should only have 2 contexts (at 5 and 15)
        expect(normative_report.context_count).to eq(2)
        expect(normative_report.block_count).to eq(2)

        # Build with show_diffs: :all
        all_report = described_class.build(
          diff_lines,
          show_diffs: :all,
          context_lines: 1,
        )

        # Should have 3 contexts (at 5, 10, and 15)
        expect(all_report.context_count).to eq(3)
        expect(all_report.block_count).to eq(3)
      end
    end

    context "regression: Issue 1 - informative diffs filtering" do
      it "filters out all-informative contexts when show_diffs: :normative" do
        # Simulate the scenario from Issue 1
        diff_lines = Array.new(100) do |i|
          # Lines 10-50 are informative diffs
          # Lines 60-65 are normative diffs
          type = (10..50).cover?(i) || (60..65).cover?(i) ? :removed : :unchanged
          node = if (10..50).cover?(i)
                   diff_node_informative
                 elsif (60..65).cover?(i)
                   diff_node_normative
                 end

          Canon::Diff::DiffLine.new(
            line_number: i,
            type: type,
            content: "line #{i}",
            diff_node: node,
          )
        end

        report = described_class.build(
          diff_lines,
          show_diffs: :normative,
          context_lines: 3,
        )

        # Should only have 1 context (the normative one at 60-65)
        expect(report.context_count).to eq(1)
        expect(report.contexts[0]).to be_normative

        # Verify no informative diffs are in the report
        report.contexts.each do |context|
          expect(context).not_to be_informative
        end
      end
    end

    context "regression: Issue 2 - empty diff output" do
      it "returns empty report when only informative diffs exist with show_diffs: :normative" do
        diff_lines = Array.new(20) do |i|
          type = (5..15).cover?(i) ? :removed : :unchanged
          node = (5..15).cover?(i) ? diff_node_informative : nil

          Canon::Diff::DiffLine.new(
            line_number: i,
            type: type,
            content: "line #{i}",
            diff_node: node,
          )
        end

        report = described_class.build(
          diff_lines,
          show_diffs: :normative,
        )

        # Should be empty (no normative diffs)
        expect(report.contexts).to be_empty
        expect(report).not_to have_differences
        expect(report.context_count).to eq(0)
        expect(report.block_count).to eq(0)
      end
    end
  end
end
