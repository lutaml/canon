# frozen_string_literal: true

require "spec_helper"

# W5.3 gate: the digest-stability suite. These pins travel across
# releases — a canonical-form change moves a digest and MUST fail
# here, forcing a conscious pin update (and a note in the release)
# rather than a silent digest drift for downstream dedup stores.
RSpec.describe Canon::Digest do
  let(:pinned) do
    {
      xml: {
        doc: "<library><book id=\"b1\"><title>Alpha</title><author>Zed</author></book>" \
             "<book id=\"b2\"><title>Beta</title></book></library>",
        digest: "13ede3b15b4c588ac41b7ee4ea5f9653ee1a99ca9ab8b2a71758e7ed44d111ac",
      },
      html: {
        doc: "<!DOCTYPE html><html><head><title>T</title></head><body><h1>Hello</h1>" \
             "<p>World</p></body></html>",
        digest: "b53452ff9c36582d329f828e326a9ab37c9ea5fdd3d27922168a57c90265ac43",
      },
      yaml: {
        doc: "library:\n  books:\n    - title: Alpha\n      author: Zed\n    - title: Beta\n",
        digest: "4f5c4f75df7167f97b86faa0e27160893335a45041d7f2e6336b81b99107da72",
      },
      json: {
        doc: "{\"library\":{\"books\":[{\"title\":\"Alpha\",\"author\":\"Zed\"}," \
             "{\"title\":\"Beta\"}]}}",
        digest: "d0b93212e688f9d3358f56fe477c58c22cd134127f09e2a4c2943d885f363a59",
      },
    }
  end

  it "pins every format's canonical digest" do
    pinned.each do |format, pin|
      expect(described_class.digest(pin[:doc], format)).to eq(pin[:digest])
    end
  end

  it "keeps the canonical forms fixed points (digest of the form is the digest)" do
    pinned.each do |format, pin|
      form = described_class.canonical_form(pin[:doc], format)
      expect(described_class.digest(form, format)).to eq(pin[:digest])
    end
  end
end
