require "spec_helper"

RSpec.describe "rebaseliner fixture" do
  it "skips inline string literal" do
    expect("<root>fresh</root>").to be_xml_equivalent_to("<root>stale</root>")
  end
end
