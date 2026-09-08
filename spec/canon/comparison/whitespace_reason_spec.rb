# frozen_string_literal: true

require "spec_helper"

# A text difference whose sides are identical after stripping is a
# whitespace-only difference: the reason uses the compact
# character-count description instead of two full visualized copies
# that read as materially different text (issue #94).
RSpec.describe "whitespace-only text diff reasons" do
  def text_reason(text1, text2)
    result = Canon::Comparison.equivalent?(
      "<r><p>#{text1}</p></r>", "<r><p>#{text2}</p></r>",
      format: :xml, verbose: true
    )
    result.differences.find { |d| d.dimension == :text_content }&.reason
  end

  it "uses the compact description for trailing-whitespace-only differences" do
    reason = text_reason("same content here\n", "same content here\n\n")
    expect(reason).to start_with("whitespace-only:")
    expect(reason).to include("chars")
    expect(reason).not_to include("same content here")
  end

  it "keeps the full visualized form for real content differences" do
    reason = text_reason("hello world", "hello moon")
    expect(reason).to start_with("Text:")
    expect(reason).to include("hello")
  end

  it "keeps the full form for interior whitespace differences" do
    reason = text_reason("hello world", "hello  world")
    expect(reason).to start_with("Text:")
  end
end
