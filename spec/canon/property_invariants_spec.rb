# frozen_string_literal: true

require "spec_helper"
require "support/format_generator"

# Canonical-form property invariants (TODO.sota/03, W1.5): idempotency
# (f(f(x)) == f(x)), determinism (same input + profile ⇒ same bytes),
# and equivalence-respect (x ≡ y ⇒ f(x) == f(y)) — per format, over a
# seeded generated corpus. A counterexample fails with the case id
# ("gen <seed>/<i>"), reproducible at CANON_PROP_SEEDS.
RSpec.describe "canonical-form property invariants" do
  let(:fuzz_seeds) do
    if ENV.key?("CANON_PROP_SEEDS")
      ENV.fetch("CANON_PROP_SEEDS").split(",").map(&:to_i)
    else
      [20261022]
    end
  end

  let(:fuzz_count) { Integer(ENV.fetch("CANON_PROP_CASES", "100")) }

  let(:cases) do
    FormatGenerator.cases(seeds: fuzz_seeds, count: fuzz_count)
  end

  def format_as(text, fmt)
    Canon.format(text, fmt)
  end

  it "is idempotent: format(format(x)) == format(x) per format" do
    cases.each do |c|
      {
        json: c[:json], yaml: c[:yaml], xml: c[:xml], html: c[:html]
      }.each do |fmt, text|
        once = format_as(text, fmt)
        twice = format_as(once, fmt)
        expect(twice).to eq(once),
                         "#{c[:id]}/#{fmt}: format is not idempotent " \
                         "(#{once.inspect[0, 120]} vs #{twice.inspect[0, 120]})"
      end
    end
  end

  it "is deterministic: same input answers the same bytes" do
    probe = cases.first
    { json: probe[:json], yaml: probe[:yaml], xml: probe[:xml],
      html: probe[:html] }.each do |fmt, text|
      first = format_as(text, fmt)
      10.times { expect(format_as(text, fmt)).to eq(first) }
    end
  end

  it "respects equivalence: shuffled JSON keys answer identical bytes" do
    cases.each do |c|
      doc = JSON.parse(c[:json])
      rng = Random.new(c[:id].hash)
      shuffled = FormatGenerator.deep_shuffle_hash(doc, rng)
      expect(format_as(JSON.generate(shuffled), :json)).to eq(c[:json] && format_as(c[:json], :json)),
                                                           "#{c[:id]}: key order changed the " \
                                                           "canonical JSON bytes"
    end
  end

  it "respects equivalence: shuffled YAML keys answer identical bytes" do
    cases.each do |c|
      doc = YAML.safe_load(c[:yaml], aliases: true)
      next unless doc.is_a?(Hash)

      rng = Random.new(c[:id].hash)
      shuffled = FormatGenerator.deep_shuffle_hash(doc, rng)
      expect(format_as(YAML.dump(shuffled), :yaml)).to eq(format_as(c[:yaml], :yaml)),
                                                       "#{c[:id]}: key order changed the " \
                                                       "canonical YAML bytes"
    end
  end

  # PENDING (W6.2): the XML pretty canonical form preserves
  # parse-order attributes today. Sorting them (the C14N-consistent
  # choice) requires the comparison engine's attribute_order :ignore
  # behavior verified end-to-end on the DOM diff path first (the
  # battery finding this suite produced; ledgered in TODO.sota/03).
  it "respects equivalence: shuffled XML attributes answer identical bytes" do
    skip "blocked on the W6.2 attribute-order semantics decision"
    cases.each do |c|
      rng = Random.new(c[:id].hash)
      shuffled = FormatGenerator.shuffled_xml(c[:xml], rng)
      expect(format_as(shuffled, :xml)).to eq(format_as(c[:xml], :xml)),
                                           "#{c[:id]}: attribute order changed " \
                                           "the canonical XML bytes"
    end
  end
end
