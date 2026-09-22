# frozen_string_literal: true

require "spec_helper"

RSpec.describe "namespace_prefix dimension" do
  let(:prefixed_a) { %(<r xmlns:ns="http://x"><ns:e t="u">t</ns:e></r>) }
  let(:prefixed_b) { %(<r xmlns:m="http://x"><m:e t="u">t</m:e></r>) }
  let(:other_uri) { %(<r xmlns:ns="http://OTHER"><ns:e t="u">t</ns:e></r>) }

  def equivalent?(a, b, **opts) # rubocop:todo Naming/MethodParameterName
    Canon::Comparison.equivalent?(a, b, { format: :xml }.merge(opts))
  end

  it "treats prefix spelling as significant by default" do
    expect(equivalent?(prefixed_a, prefixed_b)).to be false
  end

  it "treats prefix renames as equivalent under :ignore" do
    expect(equivalent?(prefixed_a, prefixed_b,
                       match: { namespace_prefix: :ignore })).to be true
  end

  it "still reports genuinely different URI sets under :ignore" do
    expect(equivalent?(prefixed_a, other_uri,
                       match: { namespace_prefix: :ignore })).to be false
  end

  it "adopts :ignore in the spec_friendly and content_only profiles" do
    expect(equivalent?(prefixed_a, prefixed_b,
                       match_profile: :spec_friendly)).to be true
    expect(equivalent?(prefixed_a, prefixed_b,
                       match_profile: :content_only)).to be true
  end

  it "keeps :significant in the strict and rendered profiles" do
    expect(equivalent?(prefixed_a, prefixed_b,
                       match_profile: :strict)).to be false
    expect(equivalent?(prefixed_a, prefixed_b,
                       match_profile: :rendered)).to be false
  end

  it "reports removed/added URIs in the difference reason" do
    result = equivalent?(prefixed_a, other_uri,
                         match: { namespace_prefix: :ignore }, verbose: true)
    expect(result.differences.map(&:reason).join).to include("http://x")
  end
end
