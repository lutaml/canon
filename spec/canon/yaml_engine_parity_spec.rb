# frozen_string_literal: true

require "spec_helper"

# Parity gate between canon's YAML engines (see Canon::YamlBackend).
# Every case must load identically through Canon::YamlParsing under
# Psych and yeptris before the default flips off :psych. The pending
# cases track the upstream divergences (yeptris-ruby issues).
PARITY_CASES = {
  "merge keys" => "base: &b\n  x: 1\nuse:\n  <<: *b\n  y: 2\n",
  "y/n booleans" => "a: y\nb: n\nc: yes\nd: no\n",
  "on/off booleans" => "a: on\nb: off\n",
  "octal and hex" => "a: 017\nb: 0o17\nc: 0x1f\n",
  "timestamps" => "d: 2026-09-07\nt: 2026-09-07T10:00:00Z\n",
  "symbols" => "a: :sym\n",
  "nulls" => "a: ~\nb: null\nc:\n",
  "special floats" => "a: .inf\nb: -.Inf\nc: .nan\n",
  "unicode" => "a: héllo　✓\nb: \"日本語\"\n",
  "anchors" => "a: &x 1\nb: *x\n",
  "nested structures" => "- - 1\n  - 2\n- k: v\n",
  "quoted keys" => "\"a b\": 1\n'c d': 2\n",
  "multiline scalars" => "a: |\n  line1\n  line2\nb: >\n  folded\n  text\n",
  "empty strings" => "a: ''\n",
  "underscored integers" => "a: 1_000\nb: +2\n",
}.freeze

PENDING_UPSTREAM = {
  "empty documents" => ["", "yeptris-ruby#29 — FFI::NullPointerError; gateway maps to nil meanwhile"],
  "comment-only documents" => ["# just a comment\n", "yeptris-ruby#29"],
  "sexagesimal scalars" => ["a: 1:30\n", "yeptris-ruby#30 — 90 vs Psych 5400"],
  "bignum integers" => ["a: 12345678901234567890123\n", "yeptris-ruby#31 — String vs Integer"],
  "JSON duplicate keys" => ['{"a":1,"a":2}', "yeptris-ruby#37 — last-wins vs json gem 3.0 strict raise"],
}.freeze

JSON_PARITY_CASES = {
  "flat" => '{"a":1,"b":2,"c":true,"d":false,"e":null}',
  "nested" => '{"x":{"y":[1,[2,{"z":[]}]],"w":{}}}',
  "floats" => '{"a":1.5,"b":1e10,"c":-0.25}',
  "unicode escapes" => '{"a":"héllo","b":"日本語"}',
  "string escapes" => %q({"esc":"a\"b\nc\td","empty":""}),
  "top array" => '[1,"two",{"three":3}]',
  "whitespace" => "  {\"a\" : 1 }  \n",
  "deep" => (1..40).reduce("1") { |acc, _| "[#{acc}]" },
  # Quirk boundaries where the YAML (Psych-contract) and strict JSON
  # surfaces diverge: exponent-without-dot, y/n quoted, negative zero,
  # exponent forms, duplicate keys.
  "exponent no dot" => '{"a":1e3,"b":1E+2}',
  "quoted y n" => '{"a":"y","b":"n","c":"yes"}',
  "negative zero" => '{"a":-0,"b":-0.0}',
  "duplicate keys" => '{"a":1,"a":2}',
}.freeze

RSpec.describe "YAML engine parity" do
  def load_both(yaml)
    [Canon::YamlParsing.safe_load(yaml.dup, aliases: true),
     YAML.safe_load(yaml, permitted_classes: [Symbol, Date, Time],
                          aliases: true)]
  end

  # NaN != NaN in Ruby, so structural equality needs a NaN-aware pass.
  def deep_equal?(left, right)
    return true if left.equal?(right)
    return false unless left.instance_of?(right.class)
    return left.nan? && right.nan? if left.is_a?(Float) && (left.nan? || right.nan?)

    if left.is_a?(Hash)
      left.keys == right.keys &&
        left.keys.all? { |k| deep_equal?(left[k], right[k]) }
    elsif left.is_a?(Array)
      left.length == right.length && right.each_index.all? { |i| deep_equal?(left[i], right[i]) }
    else
      left == right
    end
  end

  it "default backend is Psych until parity gaps close" do
    expect(Canon::YamlBackend.active).to eq(:psych) unless Canon::YamlBackend.yeptris?
  end

  PARITY_CASES.each do |name, yaml|
    it "loads #{name} identically to Psych" do
      canon_loaded, psych_loaded = load_both(yaml)
      expect(deep_equal?(canon_loaded, psych_loaded)).to be(true)
    end
  end

  PENDING_UPSTREAM.each do |name, (yaml, reason)|
    xit "#{name} (#{reason})" do
      canon_loaded, psych_loaded = load_both(yaml)
      expect(canon_loaded).to eq(psych_loaded)
    end
  end

  # JSON parsing parity (yeptris uses Yeptris::YAML.load's JSON
  # auto-detection — native materializer). Pending cases are
  # YAML-only (#30/#31 do not apply to JSON; #29 fixed in 0.1.12).
  JSON_PARITY_CASES.each do |name, json|
    it "parses JSON #{name} identically to JSON.parse" do
      canon_loaded = Canon::JsonParsing.parse(json.dup)
      stdlib_loaded = JSON.parse(json)
      expect(deep_equal?(canon_loaded, stdlib_loaded)).to be(true)
    end
  end
end
