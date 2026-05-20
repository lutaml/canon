require "spec_helper"

RSpec.describe "rebaseliner fixture" do
  it "rewrites heredoc passed inline to the matcher" do
    expect("<root>fresh</root>").to be_xml_equivalent_to(<<~XML)
      <root>stale</root>
    XML
  end
end
