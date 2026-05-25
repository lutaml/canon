# frozen_string_literal: true

require "spec_helper"
require "canon/diff/diff_line_builder"
require "canon/diff/diff_char_range"

RSpec.describe Canon::Diff::DiffLineBuilder do
  describe "build" do
    let(:old_text) do
      <<~TEXT
        line 0
        line 1
        line 2
        line 3
        line 4
        line 5
        line 6
        line 7
        line 8
        line 9
      TEXT
    end

    let(:new_text) do
      <<~TEXT
        line 0
        modified line 1
        line 2
        line 3
        line 4
        inserted line 5
        line 6
        line 7
        line 8
        line 9
      TEXT
    end

    it "builds diff lines from enriched diff nodes" do
      # Create a diff node for the modified line 1
      diff_node = Canon::Diff::DiffNode.new(
        node1: nil,
        node2: nil,
        dimension: :text_content,
        reason: "text changed",
      )
      diff_node.normative = true

      # Enrich with char_ranges pointing to line 1 in both texts
      diff_node.char_ranges = [
        Canon::Diff::DiffCharRange.new(
          line_number: 1,
          start_col: 0,
          end_col: 14,
          side: :old,
          status: :changed_old,
          role: :changed,
          diff_node: diff_node,
        ),
      ]
      diff_node.line_range_before = [1, 1]
      diff_node.line_range_after = [1, 1]

      lines = described_class.build([diff_node], old_text, new_text)

      # Should produce diff lines including the changed region
      expect(lines).not_to be_empty
      # The lines should include context around the change
      line_numbers = lines.map(&:line_number)
      expect(line_numbers).to include(1)
    end

    describe "line indices" do
      it "builds reverse index for old_text and new_text" do
        builder = described_class.new([], old_text, new_text)

        # Access the reverse indices via the build_line_index method
        index1 = builder.build_line_index(old_text.split("\n"))
        index2 = builder.build_line_index(new_text.split("\n"))

        expect(index1).to be_a(Hash)
        expect(index2).to be_a(Hash)

        # "line 1" should appear at index 1 in text1
        # Note: split("\n") removes trailing newline, so keys don't have "\n"
        expect(index1["line 1"]).to eq([1])
        expect(index2["line 1"]).to be_empty
        expect(index2["modified line 1"]).to eq([1])
      end
    end
  end

  describe "emit_removed_lines continuation handling" do
    it "emits continuation lines when line_range extends beyond char_ranges" do
      # Simulate a multi-line element where char_ranges only covers the first line
      # but line_range_before indicates the element spans multiple lines
      old_text = "line 0\nline 1\nline 2\nline 3\n"
      new_text = "line 0\nline 2\nline 3\n" # line 1 removed

      diff_node = Canon::Diff::DiffNode.new(
        node1: nil,
        node2: nil,
        dimension: :element_structure,
        reason: "element deleted",
      )
      diff_node.normative = true

      # char_ranges only on line 1, but line_range_before spans lines 1-2
      diff_node.char_ranges = [
        Canon::Diff::DiffCharRange.new(
          line_number: 1,
          start_col: 0,
          end_col: 6,
          side: :old,
          status: :changed_old,
          role: :changed,
          diff_node: diff_node,
        ),
      ]
      diff_node.line_range_before = [1, 2] # element spans lines 1-2

      lines = described_class.build([diff_node], old_text, new_text)

      # Should have a removed line for line 1 (with diff_node)
      removed_lines = lines.select { |l| l.type == :removed && !l.formatting? }
      expect(removed_lines.length).to eq(1)
      expect(removed_lines.first.line_number).to eq(1)

      # Should have a formatting continuation line for line 2 (within line_range but no char_range)
      cont_lines = lines.select { |l| l.type == :removed && l.formatting? }
      expect(cont_lines.length).to eq(1)
      expect(cont_lines.first.line_number).to eq(2)
    end
  end

  describe "emit_added_lines continuation handling" do
    it "emits continuation lines when line_range extends beyond char_ranges" do
      old_text = "line 0\nline 2\nline 3\n"
      new_text = "line 0\nline 1\nline 2\nline 3\n" # line 1 inserted

      diff_node = Canon::Diff::DiffNode.new(
        node1: nil,
        node2: nil,
        dimension: :element_structure,
        reason: "element added",
      )
      diff_node.normative = true

      diff_node.char_ranges = [
        Canon::Diff::DiffCharRange.new(
          line_number: 1,
          start_col: 0,
          end_col: 6,
          side: :new,
          status: :added,
          role: :changed,
          diff_node: diff_node,
        ),
      ]
      diff_node.line_range_after = [1, 2]

      lines = described_class.build([diff_node], old_text, new_text)

      added_lines = lines.select { |l| l.type == :added && !l.formatting? }
      expect(added_lines.length).to eq(1)
      expect(added_lines.first.line_number).to eq(1)

      cont_lines = lines.select { |l| l.type == :added && l.formatting? }
      expect(cont_lines.length).to eq(1)
      expect(cont_lines.first.line_number).to eq(2)
    end
  end

  describe "orphaned content detection in gaps" do
    it "does not emit lines without diff_nodes when content doesn't exist in other text" do
      # old_text has extra lines that don't exist in new_text
      old_text = "common\nunique1\nunique2\ncommon_end\n"
      new_text = "common\ncommon_end\n"

      # Create a diff at position 0 (Before the gap)
      diff_node = Canon::Diff::DiffNode.new(
        node1: nil,
        node2: nil,
        dimension: :text_content,
        reason: "dummy",
      )
      diff_node.normative = true
      diff_node.char_ranges = [
        Canon::Diff::DiffCharRange.new(
          line_number: 0,
          start_col: 0,
          end_col: 6,
          side: :old,
          status: :changed_old,
          role: :changed,
          diff_node: diff_node,
        ),
        Canon::Diff::DiffCharRange.new(
          line_number: 0,
          start_col: 0,
          end_col: 6,
          side: :new,
          status: :changed_new,
          role: :changed,
          diff_node: diff_node,
        ),
      ]
      diff_node.line_range_before = [0, 0]
      diff_node.line_range_after = [0, 0] # "common" exists in text2 at line 0

      lines = described_class.build([diff_node], old_text, new_text)

      # unique1 and unique2 don't exist in new_text at all.
      # We should NOT emit them as formatting-only lines without diff_nodes.
      # Only emit_reflow_summary should be used for untracked gaps.
      removed_lines = lines.select { |l| l.type == :removed }
      expect(removed_lines.length).to eq(0)
      # The gap should produce a reflow summary since we can't emit without diff_nodes
      summary_lines = lines.select { |l| l.type == :reflow_summary }
      expect(summary_lines.length).to eq(1)
    end

    it "marks gap content as unchanged when it exists in both texts" do
      # content exists in both texts but at different line positions
      old_text = "common\nalpha\nbeta\ncommon_end\n"
      new_text = "common\ngamma\nalpha\nbeta\ncommon_end\n"
      # alpha and beta are in both, just at different positions

      diff_node = Canon::Diff::DiffNode.new(
        node1: nil,
        node2: nil,
        dimension: :text_content,
        reason: "dummy",
      )
      diff_node.normative = true
      diff_node.char_ranges = [
        Canon::Diff::DiffCharRange.new(
          line_number: 0,
          start_col: 0,
          end_col: 6,
          side: :old,
          status: :changed_old,
          role: :changed,
          diff_node: diff_node,
        ),
      ]
      diff_node.line_range_before = [0, 0]

      lines = described_class.build([diff_node], old_text, new_text)

      # alpha and beta should be found as unchanged (they exist in new_text at different positions)
      unchanged_lines = lines.select { |l| l.type == :unchanged }
      # gamma only in new_text - should be :added
      added_lines = lines.select { |l| l.type == :added }

      # alpha and beta should be in unchanged (they exist in new_text)
      expect(unchanged_lines.map(&:content)).to include("alpha", "beta")
      # gamma should be in added
      expect(added_lines.map(&:content)).to include("gamma")
    end
  end
end
