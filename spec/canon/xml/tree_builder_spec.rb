# frozen_string_literal: true

require "spec_helper"

RSpec.describe "unified attribute normalization (TreeBuilder)" do
  it "resolves duplicate attributes first-wins under both engines" do
    xml = %(<a x="1" x="2" y="3"/>)
    nokogiri = Canon::Xml::DataModel.build_from_nokogiri(Nokogiri::XML(xml)).children.first
    moxml = Canon::Xml::DataModel.build_from_moxml(
      Canon::XmlParsing.moxml_context.parse(xml, readonly: true),
    ).children.first

    [nokogiri, moxml].each do |element|
      expect(element.attribute_nodes.map { |a| [a.name, a.value] }).to eq([["x", "1"], ["y", "3"]])
    end
  end
end
