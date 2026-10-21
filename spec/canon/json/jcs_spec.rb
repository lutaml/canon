# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe Canon::Json::JCS do
  def canonicalize(json)
    described_class.canonicalize(json)
  end

  # RFC 8785 §3.2.3 — the worked example (input as JSON text; the
  # canonical output is the RFC's).
  describe "the RFC 8785 §3.2.3 worked example" do
    it "canonicalizes byte-identically to the RFC's output" do
      input = <<~JSON
        {
          "numbers": [333333333.33333329, 1E30, 4.50, 2e-3, 0.000000000000000000000000001],
          "string": "\\u20ac$\\u000F\\u000aA'\\u0042\\u0022\\u005c\\\\\\"/",
          "literals": [null, true, false]
        }
      JSON
      expect(canonicalize(input)).to eq(
        '{"literals":[null,true,false],' \
        '"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],' \
        '"string":"€$\\u000f\\nA\'B\\"\\\\\\\\\\"/"}',
      )
    end
  end

  describe "number serialization (ECMA-262 Number::toString)" do
    {
      0 => "0",
      -0.0 => "0",
      0.1 => "0.1",
      -0.1 => "-0.1",
      1.0 => "1",
      -1.0 => "-1",
      123.456 => "123.456",
      0.000001 => "0.000001",
      1e-7 => "1e-7",
      1e20 => "100000000000000000000",
      1e21 => "1e+21",
      1e-27 => "1e-27",
      333333333.33333329 => "333333333.3333333",
      2e-3 => "0.002",
      4.50 => "4.5",
      1.2345678901234568e+21 => "1.2345678901234568e+21",
    }.each do |value, expected|
      it "serializes #{value.inspect} as #{expected.inspect}" do
        expect(canonicalize([value])).to eq("[#{expected}]")
      end
    end

    it "rejects non-finite numbers" do
      expect { canonicalize([Float::INFINITY]) }
        .to raise_error(Canon::Json::JCS::Error, /finite/)
      expect { canonicalize([Float::NAN]) }
        .to raise_error(Canon::Json::JCS::Error, /finite/)
    end

    it "rejects integers beyond the IEEE 754 double range (I-JSON)" do
      expect { canonicalize([9_007_199_254_740_993]) }
        .to raise_error(Canon::Json::JCS::Error, /I-JSON/)
    end
  end

  describe "key sorting (UTF-16 code units)" do
    it "sorts by UTF-16 code units, not codepoints" do
      # The famous UTF-16 divergence: an astral plane character's
      # surrogate pair starts at 0xD800, numerically BELOW U+E000..
      # U+FFFF — so U+10000 sorts BEFORE U+FFFD in UTF-16 order,
      # while codepoint order says the opposite. The canonical form
      # must pick UTF-16 (ECMAScript array sort semantics).
      expect(canonicalize({ "\u{10000}" => 1, "�" => 2 }))
        .to eq('{"𐀀":1,"�":2}')
    end

    it "puts the ASCII key first in the RFC example family" do
      expect(canonicalize({ "π" => 1, "e" => 2 })).to eq('{"e":2,"π":1}')
    end
  end

  describe "string escaping (RFC 8785 §3.2.2.2)" do
    {
      "quote" => "\"",
      "backslash" => "\\",
      "backspace" => "\b",
      "tab" => "\t",
      "newline" => "\n",
      "form feed" => "\f",
      "carriage return" => "\r",
      "unit separator (lowercase hex)" => "\x1F",
      "DEL is verbatim" => "\x7F",
    }.each do |name, src|
      it "escapes #{name} per JSON.stringify" do
        escaped = canonicalize({ "k" => src })
        raw = JSON.parse(escaped)
        expect(raw).to eq({ "k" => src })
      end
    end

    it "keeps the RFC example string byte-exact" do
      # the RFC example's string value: € $ U+000F LF A ' B " \ \ " /
      src = JSON.parse('"\\u20ac$\\u000F\\u000aA\'\\u0042\\u0022\\u005c\\\\\\"/"')
      out = canonicalize({ "string" => src })
      # canonical escaping: € and $ verbatim,  lowercase, \n
      # short form, ' B verbatim, \" for the quote, \\\\ for the two
      # backslashes, \" for the third, / verbatim
      expect(out).to eq('{"string":"€$\\u000f\\nA\'B\\"\\\\\\\\\\"/"}')
    end
  end

  describe "idempotence (JCS(JCS(x)) == JCS(x))" do
    it "holds across the vector corpus" do
      docs = [
        '{"a":1,"b":[true,null],"c":{"d":"e"}}',
        canonicalize({ "π" => 3.141592653589793, "z" => [1e21, 1e-7] }),
        "[1,2,3]",
        "{}",
        "[]",
        '{"unicode":"héllo 日本語 ✓","astral":"😀"}',
      ]
      docs.each do |doc|
        once = canonicalize(doc)
        expect(canonicalize(once)).to eq(once)
      end
    end
  end

  describe "determinism" do
    it "answers the same bytes for the same input" do
      input = { "b" => [3.5, nil], "a" => { "y" => 1, "x" => 2 } }
      first = canonicalize(input)
      10.times { expect(canonicalize(input)).to eq(first) }
    end
  end
end
