# frozen_string_literal: true

require "spec_helper"

RSpec.describe "HTML fragment attribute diagnostics" do
  it "dumps attribute shapes" do
    html = '<span lang="en" xml:lang="en">text</span>'
    frag = Canon::XmlParsing.moxml_context.parse_html_fragment(html)
    child = frag.children.first
    warn "DIAG wrapper: class=#{child.class} name=#{child.name}"
    child.attributes.each do |a|
      warn "DIAG wrapper attr: name=#{a.name.inspect} prefix=#{a.namespace&.prefix.inspect} uri=#{a.namespace&.uri.inspect} value=#{a.value.inspect}"
    end
    records = []
    child.materialize_fields do |kind, qname, prefix, namespace_uri, _ns, attrs, text, depth|
      records << [kind, qname, prefix, namespace_uri, attrs.to_a.inspect, text.to_s.inspect, depth]
    end
    warn "DIAG records: #{records.inspect}"
    root = Canon::Comparison::HtmlParser.parse(html, :html5)
    span = root.children.find { |c| c.is_a?(Canon::Xml::Nodes::ElementNode) }
    span.attribute_nodes.each do |a|
      warn "DIAG canon attr: name=#{a.name.inspect} prefix=#{a.prefix.inspect} uri=#{a.namespace_uri.inspect} qname=#{a.qname.inspect}"
    end
    expect(true).to be true
  end
end
