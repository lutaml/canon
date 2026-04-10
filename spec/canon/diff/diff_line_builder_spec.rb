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
        index1 = builder.send(:build_line_index, old_text.split("\n"))
        index2 = builder.send(:build_line_index, new_text.split("\n"))

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

  describe "continuation line char_ranges differentiation" do
    # Tests that continuation lines have char_ranges computed that correctly
    # differentiate unchanged vs changed_old vs changed_new portions

    it "creates char_ranges for changed continuation lines with unchanged content" do
      old_text = "prefix some  text\ncontinuation line\n"
      new_text = "prefix some   text\ncontinuation line\n"

      diff_node = Canon::Diff::DiffNode.new(node1: nil, node2: nil,
                                            dimension: :text_content, reason: "text changed")
      diff_node.normative = true

      diff_node.char_ranges = [
        Canon::Diff::DiffCharRange.new(line_number: 0, start_col: 0, end_col: 14,
                                       side: :old, status: :changed_old, role: :changed,
                                       diff_node: diff_node),
        Canon::Diff::DiffCharRange.new(line_number: 0, start_col: 0, end_col: 15,
                                       side: :new, status: :changed_new, role: :changed,
                                       diff_node: diff_node),
      ]
      diff_node.line_range_before = [0, 1]
      diff_node.line_range_after = [0, 1]

      lines = described_class.build([diff_node], old_text, new_text)

      cont_line = lines.find { |l| l.formatting? && l.type == :added }
      expect(cont_line).to be_a(Canon::Diff::DiffLine)
      expect(cont_line.has_char_ranges?).to be(true),
                                            "Continuation line should have char_ranges"

      old_ranges = cont_line.char_ranges
      new_ranges = cont_line.new_char_ranges

      expect(old_ranges).not_to be_empty
      expect(new_ranges).not_to be_empty

      old_ranges.each { |r| expect(r.status).to eq(:unchanged) }
      new_ranges.each { |r| expect(r.status).to eq(:unchanged) }
    end

    it "creates char_ranges for removed continuation lines" do
      # When a line is removed but continuation lines exist within line_range,
      # they should have char_ranges computed
      old_text = "line 0\nline 1 content\nline 2\n"
      new_text = "line 0\nline 1 content\n" # line 2 removed

      diff_node = Canon::Diff::DiffNode.new(
        node1: nil,
        node2: nil,
        dimension: :element_structure,
        reason: "element deleted",
      )
      diff_node.normative = true

      # char_ranges for line 1, but line_range_before spans lines 1-2
      diff_node.char_ranges = [
        Canon::Diff::DiffCharRange.new(
          line_number: 1,
          start_col: 0,
          end_col: 13,
          side: :old,
          status: :changed_old,
          role: :changed,
          diff_node: diff_node,
        ),
      ]
      diff_node.line_range_before = [1, 2]

      lines = described_class.build([diff_node], old_text, new_text)

      # Find the removed continuation line (line 2 is within line_range but not in new_text)
      cont_lines = lines.select { |l| l.type == :removed && l.formatting? }
      expect(cont_lines.length).to eq(1)

      cont_line = cont_lines.first
      expect(cont_line.has_char_ranges?).to be(true),
                                            "Removed continuation line should have char_ranges"

      # Since new_content is nil for line 2, the entire line is :changed_old
      old_ranges = cont_line.char_ranges
      expect(old_ranges).not_to be_empty
      old_ranges.each do |r|
        expect(r.status).to eq(:changed_old)
      end
    end

    it "creates char_ranges for added continuation lines" do
      # When a line is added and continuation lines exist, they should have char_ranges
      old_text = "line 0\nline 1 content\n"
      new_text = "line 0\nline 1 content\nline 2\n" # line 2 added

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
          end_col: 13,
          side: :new,
          status: :changed_new,
          role: :changed,
          diff_node: diff_node,
        ),
      ]
      diff_node.line_range_after = [1, 2]

      lines = described_class.build([diff_node], old_text, new_text)

      # Find the added continuation line
      cont_lines = lines.select { |l| l.type == :added && l.formatting? }
      expect(cont_lines.length).to eq(1)

      cont_line = cont_lines.first
      expect(cont_line.has_char_ranges?).to be(true),
                                            "Added continuation line should have char_ranges"

      # Since old_content is nil for line 2, the entire line is :changed_new
      new_ranges = cont_line.new_char_ranges
      expect(new_ranges).not_to be_empty
      new_ranges.each do |r|
        expect(r.status).to eq(:changed_new)
      end
    end

    it "differentiates unchanged vs changed portions in continuation with partial differences" do
      # When continuation content differs partially between old and new,
      # char_ranges should show common_prefix/:unchanged and changed portions
      # Note: This tests the TextDecomposer path where old and new both exist
      old_text = "prefix old continuation\nrest\n"
      new_text = "prefix new continuation\nrest\n" # only "continuation" changed

      diff_node = Canon::Diff::DiffNode.new(
        node1: nil,
        node2: nil,
        dimension: :text_content,
        reason: "text changed",
      )
      diff_node.normative = true

      diff_node.char_ranges = [
        Canon::Diff::DiffCharRange.new(
          line_number: 0,
          start_col: 0,
          end_col: 18,
          side: :old,
          status: :changed_old,
          role: :changed,
          diff_node: diff_node,
        ),
        Canon::Diff::DiffCharRange.new(
          line_number: 0,
          start_col: 0,
          end_col: 17,
          side: :new,
          status: :changed_new,
          role: :changed,
          diff_node: diff_node,
        ),
      ]
      diff_node.line_range_before = [0, 1]
      diff_node.line_range_after = [0, 1]

      lines = described_class.build([diff_node], old_text, new_text)

      # Find continuation lines
      removed_cont = lines.find { |l| l.type == :removed && l.formatting? }
      added_cont = lines.find { |l| l.type == :added && l.formatting? }

      expect(removed_cont).to be_a(Canon::Diff::DiffLine)
      expect(added_cont).to be_a(Canon::Diff::DiffLine)

      # Both should have char_ranges for proper differentiation
      expect(removed_cont.has_char_ranges?).to be(true)
      expect(added_cont.has_char_ranges?).to be(true)

      # "rest" is common prefix and suffix, so should be :unchanged
      # (The actual changed portion depends on TextDecomposer output)
      removed_cont.char_ranges.each do |r|
        expect(r.status).to be(:unchanged).or(be(:changed_old))
      end
      added_cont.new_char_ranges.each do |r|
        expect(r.status).to be(:unchanged).or(be(:changed_new))
      end
    end

    it "has char_ranges for continuation when both sides have content at same index" do
      # Continuation content exists at same index in both old and new
      old_text = "line 0\nchanged line\nline 2\n"
      new_text = "line 0\nchanged line\nline 2\n" # line 1 changed, line 2 unchanged

      diff_node = Canon::Diff::DiffNode.new(
        node1: nil,
        node2: nil,
        dimension: :text_content,
        reason: "text changed",
      )
      diff_node.normative = true

      diff_node.char_ranges = [
        Canon::Diff::DiffCharRange.new(
          line_number: 1,
          start_col: 0,
          end_col: 12,
          side: :old,
          status: :changed_old,
          role: :changed,
          diff_node: diff_node,
        ),
        Canon::Diff::DiffCharRange.new(
          line_number: 1,
          start_col: 0,
          end_col: 12,
          side: :new,
          status: :changed_new,
          role: :changed,
          diff_node: diff_node,
        ),
      ]
      diff_node.line_range_before = [1, 2]
      diff_node.line_range_after = [1, 2]

      lines = described_class.build([diff_node], old_text, new_text)

      # Find continuation lines (line 2 is unchanged but within line_range)
      removed_cont = lines.find { |l| l.type == :removed && l.formatting? }
      added_cont = lines.find { |l| l.type == :added && l.formatting? }

      expect(removed_cont).to be_a(Canon::Diff::DiffLine)
      expect(added_cont).to be_a(Canon::Diff::DiffLine)

      # Both should have char_ranges
      expect(removed_cont.has_char_ranges?).to be(true)
      expect(added_cont.has_char_ranges?).to be(true)

      # "line 2" exists at index 2 in both, so should be :unchanged
      removed_cont.char_ranges.each do |r|
        expect(r.status).to eq(:unchanged)
      end
      added_cont.new_char_ranges.each do |r|
        expect(r.status).to eq(:unchanged)
      end
    end

    it "differentiates leading whitespace in continuation lines when old has more leading spaces" do
      # When continuation has different leading whitespace (old has 18, new has 16),
      # char_ranges should show changed_old for the 2 removed leading spaces
      old_text = "prefix text\n                  be reviewed...\n"
      new_text = "prefix text\n                be reviewed...\n"

      diff_node = Canon::Diff::DiffNode.new(node1: nil, node2: nil,
                                            dimension: :text_content, reason: "text changed")
      diff_node.normative = true

      diff_node.char_ranges = [
        Canon::Diff::DiffCharRange.new(line_number: 0, start_col: 0, end_col: 12,
                                       side: :old, status: :changed_old, role: :changed,
                                       diff_node: diff_node),
        Canon::Diff::DiffCharRange.new(line_number: 0, start_col: 0, end_col: 12,
                                       side: :new, status: :changed_new, role: :changed,
                                       diff_node: diff_node),
      ]
      diff_node.line_range_before = [0, 1]
      diff_node.line_range_after = [0, 1]

      lines = described_class.build([diff_node], old_text, new_text)

      removed_cont = lines.find { |l| l.type == :removed && l.formatting? }
      added_cont = lines.find { |l| l.type == :added && l.formatting? }

      expect(removed_cont).to be_a(Canon::Diff::DiffLine)
      expect(added_cont).to be_a(Canon::Diff::DiffLine)
      expect(removed_cont.has_char_ranges?).to be(true)
      expect(added_cont.has_char_ranges?).to be(true)

      # Old continuation: 18 leading spaces, new has 16
      # First 16 spaces are common prefix (unchanged)
      # Last 2 spaces are "removed" (changed_old)
      old_changed_spaces = removed_cont.char_ranges.find do |r|
        r.status == :changed_old
      end
      expect(old_changed_spaces).not_to be_nil,
                                        "Old continuation should have changed_old status for removed leading spaces"
      expect(old_changed_spaces.start_col).to eq(16),
                                              "Changed_old should start after the 16 common spaces"

      # New continuation: 16 leading spaces
      # All 16 spaces are common prefix (unchanged) because new has FEWER spaces
      # No changed_new for leading spaces since new version has no extra spaces
      new_changed_spaces = added_cont.new_char_ranges.find do |r|
        r.status == :changed_new && r.start_col.zero?
      end
      expect(new_changed_spaces).to be_nil,
                                    "New continuation should NOT have changed_new for leading spaces when new has fewer"
    end
  end
end
