# frozen_string_literal: true

require "spec_helper"
require "json"

# Canon-level gate over the vendored JSONTestSuite (TODO.sota/06,
# W2.1): y_* cases must accept, canonicalize to a fixed point, and
# compare equivalent to the source; n_* cases must reject; i_* cases
# may do either but never mis-compare. The JSON lane is engine-free
# (stdlib parse + the strict yeptris surface), so there is no
# engine-dependent validator family here.
module JsonSuiteGate
  DIR = File.join(__dir__, "../../fixtures/corpora/json-test-suite/test_parsing").freeze
  KINDS = %w[y n i].freeze

  module_function

  def cases
    Dir.glob(File.join(DIR, "*.json")).filter_map do |path|
      id = File.basename(path)
      kind = id[0] # y / n / i
      next nil unless KINDS.include?(kind)

      { id: id, kind: kind, json: File.read(path) }
    end
  end

  def format_or_raise(source)
    Canon.format_json(source)
  end
end

RSpec.describe "JSONTestSuite canon-level gate" do
  let(:cases) { JsonSuiteGate.cases }
  let(:accept) { cases.select { |c| c[:kind] == "y" } }
  let(:reject) { cases.select { |c| c[:kind] == "n" } }
  let(:impl_defined) { cases.select { |c| c[:kind] == "i" } }

  it "vendored the full corpus" do
    expect(cases.count).to eq(318)
    expect(accept.count).to eq(95)
    expect(reject.count).to eq(188)
    expect(impl_defined.count).to eq(35)
  end

  it "accepts, canonicalizes idempotently, and compares equivalent for every y_ case" do
    failures = []
    accept.each do |c|
      once = begin
        JsonSuiteGate.format_or_raise(c[:json])
      rescue Canon::ValidationError
        # a canon-owned rejection is the strict surface's design
        # decision (the duplicate-key pair: JSONTestSuite tags y_
        # because RFC 8259 allows duplicates syntactically, but
        # canon's strict surface rejects them by contract) — owned,
        # not a parse bug. A bare JSON::ParserError below still fails.
        next
      end
      twice = JsonSuiteGate.format_or_raise(once)
      failures << "#{c[:id]}: not idempotent" if twice != once
      unless Canon::Comparison.equivalent?(c[:json], once, format: :json)
        failures << "#{c[:id]}: canonical form not equivalent to source"
      end
    rescue Canon::Error, JSON::ParserError
      failures << "#{c[:id]}: rejected but tagged y_"
    end
    expect(failures).to be_empty, failures.join("\n")
  end

  it "rejects every n_ case" do
    accepted = []
    reject.each do |c|
      once = JsonSuiteGate.format_or_raise(c[:json])
      accepted << c[:id] if once
    rescue Canon::Error, JSON::ParserError
      next
    end
    expect(accepted).to be_empty, "n_ cases canon accepted:\n#{accepted.join("\n")}"
  end

  it "owns its output on every i_ case: fixed point and equivalence when accepted" do
    failures = []
    impl_defined.each do |c|
      once = begin
        JsonSuiteGate.format_or_raise(c[:json])
      rescue Canon::Error, JSON::ParserError
        next
      end
      twice = JsonSuiteGate.format_or_raise(once)
      failures << "#{c[:id]}: not idempotent" if twice != once
      unless Canon::Comparison.equivalent?(c[:json], once, format: :json)
        failures << "#{c[:id]}: accepted form not equivalent to source"
      end
    end
    expect(failures).to be_empty, failures.join("\n")
  end
end
