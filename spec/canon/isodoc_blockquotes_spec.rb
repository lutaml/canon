# frozen_string_literal: true

require "spec_helper"

RSpec.describe "IsoDoc blockquotes bug reproduction" do
  let(:xml_formatter) do
    Canon::DiffFormatter.new(use_color: false, mode: :by_line,
                            diff_grouping_lines: 10)
  end

  it "reproduces the isodoc blockquotes diff bug" do
    # Load the fixture files with whitespace preserved
    expected_xml = File.read("spec/fixtures/xml/isodoc-blockquotes-expected.xml")
    actual_xml = File.read("spec/fixtures/xml/isodoc-blockquotes-actual.xml")

    result = xml_formatter.format([], :xml, doc1: expected_xml, doc2: actual_xml)

    # The bug: When comparing the presxml (pretty-printed) with actual output (compressed),
    # not all lines are shown in the diff
    puts "\n=== RESULT ==="
    puts result
    puts "=== END RESULT ===\n"

    # This test documents the expected behavior
    # expect(result).to include("This International Standard")
  end
end
