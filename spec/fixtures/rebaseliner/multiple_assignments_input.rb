require "spec_helper"

RSpec.describe "rebaseliner fixture" do
  it "uses most-recent assignment for reassigned variable" do
    output = <<~XML
      <first>stale</first>
    XML
    expect("<first>fresh1</first>").to be_xml_equivalent_to(output)

    output = <<~XML
      <second>stale</second>
    XML
    expect("<second>fresh2</second>").to be_xml_equivalent_to(output)
  end
end
