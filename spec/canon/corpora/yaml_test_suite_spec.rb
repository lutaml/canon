# frozen_string_literal: true

require "spec_helper"
require "yaml"

# Canon-level gate over the vendored yaml-test-suite (TODO.sota/06,
# W2.1): every parseable case runs canonicalize∘reparse idempotence
# and comparison stability — the canonical form re-parses to a
# document canon deems equivalent to the source, and formatting is a
# fixed point. Engine internals (the suite's own tree/json blocks)
# are deliberately not asserted here; this is canon's product-level
# contract, not the engine's.
#
# Known divergences are ledgered in canon-findings.yml (families:
# validator_rejected / non_idempotent / inequivalent). The gate fails
# on any finding BEYOND the ledger and flags ledger entries that no
# longer reproduce — the ledger shrinks as fixes land.
module YamlSuiteGate
  SUITE = File.join(__dir__, "../../fixtures/corpora/yaml-test-suite/src").freeze
  LEDGER = File.join(__dir__, "../../fixtures/corpora/yaml-test-suite/canon-findings.yml").freeze

  module_function

  def cases
    Dir.glob(File.join(SUITE, "*.yaml")).filter_map do |path|
      id = File.basename(path, ".yaml")
      meta = YAML.safe_load_file(path, aliases: true)
      next nil unless meta.is_a?(Array) && !meta.empty?

      first = meta.first
      next nil unless first.is_a?(Hash)

      {
        id: id,
        yaml: first["yaml"],
        error: first.fetch("error", false) == true || first["tags"].to_s.include?("error"),
        name: first["name"],
      }
    end
  end

  def finding_for(source)
    once = Canon.format_yaml(source)
    return :non_idempotent if Canon.format_yaml(once) != once

    return :inequivalent unless Canon::Comparison.equivalent?(source, once,
                                                              format: :yaml)

    nil
  rescue Canon::ValidationError
    :validator_rejected
  end
end

RSpec.describe "yaml-test-suite canon-level gate" do
  let(:valid) { YamlSuiteGate.cases.select { |c| c[:yaml] && !c[:error] } }
  let(:invalid) { YamlSuiteGate.cases.select { |c| c[:error] } }
  let(:ledger) do
    (YAML.safe_load_file(YamlSuiteGate::LEDGER) || {}).transform_values { |v| Array(v) }
  end

  it "vendored a meaningful corpus" do
    expect(valid.count).to be > 200
    expect(invalid.count).to be > 20
  end

  it "has no finding beyond the ledger" do
    fresh = []
    valid.each do |c|
      family = YamlSuiteGate.finding_for(c[:yaml])
      next if family.nil?

      fresh << "#{c[:id]} (#{family}, #{c[:name]})" unless ledger[family.to_s]&.include?(c[:id])
    end
    expect(fresh).to be_empty,
                     "new canon-level findings beyond canon-findings.yml " \
                     "(extend the ledger only with a disposition):\n" +
                       fresh.join("\n")
  end

  it "has no stale ledger entry" do
    stale = []
    ledger.each do |family, ids|
      ids.each do |id|
        c = valid.find { |vc| vc[:id] == id }
        next if c.nil? # case removed from the suite

        stale << "#{id} (#{family})" if YamlSuiteGate.finding_for(c[:yaml]).nil?
      end
    end
    expect(stale).to be_empty,
                     "ledger entries no longer reproduce — shrink " \
                     "canon-findings.yml:\n#{stale.join("\n")}"
  end

  it "sorts heterogeneous mapping keys under a total order" do
    # the yaml-test-suite's mixed-key shapes (the 2EBW class) crashed
    # the formatter's keys.sort before the [class, to_s] order
    mixed = "b: 1\n1: 2\n:c: 3\n"
    once = Canon.format_yaml(mixed)
    expect(Canon.format_yaml(once)).to eq(once)
  end

  YamlSuiteGate.cases.select { |c| c[:error] }.each do |c|
    describe c[:id] do
      it "rejects the case or canonicalizes it, never mis-compares" do
        once = begin
          Canon.format_yaml(c[:yaml])
        rescue Canon::Error, Psych::SyntaxError
          next
        end
        # a formatter that accepts an error-tagged document must still
        # own its output: fixed point + equivalence
        twice = Canon.format_yaml(once)
        expect(twice).to eq(once)
        expect(Canon::Comparison.equivalent?(c[:yaml], once, format: :yaml))
          .to be(true)
      end
    end
  end
end
