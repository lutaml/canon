require "spec_helper"

RSpec.describe "rebaseliner fixture" do
  it "skips heredoc with interpolation" do
    name = "world"
    expected = <<~XML
      <greet>hello #{name}</greet>
    XML
    expect("<greet>goodbye</greet>").to be_xml_equivalent_to(expected)
  end
end
