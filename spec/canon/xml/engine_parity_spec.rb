# frozen_string_literal: true

require "spec_helper"
require "stringio"

# Engine parity: Nokogiri vs moxml's resolved adapter (leptris).
#
# This spec is the gate for flipping Canon::XmlBackend's default to
# :moxml. The non-pending examples must always pass — they guard the
# translation seams (SAX drivers, DOM conversion) that canon owns.
#
# The pending examples document CURRENT upstream divergences in
# libleptris / the moxml leptris adapter. Each pending body asserts
# parity, so when upstream fixes the gap RSpec reports the example as
# "pending, passed" — remove the pending marker then. When no pendings
# remain, flip the default in Canon::XmlBackend#detect.
RSpec.describe "XML engine parity", :xml_engine_parity do
  let(:adapter_name) { Canon::XmlParsing.moxml_adapter_name }

  def nokogiri_tree(xml, preserve: true)
    Canon::Xml::DataModel.build_from_nokogiri(
      Nokogiri::XML(xml), preserve_whitespace: preserve
    )
  end

  def moxml_tree(xml, preserve: true)
    Canon::Xml::DataModel.build_from_moxml(
      Canon::XmlParsing.moxml_context.parse(xml), preserve_whitespace: preserve
    )
  end

  # Structural dump: type, qname, namespace URI, value, attributes.
  def dump(node, io)
    label = node.node_type.to_s
    label += " #{node.name}" if node.respond_to?(:name) && node.name && node.node_type != :text
    label += " ns=#{node.namespace_uri}" if node.respond_to?(:namespace_uri) && node.namespace_uri
    label += " value=#{node.value.inspect}" if node.respond_to?(:value) && node.value
    if node.respond_to?(:attribute_nodes) && node.attribute_nodes.any?
      label += " attrs=#{node.attribute_nodes.map { |a| [a.name, a.value, a.namespace_uri] }.inspect}"
    end
    io.puts label
    node.children.each { |child| dump(child, io) } if node.respond_to?(:children)
  end

  def tree_string(builder_result)
    io = StringIO.new
    dump(builder_result, io)
    io.string
  end

  def expect_tree_parity(xml, preserve: true)
    expect(tree_string(moxml_tree(xml, preserve: preserve)))
      .to eq(tree_string(nokogiri_tree(xml, preserve: preserve)))
  end

  before do
    skip "requires CRuby Nokogiri" if RUBY_ENGINE == "opal"
    skip "compares against a non-nokogiri adapter" if adapter_name == :nokogiri
  end

  describe "DOM conversion parity (canon-owned seam)" do
    it "matches on well-formed documents with namespaces, entities, and inline PIs" do
      xml = <<~XML
        <catalog version="2.0" xmlns:x="http://x.example" xmlns="http://def.example">
          <?pi instr?><!--c--><x:book id="1">Title &amp; sub&#65;<note/></x:book><empty/>
        </catalog>
      XML
      expect_tree_parity(xml)
    end

    it "matches on CDATA content (literal — character references not decoded)" do
      xml = %q(<a>x<![CDATA[y &amp; &#65; ]]>z<wht>  </wht></a>)
      expect_tree_parity(xml)
    end

    it "matches on character data and attribute escaping" do
      xml = %(<root a="&lt;&amp;&gt;">&lt;tag&gt; &amp; &quot;text&quot;</root>)
      expect_tree_parity(xml)
    end

    it "matches on namespace bindings of prefixed attributes" do
      xml = %(<root xmlns:x="http://x.example"><code x:tag="t" xml:space="preserve">t</code></root>)
      expect_tree_parity(xml)
    end

    it "matches on inherited and undeclared namespaces" do
      xml = %(<doc xmlns:a="http://www.w3.org"><e7 xmlns="http://www.ietf.org"><e8 xmlns=""/></e7></doc>)
      expect_tree_parity(xml)
    end
  end

  describe "SAX driver parity (canon-owned seam)" do
    def sax_tree(driver_class, xml)
      builder = Canon::Xml::SaxBuilder.new(preserve_whitespace: false)
      driver_class.new(builder).parse(xml)
      builder.result
    end

    it "NokogiriDriver and MoxmlDriver build identical trees" do
      xml = %(<catalog version="2.0" xmlns:x="http://x.example" xmlns="http://def.example"><?pi instr?><!--c--><x:book id="1" x:tag="t">Title &amp; sub&#65;<![CDATA[lit &amp; &#65;]]><note/></x:book><empty/></catalog>)
      expect(tree_string(sax_tree(Canon::Xml::Sax::MoxmlDriver, xml)))
        .to eq(tree_string(sax_tree(Canon::Xml::Sax::NokogiriDriver, xml)))
    end
  end

  describe "XML 1.0 conformance (upstream)" do
    it "normalizes whitespace in attribute values per XML 1.0 §3.3.3" do
      xml = "<root attr=\"value\twith\nwhitespace\r\"/>"
      expect_tree_parity(xml)
    end

    it "keeps processing instructions before the document element" do
      expect_tree_parity("<?pi-target pi-data?><root/>")
    end

    it "parses processing instructions after the document element" do
      expect_tree_parity("<root/><?pi-after?>")
    end

    it "keeps comments outside the document element" do
      expect_tree_parity("<!-- before --><root/><!-- after -->")
    end
  end

  describe "C14N conformance (upstream: libleptris)" do
    def c14n(tree)
      Canon::Xml::Processor.new(with_comments: true).process(tree)
    end

    it "canonicalizes W3C C14N 1.1 example 3.1 (prolog/epilog PIs and comments)" do
      xml = File.read("spec/fixtures/c14n/example-3.1-pis-comments.input.xml")
      expect(c14n(moxml_tree(xml))).to eq(c14n(nokogiri_tree(xml)))
    end

    it "canonicalizes W3C C14N 1.1 example 3.3 (namespace undeclaration)" do
      xml = File.read("spec/fixtures/c14n/example-3.3-start-end-tags.input.xml")
      expect(c14n(moxml_tree(xml))).to eq(c14n(nokogiri_tree(xml)))
    end
  end
end
