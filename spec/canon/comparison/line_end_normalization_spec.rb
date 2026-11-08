# frozen_string_literal: true

require "spec_helper"

RSpec.describe "comment and text line-end normalization" do
  # canon#310: engines disagree on XML 1.0 §2.11 line-end
  # normalization inside comment data and text nodes — libxml2
  # (the raw CANON_XML_BACKEND=nokogiri lane) preserves \r, while
  # the leptris lane normalizes to \n. Canon's comparison normalizes
  # at NodeInspector.text_content so equivalence stays engine-neutral.

  let(:crlf_source) do
    "<root><!-- note\r\nwith CRLF --><desc>line one\r\nline two</desc></root>"
  end

  let(:lf_source) do
    "<root><!-- note\nwith CRLF --><desc>line one\nline two</desc></root>"
  end

  it "compares CRLF and LF spellings of comments and text equivalent" do
    expect(Canon::Comparison.equivalent?(crlf_source, lf_source,
                                         format: :xml)).to be(true)
  end

  it "compares a parse-canonicalize round trip of a CRLF document" do
    once = Canon.format_xml(crlf_source)

    expect(Canon::Comparison.equivalent?(crlf_source, once,
                                         format: :xml)).to be(true)
  end

  it "keeps genuinely different comment content inequivalent" do
    expect(Canon::Comparison.equivalent?(
             "<root><!-- alpha --></root>",
             "<root><!-- beta --></root>",
             format: :xml,
           )).to be(false)
  end

  it "normalizes lone CR as well as CRLF" do
    cr_source = "<root><!-- a\rz --><t>x\ry</t></root>"

    once = Canon.format_xml(cr_source)
    expect(Canon::Comparison.equivalent?(cr_source, once,
                                         format: :xml)).to be(true)
  end

  it "normalizes in NodeInspector.text_content for Canon tree nodes" do
    comment = Canon::Xml::Nodes::CommentNode.new(value: "note\r\nwith CRLF")
    text = Canon::Xml::Nodes::TextNode.new(value: "line one\r\nline two")

    expect(Canon::Comparison::NodeInspector.text_content(comment))
      .to eq("note\nwith CRLF")
    expect(Canon::Comparison::NodeInspector.text_content(text))
      .to eq("line one\nline two")
  end
end
