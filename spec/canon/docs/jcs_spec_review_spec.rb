# frozen_string_literal: true

require "spec_helper"

# W6.3 review gate for docs/_references/jcs-rfc8785.adoc (the W6.1
# rider): the JCS document must match SHIPPED behavior — the law
# tokens read the implementation's own constants and methods.
JCS_DOC = File.join(__dir__, "../../../docs/_references/jcs-rfc8785.adoc").freeze

RSpec.describe "jcs-rfc8785 document review" do
  let(:doc) { File.read(JCS_DOC) }

  it "exists" do
    expect(File.exist?(JCS_DOC)).to be(true)
  end

  it "cites the implementation's methods and tables" do
    %w[canonicalize serialize escape_string es6_number ijson_integer
       utf16_code_units write_object SHORT_ESCAPES].each do |token|
      expect(doc).to include(token), "implementation token #{token} not documented"
    end
  end

  it "cites the RFC anchors" do
    expect(doc).to include("RFC 8785")
    expect(doc).to include("RFC 7493")
    expect(doc).to include("3.2.2.2")
    expect(doc).to include("UTF-16 code units")
  end

  it "documents the shipped behavior on the RFC's sorting law" do
    # UTF-16 code-unit sorting diverges from code-point sorting at
    # the surrogate boundary: U+10000 (code units D800 DC00) sorts
    # BEFORE U+FFFD (single unit FFFD) although its code point is
    # larger. The canonical order here is a, then U+10000, then
    # U+FFFD.
    doc_hash = { "\uFFFD" => 1, "\u{10000}" => 2, "a" => 3 }
    out = Canon::Json::JCS.canonicalize(doc_hash)
    expect(Canon::Json::JCS.canonicalize(out)).to eq(out)
    keys = out.scan(/"([^"]*)":/).flatten
    expect(keys).to eq(["a", "\u{10000}", "\uFFFD"])
  end
end
