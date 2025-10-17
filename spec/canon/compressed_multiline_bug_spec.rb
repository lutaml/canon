# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Compressed multiline content bug" do
  let(:formatter) do
    Canon::DiffFormatter.new(use_color: false, mode: :by_line,
                             diff_grouping_lines: 10)
  end

  it "shows ALL deleted lines when multi-line content is compressed to single line" do
    # Multi-line attribution content in file 1
    xml1 = <<~XML
      <quote id="_">
        <attribution>
          <p>
            —
            <semx element="author" source="_">ISO</semx>
            ,
            <semx element="source" source="_">
              <fmt-eref type="inline" bibitemid="ISO7301" citeas="ISO 7301:2011">
                <locality type="clause">
                  <referenceFrom>1</referenceFrom>
                </locality>
                ISO 7301:2011, Clause 1
              </fmt-eref>
            </semx>
          </p>
        </attribution>
      </quote>
    XML

    # Same content compressed to single line in file 2
    xml2 = <<~XML
      <quote id="_">
        <attribution><p>— <semx element="author" source="_">ISO</semx>, <semx element="source" source="_"><fmt-eref type="inline" bibitemid="ISO7301" citeas="ISO 7301:2011"><locality type="clause"><referenceFrom>1</referenceFrom></locality>ISO 7301:2011, Clause 1</fmt-eref></semx></p></attribution>
      </quote>
    XML

    result = formatter.format([], :xml, doc1: xml1, doc2: xml2)

    # Debugging: print the actual result
    puts "\n=== ACTUAL DIFF OUTPUT ==="
    puts result
    puts "=== END DIFF OUTPUT ===\n"

    # Count how many lines contain the deletion marker "- |"
    deletion_lines = result.lines.select { |line| line.match?(/\|\s*-\s*\|/) }

    puts "\n=== DELETION LINES (#{deletion_lines.count}) ==="
    deletion_lines.each { |line| puts line }
    puts "=== END DELETION LINES ===\n"

    # The multi-line attribution has these distinct lines:
    # 1. <p>
    # 2. —
    # 3. <semx element="author" source="_">ISO</semx>
    # 4. ,
    # 5. <semx element="source" source="_">
    # 6. <fmt-eref type="inline" bibitemid="ISO7301" citeas="ISO 7301:2011">
    # 7. <locality type="clause">
    # 8. <referenceFrom>1</referenceFrom>
    # 9. </locality>
    # 10. ISO 7301:2011, Clause 1
    # 11. </fmt-eref>
    # 12. </semx>
    # 13. </p>

    # ALL these lines should be shown as deleted
    expect(result).to include("element=\"author\"")
    expect(result).to include("element=\"source\"")
    expect(result).to include("<fmt-eref")
    expect(result).to include("<locality")
    expect(result).to include("<referenceFrom>")
    expect(result).to include("</locality>")
    expect(result).to include("</fmt-eref>")
    expect(result).to include("</semx>")

    # At minimum, we should see 10+ deletion markers for the multi-line content
    expect(deletion_lines.count).to be >= 10,
                                    "Expected at least 10 deletion lines, but got #{deletion_lines.count}. " \
                                    "Missing lines are not being shown in the diff."
  end
end
