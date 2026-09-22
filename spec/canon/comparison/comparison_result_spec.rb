# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison::ComparisonResult do
  let(:expected) { "<a><b>1</b></a>" }
  let(:actual) { "<a><b>2</b></a>" }

  let(:comparison_result) do
    Canon::Comparison.equivalent?(expected, actual, verbose: true,
                                                    format: :xml)
  end

  it "marshals verbose results whose display strings were never read" do
    copy = Marshal.load(Marshal.dump(comparison_result))
    expect(copy).to be_a(described_class)
    expect(copy).not_to be_equivalent
  end

  it "marshals verbose results after materialization" do
    r = comparison_result
    r.preprocessed_strings
    copy = Marshal.load(Marshal.dump(r))
    expect(copy.preprocessed_strings).to eq(r.preprocessed_strings)
    expect(copy.original_strings).to eq(r.original_strings)
    expect(copy.differences.size).to eq(r.differences.size)
  end

  it "preserves parse errors and format through the round-trip" do
    dup_lang = %(<body xml:lang="en" xml:lang="en">x</body>)
    r = Canon::Comparison.equivalent?(dup_lang, dup_lang.dup,
                                      verbose: true, format: :xml)
    copy = Marshal.load(Marshal.dump(r))
    expect(copy.parse_errors?).to be true
    expect(copy.format).to eq(:xml)
  end
end
