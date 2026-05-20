require "spec_helper"

RSpec.describe "rebaseliner fixture" do
  it "rewrites squiggly heredoc" do
    expected = <<~XML
      <root>stale</root>
    XML
    actual = "<root>fresh</root>"
    expect(actual).to be_xml_equivalent_to(expected)
  end
end
