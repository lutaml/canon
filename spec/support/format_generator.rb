# frozen_string_literal: true

require "json"
require "yaml"

# Seeded corpus generator for the canonical-form property suites
# (TODO.sota/03, W1.5): taxonomy-class compositions per format,
# deterministic per seed. CANON_PROP_SEEDS (comma list) and
# CANON_PROP_CASES bound each leg — the nightly passes a random list.
module FormatGenerator
  WORDS = %w[alpha beta gamma delta epsilon zeta].freeze
  NAMES = %w[r a b sec p item entry node].freeze

  module_function

  def cases(seeds:, count:)
    seeds.flat_map do |seed|
      Array.new(count) do |i|
        rng = Random.new((seed * 1_000_000) + i)
        {
          id: "gen #{seed}/#{i}",
          json: JSON.generate(json_value(rng, 0)),
          yaml: YAML.dump(yaml_safe(json_value(rng, 0))),
          xml: xml_doc(rng),
          html: html_doc(rng),
        }
      end
    end
  end

  # -- JSON / YAML (Ruby object graphs) --

  def json_value(rng, depth)
    # at the depth cap only scalars remain reachable (2..4) — the
    # container picks (0, 1) would otherwise descend forever
    pick = depth < 3 ? rng.rand(6) : 2 + rng.rand(3)
    case pick
    when 0 then object(rng, depth + 1)
    when 1 then array(rng, depth + 1)
    when 2 then number(rng)
    when 3 then string_value(rng)
    else [true, false, nil].sample(random: rng)
    end
  end

  def object(rng, depth)
    h = {}
    rng.rand(1..4).times { h[string_value(rng)] = json_value(rng, depth) }
    h
  end

  def array(rng, depth)
    Array.new(rng.rand(0..4)) { json_value(rng, depth) }
  end

  def number(rng)
    shape = rng.rand(4)
    case shape
    when 0 then rng.rand(1000)
    when 1 then (rng.rand * 1000).round(6)
    when 2 then rng.rand < 0.5 ? 10**rng.rand(18) : (10**-rng.rand(6)).to_f
    else -rng.rand(1000)
    end
  end

  def string_value(rng)
    case rng.rand(6)
    when 0 then "#{WORDS.sample(random: rng)}-#{rng.rand(1000)}"
    when 1 then "with \"quote\" and \\ backslash"
    when 2 then "unicode héllo 日本語 ✓"
    when 3 then "tab\tand\nnewline mix"
    when 4 then ""
    else "ctrl \x01\x1F del\x7F"
    end
  end

  # YAML-safe: keys must be plain scalars (merge keys, aliases off)
  def yaml_safe(value)
    case value
    when Hash
      value.to_h { |k, v| [k, yaml_safe(v)] }
    when Array then value.map { |v| yaml_safe(v) }
    else value
    end
  end

  # -- XML --

  def xml_doc(rng)
    inner = xml_element(rng, 0, root: true)
    %(<?xml version="1.0"?>#{inner})
  end

  def xml_element(rng, depth, root: false)
    name = root ? "root" : NAMES.sample(random: rng)
    attrs = xml_attrs(rng)
    text = rng.rand(3).zero? ? "text #{rng.rand(100)}" : ""
    children = depth < 3 ? Array.new(rng.rand(1..3)) { xml_element(rng, depth + 1) } : []
    "<#{name}#{attrs}>#{text}#{children.join}</#{name}>"
  end

  def xml_attrs(rng)
    attrs = {}
    rng.rand(0..3).times { |i| attrs["attr#{i}"] = "v#{rng.rand(100)}" }
    attrs.map { |k, v| %( #{k}="#{v}") }.join
  end

  # -- HTML --

  def html_doc(rng)
    body = Array.new(rng.rand(1..3)) do
      case rng.rand(3)
      when 0 then "<p>paragraph #{rng.rand(100)}</p>"
      when 1 then "<br>"
      else "<div#{xml_attrs(rng)}>#{'text' if rng.rand(2).zero?}</div>"
      end
    end.join
    "<html><head><title>t</title></head><body>#{body}</body></html>"
  end

  # Equivalence-by-construction variants: the same document with key /
  # attribute ORDER shuffled. A canonical form must answer identical
  # bytes for both.
  def deep_shuffle_hash(value, rng)
    case value
    when Hash
      shuffled = {}
      value.keys.shuffle(random: rng).each do |k|
        shuffled[k] = deep_shuffle_hash(value[k], rng)
      end
      shuffled
    when Array then value.map { |v| deep_shuffle_hash(v, rng) }
    else value
    end
  end

  def shuffled_xml(xml, rng)
    xml.gsub(%r{<([a-z]+)((?:\s+[a-z0-9]+="[^"]*")*)\s*(/?)>}) do
      name = Regexp.last_match(1)
      attrs = Regexp.last_match(2).scan(/([a-z0-9]+="[^"]*")/).flatten
      attrs = attrs.shuffle(random: rng).map { |a| " #{a}" }.join
      "<#{name}#{attrs}#{Regexp.last_match(3)}>"
    end
  end
end
