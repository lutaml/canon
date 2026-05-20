require "spec_helper"

RSpec.describe "rebaseliner fixture" do
  it "never rewrites under .not_to" do
    expected = <<~XML
      <root>same</root>
    XML
    # actual differs from expected, .not_to should pass; rebaseliner must NOT
    # rewrite the heredoc even though matches? returns false.
    expect("<root>different</root>").not_to be_xml_equivalent_to(expected)
  end
end
