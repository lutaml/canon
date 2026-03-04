# frozen_string_literal: true

require "spec_helper"

RSpec.describe "IsoDoc attribute order issue" do
  let(:expected) do
    File.read(File.join(__dir__,
                        "../fixtures/html/isodoc-section-names-expected.html"))
  end
  let(:actual) do
    File.read(File.join(__dir__,
                        "../fixtures/html/isodoc-section-names-actual.html"))
  end

  it "is equivalent with spec_friendly profile (only attribute order differs)" do
    result = Canon::Comparison.equivalent?(
      expected,
      actual,
      format: :html4,
      match_profile: :spec_friendly,
      verbose: true,
    )

    # result.differences.each_with_index do |d, _i|
    #   if d.respond_to?(:dimension)
    #   end
    # end

    # With spec_friendly, attribute order is normalized - should be equivalent
    expect(result.equivalent?).to be true
  end
end
