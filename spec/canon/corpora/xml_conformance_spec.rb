# frozen_string_literal: true

require "spec_helper"
require "yaml"

# Canon-level gate over the vendored XML corpus (TODO.sota/06, W2.1):
# libxml2's instance documents (top-level suite files, the C14N test
# inputs, namespaces, XInclude, SVG) run parse → canonicalize →
# reparse → compare. Engine internals and C14N byte expectations are
# the engine-parity suite's business; this is canon's product
# contract. libxml2's test corpus is MIT (Copyright file vendored
# alongside).
module XmlSuiteGate
  ROOT = File.join(__dir__, "../../fixtures/corpora/xml-conformance").freeze
  LEDGER = File.join(ROOT, "canon-findings.yml").freeze

  module_function

  def cases
    Dir.glob(File.join(ROOT, "**/*.xml")).filter_map do |path|
      rel = path.delete_prefix("#{ROOT}/")
      content = File.read(path)
      next nil if content.include?("<!-- Items deliberately not well") ||
        content.include?("<!DOCTYPE doc [ <!-- INVALID")

      { id: rel, xml: content }
    end
  end

  def finding_for(source)
    once = Canon.format_xml(source)
    return :non_idempotent if Canon.format_xml(once) != once

    return :inequivalent unless Canon::Comparison.equivalent?(source, once,
                                                              format: :xml)

    nil
  rescue Canon::Error
    :rejected
  end
end

RSpec.describe "xml-conformance canon-level gate" do
  let(:cases) { XmlSuiteGate.cases }
  let(:ledger) do
    (YAML.safe_load_file(XmlSuiteGate::LEDGER) || {}).transform_values { |v| Array(v) }
  end

  it "vendored a meaningful corpus" do
    expect(cases.count).to be > 140
  end

  it "canonicalizes every well-formed case to a fixed point that compares equivalent" do
    rejected = []
    failures = []
    cases.each do |c|
      once = begin
        Canon.format_xml(c[:xml])
      rescue StandardError => e
        rejected << "#{c[:id]} (#{e.class.name.split('::').last})"
        next
      end
      twice = Canon.format_xml(once)
      family = twice == once ? nil : :non_idempotent
      if family.nil? && !Canon::Comparison.equivalent?(c[:xml], once,
                                                       format: :xml)
        family = :inequivalent
      end
      next if family.nil?

      next if ledger[family.to_s]&.include?(c[:id])

      failures << "#{c[:id]} (#{family})"
    end
    unless rejected.empty?
      warn "parser-rejected cases (#{rejected.count}): #{rejected.join(', ')}"
    end
    # a mass rejection means the corpus and the parser disagree about
    # well-formedness, not one bad file
    expect(rejected.count).to be < cases.count / 10
    expect(failures).to be_empty,
                        "new canon-level findings beyond canon-findings.yml " \
                        "(extend the ledger only with a disposition):\n" +
                          failures.join("\n")
  end

  it "has no stale ledger entry" do
    stale = []
    ledger.each do |family, ids|
      ids.each do |id|
        c = cases.find { |cc| cc[:id] == id }
        next if c.nil? # case removed from the corpus

        stale << "#{id} (#{family})" if XmlSuiteGate.finding_for(c[:xml]).nil?
      end
    end
    expect(stale).to be_empty,
                     "ledger entries no longer reproduce — shrink " \
                     "canon-findings.yml:\n#{stale.join("\n")}"
  end
end
