# frozen_string_literal: true

require "benchmark/ips"
require "json"
require "securerandom"
require "stringio"
require "time"
require "yaml"

lib_path = File.expand_path(File.join(__dir__, "..", "..", "lib"))
$LOAD_PATH.unshift(lib_path) unless $LOAD_PATH.include?(lib_path)

require "canon"

begin
  require "canon/xml/sax_builder"
  SAX_AVAILABLE = true
rescue LoadError
  SAX_AVAILABLE = false
end

# Standalone benchmark runner that emits JSON results on stdout.
#
# Used by performance_comparator.rb to run benchmarks in a clean Ruby
# process per branch — sharing no state with the comparator itself.
# This isolates each branch's Canon implementation from the other.
module Performance
  REPORT_ID = SecureRandom.hex(4).freeze

  DEFAULT_RUN_TIME = Integer(ENV.fetch("CANON_PERF_RUN_TIME", "5"))
  DEFAULT_WARMUP   = Integer(ENV.fetch("CANON_PERF_WARMUP", "2"))
  DEFAULT_ITEMS    = Integer(ENV.fetch("CANON_PERF_ITEMS", "50"))

  BENCHMARKS = {
    xml_parse_dom_simple: { category: "xml_parsing",    name: "DOM (simple)" },
    xml_parse_sax_simple: { category: "xml_parsing",    name: "SAX (simple)" },
    xml_parse_dom_large: { category: "xml_parsing",    name: "DOM (large)" },
    xml_parse_sax_large: { category: "xml_parsing",    name: "SAX (large)" },
    html_parse_simple: { category: "html_parsing", name: "Simple HTML" },
    html_parse_complex: { category: "html_parsing", name: "Complex HTML" },
    xml_compare_identical: { category: "xml_comparison", name: "Identical XML" },
    xml_compare_similar: { category: "xml_comparison", name: "Similar XML" },
    xml_compare_different: { category: "xml_comparison", name: "Different XML" },
    html_compare_identical: { category: "html_comparison", name: "Identical HTML" },
    html_compare_similar: { category: "html_comparison", name: "Similar HTML" },
    html_compare_different: { category: "html_comparison", name: "Different HTML" },
    xml_c14n_format: { category: "formatting", name: "XML C14N" },
    json_format: { category: "formatting",     name: "JSON" },
    yaml_format: { category: "formatting",     name: "YAML" },
  }.freeze

  module DataGenerator
    DEFAULT_ITEMS = Performance::DEFAULT_ITEMS

    class << self
      def generate_xml(items: DEFAULT_ITEMS, depth: 1, with_namespaces: false,
                       with_attributes: true)
        ns = with_namespaces ? 'xmlns:ns="http://example.org"' : ""
        prefix = with_namespaces ? "ns:" : ""

        build_xml_element(items, depth, prefix, with_attributes, ns)
      end

      def build_xml_element(items, depth, prefix, with_attrs, ns_decl)
        attrs = with_attrs ? " id=\"#{rand(1000)}\" status=\"active\"" : ""
        ns_attr = ns_decl.empty? ? "" : " #{ns_decl}"

        if depth <= 1
          children = Array.new(items) do |i|
            inner_attrs = with_attrs ? " index=\"#{i}\"" : ""
            "<#{prefix}item#{inner_attrs}>Item #{i} content with some text</#{prefix}item>"
          end.join
          "<#{prefix}root#{ns_attr}#{attrs}>#{children}</#{prefix}root>"
        else
          child = build_xml_element(items / 2, depth - 1, prefix, with_attrs,
                                    "")
          "<#{prefix}root#{ns_attr}#{attrs}>#{child}</#{prefix}root>"
        end
      end

      def generate_html(items: DEFAULT_ITEMS, with_scripts: false,
                        with_tables: false)
        scripts = if with_scripts
                    <<~HTML
                      <script type="text/javascript">
                        function test() { return true; }
                      </script>
                      <style>
                        body { margin: 0; }
                      </style>
                    HTML
                  else
                    ""
                  end

        tables = if with_tables
                   rows = Array.new(items) do |i|
                     "<tr><td>Cell #{i}A</td><td>Cell #{i}B</td></tr>"
                   end.join
                   "<table>#{rows}</table>"
                 else
                   ""
                 end

        list_items = Array.new(items) do |i|
          "<li class=\"item-#{i}\">List item #{i} with bold text</li>"
        end.join("\n              ")

        nav_count = [(items / 5), 2].max
        nav_items = items.times.first(nav_count).map do |i|
          "<li class=\"nav-#{i}\">Nav #{i}</li>"
        end.join("\n                ")

        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <title>Benchmark Document</title>
            #{scripts}
          </head>
          <body>
            <header>
              <h1>Benchmark Test Document</h1>
              <nav>
                <ul>
                #{nav_items}
                </ul>
              </nav>
            </header>
            <main>
              <section id="content">
                <p>This is a paragraph with emphasized and strong text.</p>
                <ul>
                #{list_items}
                </ul>
                #{tables}
              </section>
            </main>
            <footer>
              <p>Copyright 2024</p>
            </footer>
          </body>
          </html>
        HTML
      end

      def generate_json(items: DEFAULT_ITEMS)
        data = {
          metadata: { version: "1.0", generated: Time.now.iso8601 },
          items: Array.new(items) do |i|
            {
              id: i,
              name: "Item #{i}",
              value: rand * 1000,
              tags: ["tag1", "tag2", "tag#{i % 10}"],
              nested: {
                level1: { level2: { data: "deeply nested value #{i}" } },
              },
            }
          end,
        }
        JSON.generate(data)
      end

      def generate_yaml(items: DEFAULT_ITEMS)
        JSON.parse(generate_json(items: items)).to_yaml
      end

      def generate_large_xml(items: 500)
        generate_xml(items: items, depth: 3, with_namespaces: true,
                     with_attributes: true)
      end
    end
  end

  class Report
    def initialize(run_time: DEFAULT_RUN_TIME, warmup: DEFAULT_WARMUP,
                   items: DEFAULT_ITEMS)
      @run_time = run_time
      @warmup = warmup
      @items = items
      @results = {}
    end

    def run_all
      BENCHMARKS.each do |method, meta|
        next if method.to_s.start_with?("xml_parse_sax") && !SAX_AVAILABLE

        label = "#{meta[:category]}: #{meta[:name]}"
        @results[label] = run_benchmark(method)
      end
      @results
    end

    def as_json
      {
        report_id: REPORT_ID,
        ruby_version: RUBY_VERSION,
        platform: RUBY_PLATFORM,
        run_time: @run_time,
        warmup: @warmup,
        items: @items,
        sax_available: SAX_AVAILABLE,
        benchmarks: @results,
      }
    end

    private

    def run_benchmark(method)
      original_stdout = $stdout
      $stdout = StringIO.new
      begin
        job = Benchmark::IPS::Job.new
        job.config(time: @run_time, warmup: @warmup)
        job.report("test") { dispatch(method) }
        job.run

        entry = job.full_report.entries.first
      ensure
        $stdout = original_stdout
      end

      samples = entry.stats.samples
      return { lower: 0, upper: 0 } if samples.empty?

      mean = samples.sum.to_f / samples.size
      variance = samples.sum { |x| (x - mean)**2 } / (samples.size - 1)
      std_dev = Math.sqrt(variance)
      error_margin = std_dev / mean
      error_pct = error_margin.round(4)

      # Clamp lower bound to positive — for very fast operations the
      # error margin can exceed the mean, producing nonsensical
      # negative IPS values that break the regression comparison.
      lower = (mean * (1 - error_pct)).round(4)
      lower = (mean * 0.5).round(4) if lower <= 0
      upper = (mean * (1 + error_pct)).round(4)

      { lower: lower, upper: upper }
    end

    def dispatch(method)
      case method
      when :xml_parse_dom_simple
        Canon::Xml::DataModel.from_xml(DataGenerator.generate_xml(items: @items))
      when :xml_parse_sax_simple
        Canon::Xml::SaxBuilder.parse(DataGenerator.generate_xml(items: @items))
      when :xml_parse_dom_large
        Canon::Xml::DataModel.from_xml(DataGenerator.generate_large_xml(items: @items * 5))
      when :xml_parse_sax_large
        Canon::Xml::SaxBuilder.parse(DataGenerator.generate_large_xml(items: @items * 5))
      when :html_parse_simple
        Canon.parse_html(DataGenerator.generate_html(items: @items))
      when :html_parse_complex
        Canon.parse_html(DataGenerator.generate_html(items: @items,
                                                     with_scripts: true,
                                                     with_tables: true))
      when :xml_compare_identical
        xml = DataGenerator.generate_xml(items: @items)
        Canon::Comparison.equivalent?(xml, xml, format: :xml)
      when :xml_compare_similar
        Canon::Comparison.equivalent?(
          DataGenerator.generate_xml(items: @items),
          DataGenerator.generate_xml(items: @items),
          format: :xml,
        )
      when :xml_compare_different
        Canon::Comparison.equivalent?(
          DataGenerator.generate_xml(items: @items),
          DataGenerator.generate_xml(items: @items, with_namespaces: true),
          format: :xml,
        )
      when :html_compare_identical
        html = DataGenerator.generate_html(items: @items)
        Canon::Comparison.equivalent?(html, html, format: :html)
      when :html_compare_similar
        Canon::Comparison.equivalent?(
          DataGenerator.generate_html(items: @items),
          DataGenerator.generate_html(items: @items),
          format: :html,
        )
      when :html_compare_different
        Canon::Comparison.equivalent?(
          DataGenerator.generate_html(items: @items),
          DataGenerator.generate_html(items: @items, with_tables: true),
          format: :html,
        )
      when :xml_c14n_format
        Canon.format_xml(DataGenerator.generate_xml(items: @items,
                                                    with_namespaces: true))
      when :json_format
        Canon.format_json(JSON.parse(DataGenerator.generate_json(items: @items)))
      when :yaml_format
        Canon.format_yaml(YAML.safe_load(DataGenerator.generate_yaml(items: @items),
                                         permitted_classes: [Time]))
      else
        raise "Unknown benchmark: #{method}"
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  report = Performance::Report.new
  report.run_all
  puts JSON.generate(report.as_json)
end
