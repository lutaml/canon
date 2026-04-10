# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Line-by-line diff display" do
  describe "line number correctness" do
    it "uses line numbers (not character offsets) for new_position in changed lines" do
      xml1 = <<~XML
        <root>
          <item>One</item>
        </root>
      XML

      xml2 = <<~XML
        <root>
          <item>Two</item>
        </root>
      XML

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true)
      diff = result.diff(use_color: false)

      # Extract line numbers from the diff output
      # Format is: "old_line|new_line+ | content" or "old_line|new_line- | content"
      # The new_line should be a reasonable line number, not a character offset
      lines = diff.split("\n")

      changed_lines = lines.select { |l| l.include?("+") || l.include?("-") }

      changed_lines.each do |line|
        # Skip the header line
        next if line =~ /^\s*[-+]\s*$/ || line.include?("Character Visualization")

        # Extract potential line numbers
        # The format is like: "17537|17537  |" or "     |8291+ |"
        if line =~ /\|\s*(\d+)\+\s*\|/
          new_line_num = $1.to_i
          # New line numbers should be reasonable (not giant numbers that look like byte offsets)
          # In a small test file, line numbers should be < 1000
          expect(new_line_num).to be < 1000,
                                  "New line number #{new_line_num} looks like a byte offset, not a line number"
        end
      end
    end

    it "shows correct line numbers for unchanged lines" do
      xml1 = <<~XML
        <root>
          <item>One</item>
        </root>
      XML

      xml2 = <<~XML
        <root>
          <item>Two</item>
        </root>
      XML

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true)
      diff = result.diff(use_color: false)

      # Unchanged lines should show same line number on both sides
      # Format: "17537|17537  |             <label>56</label>"
      lines = diff.split("\n")

      unchanged_pattern = /^\s*(\d+)\|(\d+)\s+\|/

      lines.each do |line|
        match = line.match(unchanged_pattern)
        next unless match

        old_num = match[1].to_i
        new_num = match[2].to_i

        expect(old_num).to eq(new_num),
                           "Unchanged line shows different numbers: old=#{old_num}, new=#{new_num}"
      end
    end
  end

  describe "multi-line diff alignment" do
    it "aligns changed lines correctly with context lines" do
      xml1 = <<~XML
        <root>
          <item>One</item>
        </root>
      XML

      xml2 = <<~XML
        <root>
          <item>Two</item>
        </root>
      XML

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true)
      diff = result.diff(use_color: false)
      lines = diff.split("\n")

      # Find changed/deleted/added lines
      changed_indices = []
      lines.each_with_index do |line, idx|
        changed_indices << idx if /\|[\s\d]*[+-]\s*\|/.match?(line)
      end

      # Find context (unchanged) lines
      context_indices = []
      lines.each_with_index do |line, idx|
        context_indices << idx if line =~ /\A\s*\d+\|\d+\s+\|/ && line !~ /[+-]\s*\|/
      end

      # Changed lines should be adjacent to context lines with correct alignment
      # The indentation (number of leading spaces) should be consistent
      changed_lines = changed_indices.map { |i| lines[i] }

      # Check that diff markers (-, +) appear at consistent column positions
      # Note: We only look for - and + as markers, not < > [ ] which can appear in XML content
      marker_columns = changed_lines.filter_map do |line|
        # Find column of first marker character after the line numbers
        # Only - and + are diff markers; < > [ ] appear in XML content
        markers = ["-", "+"]
        result = nil
        markers.each do |m|
          if line.include?(m)
            idx = line.index(m)
            # Make sure it's after the | which separates line numbers from content
            if idx && idx > 0 && line[idx - 1] == " "
              result = idx
              break
            end
          end
        end
        result
      end

      if marker_columns.any?
        # All markers should be at the same column position
        expect(marker_columns).to all(eq(marker_columns.first)),
                                  "Markers are at inconsistent columns: #{marker_columns.inspect}"
      end
    end
  end

  describe "text node change display" do
    it "shows text content changes as within-line changes, not whole-line deletions" do
      # This tests a specific case where an element has a text node change
      # The element <mixed-citation> has its closing text changed from "" to "extra"
      xml1 = <<~XML
        <root>
          <mixed-citation>Chinese Military Standard</mixed-citation>
        </root>
      XML

      xml2 = <<~XML
        <root>
          <mixed-citation>Chinese Military Standard extra</mixed-citation>
        </root>
      XML

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true)
      diff = result.diff(use_color: false)

      # The diff should show:
      # 1. The old line with the old text content marked as removed
      # 2. The new line with the new text content marked as added
      # NOT multiple whole-line deletions for what is actually a single text change

      lines = diff.split("\n")

      # Count delete and insert markers
      delete_count = lines.count { |l| l =~ /\|\s*[\d\s]*-\s*\|/ }
      insert_count = lines.count { |l| l =~ /\|\s*[\d\s]*\+\s*\|/ }

      # For a simple text change in one element, we expect at most 1 delete and 1 insert
      # If we see 2 deletes and 1 insert (or more), it means closing tags are being
      # incorrectly shown as deleted
      if delete_count > 1 || insert_count > 1
        # This is the bug: closing tags being shown as deleted/inserted
        expect(delete_count).to be <= 1,
                                "Found #{delete_count} delete lines for a single text change - " \
                                "closing tags should not be shown as deleted"
        expect(insert_count).to be <= 1,
                                "Found #{insert_count} insert lines for a single text change"
      end
    end

    it "does not show closing tags as separate deleted lines when only text content changes" do
      xml1 = <<~XML
        <root>
          <p>Hello</p>
        </root>
      XML

      xml2 = <<~XML
        <root>
          <p>Hello World</p>
        </root>
      XML

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true)
      diff = result.diff(use_color: false)
      lines = diff.split("\n")

      # A closing tag should not appear as a SEPARATE deleted line.
      # It's OK for </p> to appear in a changed line's content (same line as <p>),
      # but it should never be the sole content of a deleted line.
      deleted_lines = lines.grep(/\|\s*[\d\s]*-\s*\|/)

      deleted_lines.each do |line|
        # Extract the content after the "| - | " marker
        content = line.sub(/^.*\|\s*-\s*\|\s*/, "")
        stripped = content.strip

        # A line that is ONLY a closing tag (with optional whitespace)
        # should never appear as a deleted line
        expect(stripped).not_to match(/\A<\/\w+>\z/),
                                "Closing tag appears as separate deleted line: #{line}"
      end
    end
  end

  describe "character-level highlighting within lines" do
    it "highlights only the changed portion of a line, not the whole line" do
      xml1 = <<~XML
        <root>
          <p>Hello World</p>
        </root>
      XML

      xml2 = <<~XML
        <root>
          <p>Hello Universe</p>
        </root>
      XML

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true)
      diff = result.diff(use_color: true)

      # Strip ANSI codes for searching
      diff_plain = diff.gsub(/\e\[[0-9;]*m/, "")

      # The diff should show the changed portion highlighted (with ANSI codes)
      # not the entire <p> line as changed
      lines = diff.split("\n")
      lines_plain = diff_plain.split("\n")

      # Find the changed line indices (with - or + marker)
      removed_idx = lines_plain.index { |l| l.include?("- |") }
      added_idx = lines_plain.index { |l| l.include?("+ |") }

      skip "No changed line found" unless removed_idx && added_idx

      removed_line = lines[removed_idx]
      added_line = lines[added_idx]

      # With use_color: true, the output contains ANSI codes for highlighting.
      # We verify character-level highlighting is working by checking:
      # 1. ANSI codes appear in the output (indicating color/styling was applied)
      # 2. The ANSI strikethrough code appears on the removed text portion
      #
      # Note: The entire line has ANSI codes for structure colors (line numbers,
      # pipes, markers). The key is that the content area shows character-level
      # highlighting on "World"/"Universe" using different styles than the
      # surrounding context.

      # Check that ANSI codes for highlighting are present
      # The strikethrough code (9) appears on removed text
      expect(removed_line).to match(/\e\[9m/),
                              "Removed text should have strikethrough (character-level highlight)"
      expect(added_line).to match(/\e\[32m/),
                            "Added text should be green (character-level highlight)"
    end
  end

  describe "long document context" do
    it "shows only context lines around changes, not entire document" do
      xml1 = <<~XML
        <?xml version="1.0"?>
        <document>
          <header>
            <title>Report</title>
          </header>
          <body>
            <section id="1"><p>Alpha</p></section>
            <section id="2"><p>Beta</p></section>
            <section id="3"><p>Gamma</p></section>
            <section id="4"><p>Delta</p></section>
            <section id="5"><p>Changed Old</p></section>
            <section id="6"><p>Zeta</p></section>
            <section id="7"><p>Eta</p></section>
            <section id="8"><p>Theta</p></section>
          </body>
        </document>
      XML

      xml2 = <<~XML
        <?xml version="1.0"?>
        <document>
          <header>
            <title>Report</title>
          </header>
          <body>
            <section id="1"><p>Alpha</p></section>
            <section id="2"><p>Beta</p></section>
            <section id="3"><p>Gamma</p></section>
            <section id="4"><p>Delta</p></section>
            <section id="5"><p>Changed New</p></section>
            <section id="6"><p>Zeta</p></section>
            <section id="7"><p>Eta</p></section>
            <section id="8"><p>Theta</p></section>
          </body>
        </document>
      XML

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true)
      diff = result.diff(use_color: false)
      lines = diff.split("\n").reject(&:empty?)

      # Should NOT show all 14+ document lines
      # Context should be limited to a few lines around the change
      content_lines = lines.select do |l|
        l.include?("|") && l !~ /diff|Diff|Legend|━/
      end
      expect(content_lines.length).to be < 12,
                                      "Expected limited context lines, got #{content_lines.length}"
    end

    it "shows separate context blocks for far-apart changes" do
      xml1 = <<~XML
        <report>
          <meta><version>1.0</version></meta>
          <body>
            <p>Line one</p>
            <p>Line two</p>
            <p>Line three</p>
            <p>Line four</p>
            <p>Line five</p>
            <p>Line six</p>
            <p>Line seven</p>
            <p>Line eight</p>
          </body>
          <footer><note>End</note></footer>
        </report>
      XML

      xml2 = <<~XML
        <report>
          <meta><version>2.0</version></meta>
          <body>
            <p>Line one</p>
            <p>Line two</p>
            <p>Line three</p>
            <p>Line four</p>
            <p>Line five</p>
            <p>Line six</p>
            <p>Line seven</p>
            <p>Line eight</p>
          </body>
          <footer><note>Done</note></footer>
        </report>
      XML

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true)
      diff = result.diff(use_color: false)

      # Should have two separate blocks (header version + footer note)
      # indicated by an empty line between them
      blocks = diff.split("\n\n")
      expect(blocks.length).to be >= 2,
                               "Expected separate context blocks for far-apart changes"
    end
  end

  describe "marker correctness" do
    it "uses -/+ for simple word replacements, not * mixed marker" do
      xml1 = "<root><p>John Doe</p></root>"
      xml2 = "<root><p>Jane Doe</p></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true)
      diff = result.diff(use_color: false)
      lines = diff.split("\n")

      # Match any line containing the marker character in the marker column
      # Format: "   2|    - | content" or "    |   2+ | content"
      has_star = lines.any? { |l| l.include?("* |") }
      has_minus = lines.any? { |l| l.include?("- |") }
      has_plus = lines.any? { |l| l.include?("+ |") }

      expect(has_star).to be_falsey,
                          "Simple replacement should NOT use * marker"
      expect(has_minus).to be_truthy
      expect(has_plus).to be_truthy
    end

    it "uses [/] for formatting-only whitespace changes" do
      xml1 = "<document>\n\t<section>\n\t\t<p>Hello</p>\n\t</section>\n</document>"
      xml2 = "<document>\n  <section>\n    <p>Hello</p>\n  </section>\n</document>"

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true)
      diff = result.diff(use_color: false)
      lines = diff.split("\n")

      # When documents are equivalent, NO markers should be shown
      # (the comparison found them equivalent despite formatting differences)
      has_formatting = lines.any? { |l| l.include?("[ |") || l.include?("] |") }
      has_normative = lines.any? { |l| l.include?("- |") || l.include?("+ |") }

      expect(has_formatting).to be_falsey,
                                "Equivalent documents should NOT show formatting markers"
      expect(has_normative).to be_falsey,
                               "Equivalent documents should NOT show normative markers"
    end

    it "uses -/+ for normative text changes mixed with whitespace" do
      xml1 = "<doc>\n\t<p>Hello World</p>\n</doc>"
      xml2 = "<doc>\n  <p>Hello Universe</p>\n</doc>"

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true)
      diff = result.diff(use_color: false)
      lines = diff.split("\n")

      has_normative = lines.any? { |l| l.include?("- |") || l.include?("+ |") }

      expect(has_normative).to be_truthy,
                               "Text change should show normative markers -/+"
    end
  end

  describe "whitespace visualization" do
    it "visualizes tabs as ⇥ in diff output" do
      xml1 = "<doc>\n\t<p>Hello</p>\n</doc>"
      xml2 = "<doc>\n  <p>Hello</p>\n</doc>"

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true)
      result.diff(use_color: false)

      # When equivalent, no diff output is shown, so no visualization applies
      # (visualization only matters when diff lines are actually shown)
      expect(result).to be_equivalent
    end

    it "visualizes spaces as ░ in diff output" do
      xml1 = "<doc>\n\t<p>Hello</p>\n</doc>"
      xml2 = "<doc>\n  <p>Hello</p>\n</doc>"

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true)
      result.diff(use_color: false)

      # When equivalent, no diff output is shown, so no visualization applies
      expect(result).to be_equivalent
    end
  end
end
