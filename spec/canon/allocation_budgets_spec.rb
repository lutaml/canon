# frozen_string_literal: true

require "spec_helper"
require "yaml"

# Allocation budgets (TODO.sota/04, W3.3): every measured lane
# carries a hard GC.stat object-count ceiling. Object counting is
# exact — the median delta over 15 runs is deterministic (min ==
# median on a quiet machine), so a budget breach is a REAL
# allocation regression, not clock noise.
#
# The committed ceilings live in spec/support/allocation_budgets.yml.
# Re-baseline with CANON_BUDGET_UPDATE=1 after verifying a delta is
# intentional.
BUDGETS_FILE = File.join(__dir__, "../support/allocation_budgets.yml").freeze
XML_DOC = '<root a="1" b="2"><child x="10">text</child><child/><tail>z</tail></root>'
XML_VARIANT = XML_DOC.gsub("><", ">\n<")
JSON_DOC = '{"b":[1,2,{"c":"d"}],"a":{"x":1,"y":[true,null]},"z":"str"}'
JSON_VARIANT = '{"z":"str","a":{"y":[true,null],"x":1},"b":[1,2,{"c":"d"}]}'
YAML_DOC = "b:\n- 1\n- 2\n- c: d\na:\n  x: 1\n  y:\n  - true\n  - ~\nz: str\n"
YAML_VARIANT = "z: str\na:\n  y:\n  - true\n  - ~\n  x: 1\nb:\n- 1\n- 2\n- c: d\n"
HTML_DOC = "<html><head><title>t</title></head><body><p>para</p><br>" \
           "<div id='x'>text</div></body></html>"
LANES = {
  "format_xml" => -> { Canon.format_xml(XML_DOC) },
  "format_json" => -> { Canon.format_json(JSON_DOC) },
  "format_yaml" => -> { Canon.format_yaml(YAML_DOC) },
  "format_html" => -> { Canon.format_html(HTML_DOC) },
  "parse_xml" => -> { Canon.parse_xml(XML_DOC) },
  "equiv_xml" => -> { Canon::Comparison.equivalent?(XML_DOC, XML_VARIANT, format: :xml) },
  "equiv_json" => -> { Canon::Comparison.equivalent?(JSON_DOC, JSON_VARIANT, format: :json) },
  "equiv_yaml" => -> { Canon::Comparison.equivalent?(YAML_DOC, YAML_VARIANT, format: :yaml) },
  "jcs" => -> { Canon::Json::JCS.canonicalize(JSON.parse(JSON_DOC)) },
}.freeze

RSpec.describe "allocation budgets" do
  let(:lanes) { LANES }
  let(:budgets) { YAML.safe_load_file(BUDGETS_FILE) }

  def median_allocation_delta(lane)
    call = lanes.fetch(lane)
    call.call # warmup: lazy loads and per-process caches are not the lane's cost
    deltas = Array.new(15) do
      before = GC.stat(:total_allocated_objects)
      call.call
      GC.stat(:total_allocated_objects) - before
    end
    deltas.sort![7]
  end

  it "has a budget entry for every measured lane" do
    missing = lanes.keys - budgets.keys
    extra = budgets.keys - lanes.keys
    expect(missing).to be_empty, "lanes without budgets: #{missing.join(', ')}"
    expect(extra).to be_empty, "budgets without lanes: #{extra.join(', ')}"
  end

  it "keeps every lane within its committed allocation ceiling" do
    breaches = []
    updated = {}
    budgets.each do |lane, ceiling|
      median = median_allocation_delta(lane)
      if median > ceiling
        if ENV["CANON_BUDGET_UPDATE"]
          updated[lane] = median
        else
          breaches << "#{lane}: median #{median} > ceiling #{ceiling} " \
                      "(+#{median - ceiling}); re-baseline with " \
                      "CANON_BUDGET_UPDATE=1 only if the delta is intentional"
        end
      end
    end
    unless updated.empty?
      header = File.readlines(BUDGETS_FILE)
        .take_while { |line| line.start_with?("#") }.join
      body = budgets.merge(updated)
      note = updated.map { |lane, med| "#{lane}: #{budgets[lane]} -> #{med}" }.join("; ")
      File.write(BUDGETS_FILE,
                 "#{header}\n# re-baselined #{Time.now.strftime('%Y-%m-%d')}: " \
                 "#{note}\n#{YAML.dump(body)}")
    end
    expect(breaches).to be_empty, breaches.join("\n")
  end
end
