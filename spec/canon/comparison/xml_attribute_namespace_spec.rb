# frozen_string_literal: true

require "spec_helper"

# Attributes compare by expanded name (namespace URI + local name,
# XML Namespaces 1.0 §5.2/§5.3): an unprefixed attribute is in NO
# namespace and is never equivalent to a qualified one, and prefixes
# bound to the same URI are the same attribute (issue #155).
RSpec.describe "XML attribute expanded-name comparison" do
  let(:base) do
    <<~XML
      <g:Point xmlns:g="http://www.opengis.net/gml/3.2">
        <g:pos>1 2</g:pos>
      </g:Point>
    XML
  end
  let(:unprefixed) { base.sub("<g:Point ", %(<g:Point srsName="urn:x" )) }
  let(:g_prefixed) { base.sub("<g:Point ", %(<g:Point g:srsName="urn:x" )) }
  let(:gml_prefixed) do
    base.sub("<g:Point ", %(<g:Point xmlns:gml="http://www.opengis.net/gml/3.2" gml:srsName="urn:x" ))
  end
  let(:foo_prefixed) do
    base.sub("<g:Point ", %(<g:Point xmlns:foo="http://example.com/x" foo:srsName="urn:x" ))
  end

  def equivalent?(left, right, **opts)
    Canon::Comparison.equivalent?(left, right, { format: :xml }.merge(opts))
  end

  it "does not conflate an unqualified attribute with a qualified one" do
    expect(equivalent?(unprefixed, g_prefixed)).to be false
    expect(equivalent?(unprefixed, gml_prefixed)).to be false
    expect(equivalent?(unprefixed, foo_prefixed)).to be false
  end

  it "treats the same attribute under different prefixes of the same URI as equal" do
    # Both documents declare both prefixes; only the prefix spelling
    # of the attribute differs. Expanded names are identical.
    a = %(<g:Point xmlns:g="http://www.opengis.net/gml/3.2" xmlns:gml="http://www.opengis.net/gml/3.2" g:srsName="urn:x"><g:pos>1 2</g:pos></g:Point>)
    b = %(<g:Point xmlns:g="http://www.opengis.net/gml/3.2" xmlns:gml="http://www.opengis.net/gml/3.2" gml:srsName="urn:x"><g:pos>1 2</g:pos></g:Point>)
    expect(equivalent?(a, b)).to be true
  end

  it "still matches identical documents" do
    expect(equivalent?(g_prefixed, g_prefixed)).to be true
    expect(equivalent?(unprefixed, unprefixed)).to be true
  end

  it "keeps ignore lists working against local names" do
    expect(equivalent?(unprefixed, g_prefixed, ignore_attrs: [])).to be false
    expect(
      equivalent?(unprefixed, g_prefixed, ignore_attrs_by_name: ["srsNa"]),
    ).to be true
  end
end
